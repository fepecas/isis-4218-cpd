defmodule Gate.Sector do
  @moduledoc """
  All the ticketing rules for one sector. Pure data and pure functions. No processes, no
  messages, no locks, not one of them anywhere in this file.

  Take into account:

  - Write it in assignment 1 and copy it into the next three without touching a line.
  - This is the part of the project that does not change between the four assignments, so
    it is worth getting right once!
  - If you find yourself editing it in assignment 2, the boundary between the rules and
    the model is in the wrong place!

  """

  alias Gate.Row
  alias Gate.VenueSpec

  @typedoc "Where a hold stands. `:held` is the only state still counted in `pending`."
  @type hold_state :: :held | :confirmed | :cancelled | :expired

  @typedoc """
  Bookkeeping for one `reserve/4` call. `row_seats` and `seats` are fixed at hold
  time and never recomputed, so the seats a client is shown are the seats it gets.
  """
  @type hold :: %{
          status: hold_state,
          row_seats: [{row_no :: pos_integer, seat_no :: pos_integer}],
          seats: [Gate.API.seat_id()],
          held_at: integer
        }

  @typedoc """
  One sector's state. `holds` keeps every hold ever issued, by final state, so a
  `hold_id` is never mistaken for one from another sector or reused. `pending` is
  the subset still `:held`, checked against `ttl_ms` on every call before anything
  else runs. `free` is the seat count kept in sync with `rows` on every mutation.
  """
  @type t :: %__MODULE__{
          name: Gate.API.sector(),
          price_cop: pos_integer,
          ttl_ms: pos_integer,
          rows: %{pos_integer => Row.t()},
          holds: %{Gate.API.hold_id() => hold},
          pending: MapSet.t(Gate.API.hold_id()),
          free: non_neg_integer,
          next_ref: non_neg_integer
        }

  defstruct [:name, :price_cop, :ttl_ms, :rows, :holds, :pending, :free, :next_ref]

  @doc "An empty sector, built from one entry of a venue spec."
  @spec new(Gate.API.sector(), map, pos_integer) :: t
  def new(name, shape, ttl_ms) do
    rows =
      for row_no <- 1..shape.rows, into: %{} do
        {row_no, Row.new(shape.seats_per_row)}
      end

    %__MODULE__{
      name: name,
      price_cop: shape.price_cop,
      ttl_ms: ttl_ms,
      rows: rows,
      holds: %{},
      pending: MapSet.new(),
      free: shape.rows * shape.seats_per_row,
      next_ref: 0
    }
  end

  @doc """
  Hold `qty` seats and say which ones, or say why not.

  All of the seats or none of them. A request that cannot be served leaves the sector
  exactly as it was.
  """
  @spec reserve(t, pos_integer, :any | :contiguous, integer) ::
          {:ok, t, Gate.API.hold_id(), [Gate.API.seat_id()]}
          | {:error, :sold_out | :no_contiguous_block}
  def reserve(sector, qty, mode, now) do
    sector = sweep(sector, now)

    case alloc(sector, qty, mode) do
      {:ok, sector, row_seats} ->
        hold_id = {sector.name, sector.next_ref}

        seat_ids =
          for {row_no, seat_no} <- row_seats, do: VenueSpec.seat_id(sector.name, row_no, seat_no)

        hold = %{status: :held, row_seats: row_seats, seats: seat_ids, held_at: now}

        sector = %{
          sector
          | holds: Map.put(sector.holds, hold_id, hold),
            pending: MapSet.put(sector.pending, hold_id),
            next_ref: sector.next_ref + 1
        }

        {:ok, sector, hold_id, seat_ids}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Sell the seats of a live hold, all of them together."
  @spec confirm(t, Gate.API.hold_id(), integer) ::
          {:ok, t, [Gate.API.ticket()]}
          | {:error, :expired | :unknown_hold | :already_confirmed}
  def confirm(sector, hold_id, now) do
    sector = sweep(sector, now)

    case Map.fetch(sector.holds, hold_id) do
      :error ->
        {:error, :unknown_hold}

      {:ok, %{status: :held} = hold} ->
        rows = update_rows(sector.rows, hold.row_seats, &Row.sell/2)

        tickets =
          for seat_id <- hold.seats do
            %{
              seat_id: seat_id,
              sector: sector.name,
              price_cop: sector.price_cop,
              hold_id: hold_id
            }
          end

        sector = %{
          sector
          | rows: rows,
            holds: Map.put(sector.holds, hold_id, %{hold | status: :confirmed}),
            pending: MapSet.delete(sector.pending, hold_id)
        }

        {:ok, sector, tickets}

      {:ok, %{status: :confirmed}} ->
        {:error, :already_confirmed}

      {:ok, %{status: :expired}} ->
        {:error, :expired}

      {:ok, %{status: :cancelled}} ->
        {:error, :unknown_hold}
    end
  end

  @doc "Give up a hold and free its seats."
  @spec cancel(t, Gate.API.hold_id(), integer) ::
          {:ok, t} | {:error, :unknown_hold | :already_confirmed}
  def cancel(sector, hold_id, now) do
    sector = sweep(sector, now)

    case Map.fetch(sector.holds, hold_id) do
      :error ->
        {:error, :unknown_hold}

      {:ok, %{status: :held} = hold} ->
        rows = update_rows(sector.rows, hold.row_seats, &Row.release/2)

        sector = %{
          sector
          | rows: rows,
            holds: Map.put(sector.holds, hold_id, %{hold | status: :cancelled}),
            pending: MapSet.delete(sector.pending, hold_id),
            free: sector.free + length(hold.row_seats)
        }

        {:ok, sector}

      {:ok, %{status: :cancelled}} ->
        {:ok, sector}

      {:ok, %{status: :expired}} ->
        {:ok, sector}

      {:ok, %{status: :confirmed}} ->
        {:error, :already_confirmed}
    end
  end

  @doc "Free seats of the sector, after dropping whatever has expired."
  @spec availability(t, integer) :: {t, non_neg_integer}
  def availability(sector, now) do
    sector = sweep(sector, now)
    {sector, sector.free}
  end

  @doc "A consistent cut of this sector, and the money made in it so far."
  @spec snapshot(t, integer) :: {t, Gate.API.snapshot()}
  def snapshot(sector, now) do
    sector = sweep(sector, now)

    {free_ids, held_ids, sold_ids} =
      Enum.reduce(sector.rows, {[], [], []}, fn {row_no, row}, {free, held, sold} ->
        by_status = Row.by_status(row)

        to_ids = fn seats ->
          for seat <- seats, do: VenueSpec.seat_id(sector.name, row_no, seat)
        end

        {free ++ to_ids.(by_status.free), held ++ to_ids.(by_status.held),
         sold ++ to_ids.(by_status.sold)}
      end)

    snapshot = %{
      sold: sold_ids,
      held: held_ids,
      free: free_ids,
      revenue: length(sold_ids) * sector.price_cop
    }

    {sector, snapshot}
  end

  # Drop every pending hold whose ttl has passed, freeing its seats back to the rows.
  # Runs first inside every operation so expiry can never be observed as a stale read.
  defp sweep(sector, now) do
    Enum.reduce(sector.pending, sector, fn hold_id, sector ->
      hold = Map.fetch!(sector.holds, hold_id)

      if now - hold.held_at >= sector.ttl_ms do
        rows = update_rows(sector.rows, hold.row_seats, &Row.release/2)

        %{
          sector
          | rows: rows,
            holds: Map.put(sector.holds, hold_id, %{hold | status: :expired}),
            pending: MapSet.delete(sector.pending, hold_id),
            free: sector.free + length(hold.row_seats)
        }
      else
        sector
      end
    end)
  end

  defp alloc(sector, qty, :any) do
    {rows, collected, _remaining} =
      Enum.reduce(row_order(sector), {sector.rows, [], qty}, fn row_no, {rows, acc, remaining} ->
        if remaining <= 0 do
          {rows, acc, remaining}
        else
          row = Map.fetch!(rows, row_no)
          {row, seats} = Row.alloc_upto(row, remaining)
          acc = acc ++ for(seat <- seats, do: {row_no, seat})
          {Map.put(rows, row_no, row), acc, remaining - length(seats)}
        end
      end)

    if length(collected) == qty do
      {:ok, %{sector | rows: rows, free: sector.free - qty}, collected}
    else
      {:error, :sold_out}
    end
  end

  defp alloc(sector, qty, :contiguous) do
    row_order(sector)
    |> Enum.find_value(fn row_no ->
      row = Map.fetch!(sector.rows, row_no)

      case Row.alloc_contiguous(row, qty) do
        {:ok, row, seats} -> {row_no, row, seats}
        :none -> nil
      end
    end)
    |> case do
      {row_no, row, seats} ->
        row_seats = for seat <- seats, do: {row_no, seat}
        rows = Map.put(sector.rows, row_no, row)
        {:ok, %{sector | rows: rows, free: sector.free - qty}, row_seats}

      nil ->
        if sector.free >= qty do
          {:error, :no_contiguous_block}
        else
          {:error, :sold_out}
        end
    end
  end

  defp row_order(sector), do: sector.rows |> Map.keys() |> Enum.sort()

  defp update_rows(rows, row_seats, fun) do
    row_seats
    |> Enum.group_by(fn {row_no, _seat} -> row_no end, fn {_row_no, seat} -> seat end)
    |> Enum.reduce(rows, fn {row_no, seats}, acc ->
      Map.update!(acc, row_no, &fun.(&1, seats))
    end)
  end
end
