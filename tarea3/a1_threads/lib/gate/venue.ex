defmodule Gate.Venue do
  @moduledoc """
  The module the grader calls. Write it once, in assignment 1, and then leave
  it alone.

  This is the glue and nothing else. Each callback turns a request into a pure state
  transition of `Gate.Sector` and hands that transition to `Gate.Sync.update/3`, which
  is the only code in the project that knows how the state is shared.

  Keeping this file free of processes is what makes the next three assignments a change
  of model instead of a rewrite. `mix gate.check` enforces it: `spawn`, `send`,
  `receive` and `Process` here are a hard failure.
  """

  @behaviour Gate.API

  alias Gate.Sector
  alias Gate.Sync

  @impl Gate.API
  def start_venue(spec) do
    Sync.start(spec)
  end

  @impl Gate.API
  def stop_venue(venue) do
    Sync.stop(venue)
  end

  # A failed operation still hands back the sector with the expiries it decided, so an
  # answer like `:expired` is committed together with the state it was based on.
  @impl Gate.API
  def reserve(venue, sector, qty, mode) do
    Sync.update(venue, sector, fn state, now ->
      case Sector.reserve(state, qty, mode, now) do
        {:ok, state, hold_id, seat_ids} -> {{:ok, hold_id, seat_ids}, state}
        {:error, reason} -> {{:error, reason}, Sector.sweep(state, now)}
      end
    end)
  end

  @impl Gate.API
  def confirm(venue, hold_id) do
    with {:ok, sector} <- route(hold_id) do
      case Sync.update(venue, sector, fn state, now ->
             case Sector.confirm(state, hold_id, now) do
               {:ok, state, tickets} -> {{:ok, tickets}, state}
               {:error, reason} -> {{:error, reason}, Sector.sweep(state, now)}
             end
           end) do
        {:error, :bad_sector} -> {:error, :unknown_hold}
        other -> other
      end
    else
      :error -> {:error, :unknown_hold}
    end
  end

  @impl Gate.API
  def cancel(venue, hold_id) do
    with {:ok, sector} <- route(hold_id) do
      case Sync.update(venue, sector, fn state, now ->
             case Sector.cancel(state, hold_id, now) do
               {:ok, state} -> {:ok, state}
               {:error, reason} -> {{:error, reason}, Sector.sweep(state, now)}
             end
           end) do
        {:error, :bad_sector} -> {:error, :unknown_hold}
        other -> other
      end
    else
      :error -> {:error, :unknown_hold}
    end
  end

  @impl Gate.API
  def availability(venue, sector) do
    Sync.update(venue, sector, fn state, now ->
      {state, count} = Sector.availability(state, now)
      {count, state}
    end)
  end

  @impl Gate.API
  def snapshot(venue) do
    Sync.sectors(venue)
    |> Enum.reduce(%{sold: [], held: [], free: [], revenue: 0}, fn sector, acc ->
      cut =
        Sync.update(venue, sector, fn state, now ->
          {state, snapshot} = Sector.snapshot(state, now)
          {snapshot, state}
        end)

      %{
        sold: acc.sold ++ cut.sold,
        held: acc.held ++ cut.held,
        free: acc.free ++ cut.free,
        revenue: acc.revenue + cut.revenue
      }
    end)
  end

  # `hold_id` is opaque to whoever calls confirm/2 and cancel/2, but we control its shape
  # internally: it carries the sector it belongs to, so we know which process to ask
  # without a sector argument in the callback. Anything that does not have this exact
  # shape is not an id we ever issued, so it fails safely instead of crashing.
  defp route(hold_id) do
    case hold_id do
      {sector, ref} when is_atom(sector) and is_integer(ref) -> {:ok, sector}
      _other -> :error
    end
  end
end
