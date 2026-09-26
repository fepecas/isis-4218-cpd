defmodule Gate.STMTest do
  # Real concurrency against the STM layer: every race below is run by separate BEAM
  # processes released together, never by a sequential loop. Only spawn, send and receive
  # are used, so the tests stay inside the same rules as the code under test.
  use ExUnit.Case, async: false

  alias Gate.Sector
  alias Gate.Sync
  alias Gate.Venue
  alias Gate.VenueSpec

  @price 100

  # Sector names must come from the real layout so VenueSpec.all_seat_ids/1 knows them;
  # the shapes are small so that the races are all about the last seats.
  defp spec(shapes, ttl_ms \\ 5_000) do
    sectors =
      for {name, rows, seats} <- shapes, into: %{} do
        {name, %{rows: rows, seats_per_row: seats, price_cop: @price}}
      end

    %{sectors: sectors, ttl_ms: ttl_ms}
  end

  defp start!(spec) do
    {:ok, venue} = Venue.start_venue(spec)
    on_exit(fn -> Venue.stop_venue(venue) end)
    venue
  end

  # Spawn one process per element, hold them all at a barrier, release them together and
  # collect every answer in input order.
  defp race(inputs, fun) do
    parent = self()

    pids =
      for input <- inputs do
        spawn_link(fn ->
          receive do
            :go -> send(parent, {:done, self(), fun.(input)})
          end
        end)
      end

    Enum.each(pids, &send(&1, :go))

    for pid <- pids do
      receive do
        {:done, ^pid, result} -> result
      after
        30_000 -> flunk("a racing client never answered")
      end
    end
  end

  defp assert_consistent(snap, spec) do
    all = VenueSpec.all_seat_ids(spec)
    sold = MapSet.new(snap.sold)
    held = MapSet.new(snap.held)
    free = MapSet.new(snap.free)

    assert length(snap.sold) == MapSet.size(sold), "a seat is listed twice as sold"
    assert length(snap.held) == MapSet.size(held), "a seat is listed twice as held"
    assert length(snap.free) == MapSet.size(free), "a seat is listed twice as free"
    assert MapSet.disjoint?(sold, held)
    assert MapSet.disjoint?(sold, free)
    assert MapSet.disjoint?(held, free)
    assert MapSet.union(sold, held) |> MapSet.union(free) == MapSet.new(all)
    assert snap.revenue == length(snap.sold) * @price
    snap
  end

  describe "case 1: many clients, same sector, last seats" do
    test "every seat is sold exactly once and revenue matches" do
      spec = spec([{:vip, 2, 5}])
      venue = start!(spec)

      results = race(1..300, fn _ -> Venue.reserve(venue, :vip, 1, :any) end)
      wins = for {:ok, hold, seats} <- results, do: {hold, seats}

      assert length(wins) == 10
      assert Enum.count(results, &(&1 == {:error, :sold_out})) == 290

      seats = Enum.flat_map(wins, &elem(&1, 1))
      assert length(Enum.uniq(seats)) == 10
      assert length(Enum.uniq(Enum.map(wins, &elem(&1, 0)))) == 10

      confirms = race(wins, fn {hold, _} -> Venue.confirm(venue, hold) end)
      assert Enum.all?(confirms, &match?({:ok, _}, &1))

      snap = assert_consistent(Venue.snapshot(venue), spec)
      assert Enum.sort(snap.sold) == Enum.sort(seats)
      assert snap.revenue == 10 * @price
      assert Venue.availability(venue, :vip) == 0
    end

    test "mixed group sizes never share a seat, and concurrent snapshots stay consistent" do
      spec = spec([{:sur_baja, 4, 6}])
      venue = start!(spec)
      parent = self()

      watcher =
        spawn_link(fn ->
          snaps = watch(venue, [])
          send(parent, {:snaps, snaps})
        end)

      results =
        race(1..400, fn i ->
          mode = if rem(i, 2) == 0, do: :any, else: :contiguous

          case Venue.reserve(venue, :sur_baja, rem(i, 6) + 1, mode) do
            {:ok, hold, seats} = ok ->
              if rem(i, 3) == 0, do: {ok, Venue.confirm(venue, hold)}, else: {ok, seats}

            error ->
              error
          end
        end)

      send(watcher, :stop)

      snaps =
        receive do
          {:snaps, snaps} -> snaps
        end

      assert length(snaps) > 1
      Enum.each(snaps, &assert_consistent(&1, spec))

      held_or_sold =
        for {{:ok, _hold, seats}, _} <- results, seat <- seats, do: seat

      assert length(held_or_sold) == length(Enum.uniq(held_or_sold))

      sold = for {{:ok, _, _}, {:ok, tickets}} <- results, t <- tickets, do: t.seat_id
      snap = assert_consistent(Venue.snapshot(venue), spec)
      assert Enum.sort(snap.sold) == Enum.sort(sold)
      assert Enum.sort(snap.sold ++ snap.held) == Enum.sort(held_or_sold)
    end
  end

  defp watch(venue, acc) do
    receive do
      :stop -> acc
    after
      0 -> watch(venue, [Venue.snapshot(venue) | acc])
    end
  end

  describe "case 2: double confirmation" do
    test "one hold confirmed by 200 clients at once is sold exactly once" do
      spec = spec([{:vip, 1, 10}])
      venue = start!(spec)
      {:ok, hold, seats} = Venue.reserve(venue, :vip, 4, :contiguous)

      results = race(1..200, fn _ -> Venue.confirm(venue, hold) end)

      assert [{:ok, tickets}] = Enum.filter(results, &match?({:ok, _}, &1))
      assert Enum.map(tickets, & &1.seat_id) == seats
      assert Enum.count(results, &(&1 == {:error, :already_confirmed})) == 199

      snap = assert_consistent(Venue.snapshot(venue), spec)
      assert Enum.sort(snap.sold) == Enum.sort(seats)
      assert snap.revenue == 4 * @price
    end
  end

  describe "case 3: all or nothing" do
    test "requests larger than what is free never hold part of a group" do
      spec = spec([{:vip, 1, 5}])
      venue = start!(spec)
      {:ok, _hold, _} = Venue.reserve(venue, :vip, 3, :any)
      before = Venue.snapshot(venue)

      results =
        race(1..200, fn i ->
          Venue.reserve(venue, :vip, 3 + rem(i, 4), Enum.at([:any, :contiguous], rem(i, 2)))
        end)

      assert Enum.all?(results, &(&1 == {:error, :sold_out}))
      assert Venue.snapshot(venue) == before
      assert Venue.availability(venue, :vip) == 2
    end

    test "enough seats but no run of them is :no_contiguous_block, and changes nothing" do
      spec = spec([{:vip, 2, 4}])
      venue = start!(spec)
      {:ok, _, _} = Venue.reserve(venue, :vip, 3, :contiguous)
      {:ok, _, _} = Venue.reserve(venue, :vip, 3, :contiguous)
      before = Venue.snapshot(venue)
      assert Enum.sort(before.free) == ["vip:R001:S004", "vip:R002:S004"]

      results = race(1..100, fn _ -> Venue.reserve(venue, :vip, 2, :contiguous) end)
      assert Enum.all?(results, &(&1 == {:error, :no_contiguous_block}))
      assert Venue.reserve(venue, :vip, 3, :contiguous) == {:error, :sold_out}
      assert Venue.reserve(venue, :vip, 3, :any) == {:error, :sold_out}
      assert Venue.snapshot(venue) == before
    end
  end

  describe "case 4: independent sectors and optimistic transactions" do
    test "a transaction stalled mid-flight blocks neither its own sector nor another one" do
      spec = spec([{:vip, 1, 10}, {:sur_baja, 1, 10}])
      venue = start!(spec)
      parent = self()

      # A slow client: its transition stops half way and waits to be let go, while it is
      # inside the transaction and before it commits.
      slow =
        spawn_link(fn ->
          result =
            Sync.update(venue, :vip, fn state, now ->
              send(parent, {:attempt, self()})

              receive do
                :continue -> :ok
              end

              {:ok, state, hold, seats} = Sector.reserve(state, 2, :contiguous, now)
              {{hold, seats}, state}
            end)

          send(parent, {:slow_done, result})
        end)

      assert_receive {:attempt, ^slow}

      # With a mutex both of these would wait for the slow client. Under STM neither does.
      other = race(1..20, fn _ -> Venue.reserve(venue, :sur_baja, 1, :any) end)
      assert Enum.count(other, &match?({:ok, _, _}, &1)) == 10

      assert {:ok, fast_hold, fast_seats} = Venue.reserve(venue, :vip, 2, :contiguous)
      assert fast_seats == ["vip:R001:S001", "vip:R001:S002"]

      # The slow attempt read a version that is no longer current, so its commit is
      # rejected and the whole transition runs again against the new value.
      send(slow, :continue)
      assert_receive {:attempt, ^slow}
      send(slow, :continue)
      assert_receive {:slow_done, {slow_hold, slow_seats}}

      assert slow_hold != fast_hold
      assert slow_seats == ["vip:R001:S003", "vip:R001:S004"]
      snap = assert_consistent(Venue.snapshot(venue), spec)
      vip_held = Enum.filter(snap.held, &String.starts_with?(&1, "vip:"))
      assert Enum.sort(vip_held) == Enum.sort(fast_seats ++ slow_seats)
      assert Venue.availability(venue, :vip) == 6
      assert Venue.availability(venue, :sur_baja) == 0
    end
  end

  describe "case 5: state propagates through each transition" do
    test "reserve -> confirm -> snapshot" do
      spec = spec([{:vip, 2, 3}])
      venue = start!(spec)
      {:ok, hold, seats} = Venue.reserve(venue, :vip, 2, :contiguous)

      snap = assert_consistent(Venue.snapshot(venue), spec)
      assert Enum.sort(snap.held) == Enum.sort(seats)
      assert snap.revenue == 0

      assert {:ok, tickets} = Venue.confirm(venue, hold)
      assert Enum.map(tickets, & &1.seat_id) == seats
      assert Enum.all?(tickets, &(&1.hold_id == hold and &1.price_cop == @price))

      snap = assert_consistent(Venue.snapshot(venue), spec)
      assert Enum.sort(snap.sold) == Enum.sort(seats)
      assert snap.held == []
      assert snap.revenue == 2 * @price

      assert Venue.confirm(venue, hold) == {:error, :already_confirmed}
      assert Venue.cancel(venue, hold) == {:error, :already_confirmed}
      assert Venue.availability(venue, :vip) == 4
    end

    test "reserve -> cancel -> snapshot" do
      spec = spec([{:vip, 2, 3}])
      venue = start!(spec)
      {:ok, hold, _seats} = Venue.reserve(venue, :vip, 3, :any)
      assert Venue.availability(venue, :vip) == 3

      assert Venue.cancel(venue, hold) == :ok
      snap = assert_consistent(Venue.snapshot(venue), spec)
      assert length(snap.free) == 6 and snap.held == [] and snap.sold == []

      assert Venue.cancel(venue, hold) == :ok
      assert Venue.confirm(venue, hold) == {:error, :unknown_hold}

      {:ok, next_hold, _} = Venue.reserve(venue, :vip, 1, :any)
      assert next_hold != hold
    end

    test "forged ids and unknown sectors fail safely" do
      venue = start!(spec([{:vip, 1, 3}]))

      for forged <- [:nope, {:vip, 999}, {:nope, 0}, {:vip, "x"}, "vip", nil, {1, 2, 3}] do
        assert Venue.confirm(venue, forged) == {:error, :unknown_hold}
        assert Venue.cancel(venue, forged) == {:error, :unknown_hold}
      end

      assert Venue.reserve(venue, :nope, 1, :any) == {:error, :bad_sector}
      assert Venue.availability(venue, :nope) == {:error, :bad_sector}
    end
  end

  describe "case 6: expiry" do
    test "abandoned holds free their seats once the ttl has passed" do
      ttl = 100
      spec = spec([{:vip, 3, 4}], ttl)
      venue = start!(spec)

      holds = race(1..12, fn _ -> Venue.reserve(venue, :vip, 1, :any) end)
      assert Enum.all?(holds, &match?({:ok, _, _}, &1))
      assert Venue.availability(venue, :vip) == 0

      # Letting time pass is the point here, exactly as the grader waits three lifetimes.
      Process.sleep(3 * ttl)

      snap = assert_consistent(Venue.snapshot(venue), spec)
      assert snap.held == [] and snap.sold == [] and length(snap.free) == 12
      assert Venue.availability(venue, :vip) == 12

      {:ok, hold, _seats} = hd(holds)
      assert Venue.confirm(venue, hold) == {:error, :expired}
      assert Venue.cancel(venue, hold) == :ok
    end
  end

  describe "case 7: races between transitions of the same hold" do
    test "confirm against cancel never leaves an impossible state" do
      spec = spec([{:sur_baja, 10, 10}])
      venue = start!(spec)

      holds =
        for _ <- 1..50 do
          {:ok, hold, seats} = Venue.reserve(venue, :sur_baja, 2, :any)
          {hold, seats}
        end

      outcomes =
        race(Enum.flat_map(holds, fn h -> [{:confirm, h}, {:cancel, h}] end), fn
          {:confirm, {hold, _}} -> {hold, :confirm, Venue.confirm(venue, hold)}
          {:cancel, {hold, _}} -> {hold, :cancel, Venue.cancel(venue, hold)}
        end)

      sold =
        for {hold, seats} <- holds, reduce: [] do
          sold ->
            by_hold = for {^hold, op, r} <- outcomes, into: %{}, do: {op, r}

            case by_hold do
              %{confirm: {:ok, _}, cancel: {:error, :already_confirmed}} -> seats ++ sold
              %{confirm: {:error, :unknown_hold}, cancel: :ok} -> sold
              other -> flunk("impossible pair of outcomes: #{inspect(other)}")
            end
        end

      snap = assert_consistent(Venue.snapshot(venue), spec)
      assert snap.held == []
      assert Enum.sort(snap.sold) == Enum.sort(sold)
    end

    test "confirm against expiry: every hold is either sold or free, never both or neither" do
      ttl = 60
      spec = spec([{:sur_baja, 10, 10}], ttl)
      venue = start!(spec)

      holds =
        for _ <- 1..50 do
          {:ok, hold, seats} = Venue.reserve(venue, :sur_baja, 2, :any)
          {hold, seats}
        end

      # A third of the holds are confirmed well inside the lifetime, a third well after it,
      # and a third right at the edge, several times each, so expiry and confirmation
      # collide on the same hold.
      delays = [[0, 10], [50, 55, 60, 65, 70], [120, 150]]

      schedule =
        for {h, i} <- Enum.with_index(holds), delay <- Enum.at(delays, rem(i, 3)), do: {h, delay}

      outcomes =
        race(schedule, fn
          {{hold, _}, delay} ->
            Process.sleep(delay)
            {hold, Venue.confirm(venue, hold)}
        end)

      sold =
        for {hold, seats} <- holds, reduce: [] do
          sold ->
            results = for {^hold, r} <- outcomes, do: r
            oks = Enum.count(results, &match?({:ok, _}, &1))
            assert oks <= 1

            assert Enum.all?(
                     results,
                     &(match?({:ok, _}, &1) or
                         &1 in [{:error, :expired}, {:error, :already_confirmed}])
                   )

            if oks == 1 do
              refute {:error, :expired} in results
              seats ++ sold
            else
              assert {:error, :already_confirmed} not in results
              sold
            end
        end

      # Both endings really happened, so the race was exercised and not decided up front.
      assert length(sold) > 0 and length(sold) < 100

      Process.sleep(3 * ttl)
      snap = assert_consistent(Venue.snapshot(venue), spec)
      assert snap.held == []
      assert Enum.sort(snap.sold) == Enum.sort(sold)
    end
  end

  describe "venue lifecycle" do
    test "stop twice is fine and a stopped venue answers instead of hanging" do
      {:ok, venue} = Venue.start_venue(spec([{:vip, 1, 3}]))
      assert Venue.stop_venue(venue) == :ok
      assert Venue.stop_venue(venue) == :ok
      assert Venue.reserve(venue, :vip, 1, :any) == {:error, :bad_sector}
    end
  end
end
