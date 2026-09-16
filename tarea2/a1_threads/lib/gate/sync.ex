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

  ## This assignment: threads and a mutex

  There is no shared mutable memory on the BEAM once `Agent`, `GenServer` and `:ets` are
  off the table, so the only place a sector's state can live is inside one process's own
  loop variable. That process is spawned once per sector, in `start/1`, and never touches
  any other sector.

  A caller of `update/3` never reads or writes that state directly. It sends the pure
  transition to the owning process and blocks in `receive` for the single reply. The
  owning process serves its mailbox one message at a time, which is exactly the property
  a mutex gives you around a critical section: whichever request arrives first gets the
  state, runs `fun` to completion, publishes the new state as its own next loop argument,
  and only then looks at the next message. Two concurrent callers on the same sector are
  serialized by the mailbox; callers on different sectors never wait on each other,
  because they talk to different processes.

  There is exactly one round trip per `update/3` call (one `send`, one `receive`), so
  there is nothing to forget to release and nothing to hold across a `receive`: the
  section that would need a mutex in a threaded language is entirely inside the owning
  process, which cannot be preempted mid-step by another message.
  """

  @typedoc "One sector name mapped to the pid of the process that owns its state."
  @type venue :: %{Gate.API.sector() => pid}

  @doc "Set up whatever owns the state, and return the handle for it."
  @spec start(Gate.API.venue_spec()) :: {:ok, venue} | {:error, term}
  def start(spec) do
    sectors =
      for {name, shape} <- spec.sectors, into: %{} do
        sector = Gate.Sector.new(name, shape, spec.ttl_ms)
        {name, spawn(fn -> loop(sector) end)}
      end

    {:ok, sectors}
  end

  @doc "Take it all down. Calling this twice must still work."
  @spec stop(venue) :: :ok
  def stop(venue) do
    Enum.each(venue, fn {_name, pid} -> send(pid, :stop) end)
    :ok
  end

  @doc "Sector names of a running venue."
  @spec sectors(venue) :: [Gate.API.sector()]
  def sectors(venue), do: Map.keys(venue)

  @doc """
  Run a pure transition against one sector, as one indivisible step.

  See the module documentation. This function is the whole assignment.
  """
  @spec update(venue, Gate.API.sector(), (Gate.Sector.t(), integer -> {result, Gate.Sector.t()})) ::
          result | {:error, :bad_sector}
        when result: term
  def update(venue, sector, fun) do
    case Map.fetch(venue, sector) do
      {:ok, pid} ->
        ref = make_ref()
        send(pid, {:update, fun, ref, self()})

        receive do
          {:reply, ^ref, result} -> result
        end

      :error ->
        {:error, :bad_sector}
    end
  end

  defp loop(state) do
    receive do
      {:update, fun, ref, from} ->
        now = System.monotonic_time(:millisecond)

        try do
          {result, new_state} = fun.(state, now)
          send(from, {:reply, ref, result})
          loop(new_state)
        rescue
          # A transition must never take the whole sector down with it: without this,
          # one bad `fun` would crash the owning process and hang every caller forever.
          _ ->
            send(from, {:reply, ref, {:error, :internal_error}})
            loop(state)
        end

      :stop ->
        :ok
    end
  end
end
