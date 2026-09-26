defmodule Gate.Sync do
  @moduledoc """
  The concurrency layer. This is the file that changes between the four assignments, and
  in assignments 2, 3 and 4 it is the only one.

  It has one job. `Gate.Venue` hands it a pure transition and the name of a sector, and it
  has to run that transition somewhere safe and give the answer back. Safe, meaning:  two
  clients touching the same sector cannot see or lose each other's work.

  Everything about processes lives here and only here. `spawn`, `send`, `receive`,`Task`,
  `Process`, and whatever you build out of them.

  ## The contract

      update(venue, sector, fun)

  where `fun` takes the current sector value and the current time in milliseconds and
  returns `{result, new_sector_value}`. `update/3` returns the `result`, or
  `{:error, :bad_sector}` if there is no such sector.

  The whole of `fun` has to happen as one indivisible step. Reading the sector, working
  out the answer, and writing the sector back cannot be three steps that another client
  can slip between. How you arrange that is the assignment.

  ## This assignment: software transactional memory

  Each sector's state lives in one transactional variable, a TVar: a process whose only
  loop variables are the current value and a version number that goes up by one on every
  successful write. A TVar never runs a transition. It answers two requests and nothing
  else:

    * `read`, which returns the current `{version, value}` pair, and
    * `commit(expected_version, new_value)`, which installs `new_value` only if the
      version is still `expected_version`, and otherwise answers `:conflict`. The version
      is checked before the value is sent, the way a TL2 commit takes a versioned write
      lock, so a commit that is going to lose never ships the sector at all.

  `update/3` is the transaction, and it runs in the caller's own process. It reads the
  TVar, takes the time, runs `fun` on its private copy of the value, and tries to commit.
  If nobody else committed to that sector in between, the commit succeeds and the result
  is returned. If somebody did, the value `fun` saw is stale, so the attempt is thrown
  away whole and the transaction starts again from a fresh read. This is optimistic
  concurrency: nobody holds anything while `fun` runs, many clients can be computing
  against the same sector at the same time, and the only thing serialized is the commit:
  the version check plus the hand over of the new value, never the transition itself.

  Re-running is safe because `fun` is a pure function of `(value, now)`: an attempt that
  loses the race has touched nothing but its own copy, so throwing it away leaves no
  trace. A result is only ever returned from an attempt that committed, which is what
  keeps a hold id, a ticket or a `:sold_out` from being handed out on a stale view. A
  transition that changes nothing (a failed reserve, `availability`, a `snapshot` with
  nothing to expire) is a read-only transaction and skips the commit: one read of one
  TVar is already a consistent view of that sector at the moment it was taken.

  Conflicts are per sector, because each sector is its own TVar: a transaction on one
  sector never reads, validates against, or waits for another. The retry is not the
  caller waiting for anyone, it is the transaction re-executing against newer data, so
  `reserve/4` still never queues behind a cancel and still fails at once when the
  committed state says it must.
  """

  @typedoc "One sector name mapped to the pid of the TVar that holds its state."
  @type venue :: %{Gate.API.sector() => pid}

  @typedoc "A pure transition of one sector, given the current time in milliseconds."
  @type transition(result) :: (Gate.Sector.t(), integer -> {result, Gate.Sector.t()})

  @doc "Set up whatever owns the state, and return the handle for it."
  @spec start(Gate.API.venue_spec()) :: {:ok, venue} | {:error, term}
  def start(spec) do
    sectors =
      for {name, shape} <- spec.sectors, into: %{} do
        sector = Gate.Sector.new(name, shape, spec.ttl_ms)
        {name, spawn(fn -> tvar(0, sector) end)}
      end

    {:ok, sectors}
  end

  @doc "Take it all down. Calling this twice must still work."
  @spec stop(venue) :: :ok
  def stop(venue) do
    Enum.each(venue, fn {_name, tvar} -> send(tvar, :stop) end)
    :ok
  end

  @doc "Sector names of a running venue."
  @spec sectors(venue) :: [Gate.API.sector()]
  def sectors(venue), do: Map.keys(venue)

  @doc """
  Run a pure transition against one sector, as one indivisible step.

  See the module documentation. This function is the whole assignment.
  """
  @spec update(venue, Gate.API.sector(), transition(result)) :: result | {:error, :bad_sector}
        when result: term
  def update(venue, sector, fun) do
    case Map.fetch(venue, sector) do
      {:ok, tvar} ->
        # The monitor ref doubles as the tag of every request this transaction sends, and
        # turns a stopped venue into an error instead of a caller blocked forever.
        tag = Process.monitor(tvar)
        result = atomically(tvar, tag, fun)
        Process.demonitor(tag, [:flush])
        result

      :error ->
        {:error, :bad_sector}
    end
  end

  # One transaction: read, compute on a private copy, validate and commit, or start over.
  defp atomically(tvar, tag, fun) do
    with {:ok, version, state} <- read(tvar, tag) do
      now = System.monotonic_time(:millisecond)

      case run(fun, state, now) do
        {:ok, result, ^state} ->
          result

        {:ok, result, new_state} ->
          case commit(tvar, tag, version, new_state) do
            :ok -> result
            :conflict -> atomically(tvar, tag, fun)
            {:error, reason} -> {:error, reason}
          end

        :error ->
          {:error, :internal_error}
      end
    end
  end

  # A transition must never take anything down with it. Nothing has been written yet, so
  # the sector stays exactly as it was and the caller gets an error instead of a crash.
  defp run(fun, state, now) do
    {result, new_state} = fun.(state, now)
    {:ok, result, new_state}
  rescue
    _ -> :error
  end

  defp read(tvar, tag) do
    send(tvar, {:read, self(), tag})

    receive do
      {^tag, version, state} -> {:ok, version, state}
      {:DOWN, ^tag, :process, _pid, _reason} -> {:error, :bad_sector}
    end
  end

  # Validate first with a message that carries only the version, and ship the new value
  # only once the TVar has granted the write. A sector is tens to hundreds of kilobytes,
  # so sending it with every attempt would flood the TVar with values that are about to be
  # rejected anyway; this way a losing attempt costs two small messages.
  defp commit(tvar, tag, version, state) do
    send(tvar, {:lock, self(), tag, version})

    receive do
      {^tag, :locked, lock} ->
        send(tvar, {lock, state})
        :ok

      {^tag, :conflict} ->
        :conflict

      {:DOWN, ^tag, :process, _pid, _reason} ->
        {:error, :bad_sector}
    end
  end

  # The TVar. It holds the committed value and its version, and user code never runs in
  # here. A lock is granted only to a transaction whose read version is still current, and
  # it lasts exactly until that transaction's value arrives, so readers never see anything
  # but whole committed values. If the writer dies in between, the monitor gives the lock
  # back and the old value stays.
  defp tvar(version, state) do
    receive do
      {:read, from, tag} ->
        send(from, {tag, version, state})
        tvar(version, state)

      {:lock, from, tag, ^version} ->
        lock = Process.monitor(from)
        send(from, {tag, :locked, lock})

        receive do
          {^lock, new_state} ->
            Process.demonitor(lock, [:flush])
            tvar(version + 1, new_state)

          {:DOWN, ^lock, :process, _pid, _reason} ->
            tvar(version, state)
        end

      {:lock, from, tag, _stale} ->
        send(from, {tag, :conflict})
        tvar(version, state)

      :stop ->
        :ok
    end
  end
end
