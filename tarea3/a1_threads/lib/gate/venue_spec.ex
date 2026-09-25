defmodule Gate.VenueSpec do
  @moduledoc """
  The venue used for grading, plus the seat naming rules.

  This file is provided. Do not change it. The grader builds its spec from here,
  so if you change the numbers your seat ids stop matching the ones it expects.

  The layout follows the BTS 2026 concert at Estadio El Campin in Bogota, with a
  360 degree stage in the middle of the field. Sector names and the three price
  tiers come from the real sale. Row and seat counts are rounded to give the
  published total of about 36,000 seats.
  """

  @typedoc "Price tier of a sector. Only used for reporting."
  @type tier :: :cheap | :mid | :premium

  # {sector, rows, seats_per_row, price_cop, tier}
  @layout [
    # Premium, closest to the central stage.
    {:soundcheck_vip, 32, 40, 2_500_000, :premium},
    {:vip, 40, 60, 1_800_000, :premium},
    {:oriental_baja, 52, 80, 1_200_000, :premium},
    {:occidental_baja, 52, 80, 1_200_000, :premium},
    # Mid tier, upper rings.
    {:oriental_alta, 64, 64, 550_000, :mid},
    {:sur_alta, 72, 70, 450_000, :mid},
    {:norte_alta, 72, 70, 450_000, :mid},
    # Cheapest, behind and above the stage.
    {:oriental_norte_baja, 48, 55, 350_000, :cheap},
    {:sur_baja, 60, 60, 320_000, :cheap},
    {:norte_baja, 60, 60, 320_000, :cheap}
  ]

  @default_ttl_ms 5_000

  @doc """
  The grading venue.

  Options:

  * `:ttl_ms` is the hold lifetime, #{@default_ttl_ms} ms by default.
  * `:only` keeps just the given sectors, which is handy while you develop.
  """
  @spec el_campin(keyword) :: Gate.API.venue_spec()
  def el_campin(opts \\ []) do
    keep = Keyword.get(opts, :only, sectors())

    sectors =
      for {sector, rows, seats_per_row, price_cop, _tier} <- @layout,
          sector in keep,
          into: %{} do
        {sector, %{rows: rows, seats_per_row: seats_per_row, price_cop: price_cop}}
      end

    %{sectors: sectors, ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms)}
  end

  @doc "Sector names, from the most expensive to the cheapest."
  @spec sectors() :: [Gate.API.sector()]
  def sectors, do: for({sector, _, _, _, _} <- @layout, do: sector)

  @doc "Price tier of a sector."
  @spec tier(Gate.API.sector()) :: tier | nil
  def tier(sector) do
    case List.keyfind(@layout, sector, 0) do
      {^sector, _, _, _, tier} -> tier
      nil -> nil
    end
  end

  @doc """
  Total number of seats described by a spec.

      iex> Gate.VenueSpec.el_campin() |> Gate.VenueSpec.capacity()
      36016
  """
  @spec capacity(Gate.API.venue_spec()) :: non_neg_integer
  def capacity(%{sectors: sectors}) do
    Enum.reduce(sectors, 0, fn {_sector, s}, acc -> acc + s.rows * s.seats_per_row end)
  end

  @doc """
  Seat id of one seat. Rows and seats are numbered from 1.

      iex> Gate.VenueSpec.seat_id(:occidental_baja, 12, 34)
      "occidental_baja:R012:S034"
  """
  @spec seat_id(Gate.API.sector(), pos_integer, pos_integer) :: Gate.API.seat_id()
  def seat_id(sector, row, seat) do
    "#{sector}:R#{pad(row)}:S#{pad(seat)}"
  end

  @doc """
  Take a seat id apart again. Useful for checking your own work.

      iex> Gate.VenueSpec.parse_seat_id("vip:R007:S060")
      {:ok, :vip, 7, 60}
  """
  @spec parse_seat_id(Gate.API.seat_id()) ::
          {:ok, Gate.API.sector(), pos_integer, pos_integer} | :error
  def parse_seat_id(seat_id) when is_binary(seat_id) do
    with [sector, "R" <> row, "S" <> seat] <- String.split(seat_id, ":"),
         {row, ""} <- Integer.parse(row),
         {seat, ""} <- Integer.parse(seat) do
      {:ok, String.to_existing_atom(sector), row, seat}
    else
      _other -> :error
    end
  end

  @doc "Every seat id of a spec, in a stable order. Used by the grader."
  @spec all_seat_ids(Gate.API.venue_spec()) :: [Gate.API.seat_id()]
  def all_seat_ids(%{sectors: sectors}) do
    for sector <- sectors(),
        Map.has_key?(sectors, sector),
        row <- 1..sectors[sector].rows,
        seat <- 1..sectors[sector].seats_per_row do
      seat_id(sector, row, seat)
    end
  end

  defp pad(number), do: String.pad_leading(Integer.to_string(number), 3, "0")
end
