defmodule Gate.Row do
  @moduledoc """
  One row of seats. Pure data, no processes.

  Contiguous seating is a question about one row, so a row is a useful thing to have a
  name for, and a sector then becomes a collection of rows. Nothing in the grader looks
  at this module, so if you would rather represent a sector some other way, do that
  instead and change this file.

  A seat is `:free`, `:held` or `:sold`, and never two of those at once.

  """

  @enforce_keys [:size, :status, :free]
  defstruct [:size, :status, :free]

  @type seat_no :: pos_integer
  @type status :: :free | :held | :sold
  @type t :: %__MODULE__{
          size: pos_integer,
          status: %{seat_no => status},
          free: non_neg_integer
        }

  @doc "A row of `size` free seats."
  @spec new(pos_integer) :: t
  def new(size) do
    status = for seat <- 1..size, into: %{}, do: {seat, :free}
    %__MODULE__{size: size, status: status, free: size}
  end

  @doc "How many seats of the row are free."
  @spec free_count(t) :: non_neg_integer
  def free_count(row), do: row.free

  @doc """
  Hold up to `qty` free seats and say which ones.

  Up to, so the caller gets between 0 and `qty`. That is what lets a reserve in `:any`
  mode walk several rows and collect what it needs.
  """
  @spec alloc_upto(t, pos_integer) :: {t, [seat_no]}
  def alloc_upto(row, qty) do
    seats =
      row.status
      |> Enum.filter(fn {_seat, status} -> status == :free end)
      |> Enum.map(fn {seat, _status} -> seat end)
      |> Enum.sort()
      |> Enum.take(qty)

    new_status = mark(row.status, seats, :held)
    {%{row | status: new_status, free: row.free - length(seats)}, seats}
  end

  @doc "Hold `qty` seats with consecutive numbers, or nothing at all."
  @spec alloc_contiguous(t, pos_integer) :: {:ok, t, [seat_no]} | :none
  def alloc_contiguous(row, qty) do
    case find_contiguous(row.status, row.size, qty) do
      nil ->
        :none

      seats ->
        new_status = mark(row.status, seats, :held)
        {:ok, %{row | status: new_status, free: row.free - qty}, seats}
    end
  end

  @doc "Put held seats back to free."
  @spec release(t, [seat_no]) :: t
  def release(row, seats) do
    %{row | status: mark(row.status, seats, :free), free: row.free + length(seats)}
  end

  @doc "Turn held seats into sold seats."
  @spec sell(t, [seat_no]) :: t
  def sell(row, seats) do
    %{row | status: mark(row.status, seats, :sold)}
  end

  @doc "Seat numbers of the row grouped by status."
  @spec by_status(t) :: %{free: [seat_no], held: [seat_no], sold: [seat_no]}
  def by_status(row) do
    Enum.reduce(row.status, %{free: [], held: [], sold: []}, fn {seat, status}, acc ->
      Map.update!(acc, status, &[seat | &1])
    end)
  end

  defp mark(status, seats, new_value) do
    Enum.reduce(seats, status, fn seat, acc -> Map.put(acc, seat, new_value) end)
  end

  defp find_contiguous(_status, size, qty) when qty > size, do: nil

  defp find_contiguous(status, size, qty) do
    Enum.find_value(1..(size - qty + 1), fn start ->
      seats = Enum.to_list(start..(start + qty - 1))

      if Enum.all?(seats, fn seat -> Map.fetch!(status, seat) == :free end) do
        seats
      end
    end)
  end
end
