defmodule Gate.API do
  @moduledoc """
  The graded contract for every assignment of Project 1.

  This file is provided. Do not change it. The grader talks only to the
  callbacks below, and it calls them on `Gate.Venue`, so `Gate.Venue` must declare
  `@behaviour Gate.API` and implement all of them.

  The same contract is used by the four assignments (threads, STM, CSP, actors).
  Only the concurrency layer under `Gate.Sync` is expected to change between them.

  ## Vocabulary

  A venue has sectors. A sector has rows. A row has seats. A seat is free, held or
  sold, and never two of those at once.

  A client reserves seats, which creates a hold. A hold lives for `ttl_ms`
  milliseconds. Confirming a live hold turns its seats into tickets, which is the
  sale. Confirming an expired hold fails and the seats go back to free.
  """

  @typedoc """
  Seat identifier. Stable, and derived only from the venue spec, so the same seat
  has the same id in every run and in every implementation.

  Format: `"<sector>:R<row>:S<seat>"` with the row and the seat zero padded to
  three digits, both starting at 1. Example: `"occidental_baja:R012:S034"`.
  """
  @type seat_id :: String.t()

  @typedoc "Sector name, as given in the venue spec."
  @type sector :: atom()

  @typedoc """
  Hold identifier, opaque to the caller. Never reused inside one venue, not even
  after the hold expires, is cancelled or is confirmed.
  """
  @type hold_id :: term()

  @typedoc """
  Opaque handle for a running venue, whatever your implementation needs it to be.
  The grader only stores it and passes it back to you.
  """
  @type venue :: term()

  @typedoc """
  Venue configuration. `Gate.VenueSpec.el_campin/1` builds the one used for
  grading, but your code must work for any spec of this shape.

  * `:sectors` maps a sector name to its shape and price.
  * `:ttl_ms` is the lifetime of a hold in milliseconds.
  """
  @type venue_spec :: %{
          sectors: %{
            sector => %{rows: pos_integer, seats_per_row: pos_integer, price_cop: pos_integer}
          },
          ttl_ms: pos_integer
        }

  @typedoc "A sold seat."
  @type ticket :: %{
          seat_id: seat_id,
          sector: sector,
          price_cop: pos_integer,
          hold_id: hold_id
        }

  @typedoc """
  A consistent cut of the whole venue, meaning the three seat sets must describe
  one single instant of the venue's history.

  `:sold`, `:held` and `:free` are pairwise disjoint and their union is every seat
  of the venue. `:revenue` is the sum of the prices of the seats in `:sold`.
  """
  @type snapshot :: %{
          sold: [seat_id],
          held: [seat_id],
          free: [seat_id],
          revenue: non_neg_integer
        }

  @doc """
  Start a venue from a spec. Every seat starts free.

  Returns the handle that all the other callbacks take.
  """
  @callback start_venue(venue_spec) :: {:ok, venue} | {:error, term}

  @doc """
  Stop a venue and release everything it owns. Calling it twice is allowed and
  still returns `:ok`.
  """
  @callback stop_venue(venue) :: :ok

  @doc """
  Try to hold `qty` seats in `sector`.

  `qty` is between 1 and 6. With `:any` the seats may come from any rows of the
  sector. With `:contiguous` they must be consecutive seat numbers inside one row
  of the sector.

  This call never blocks and never queues. If it cannot be served right now it
  fails, and the caller is free to try again.

  * `:sold_out` means the sector does not have `qty` free seats.
  * `:no_contiguous_block` means the sector has enough free seats but no run of
    `qty` consecutive free seats in a single row.
  * `:bad_sector` means the sector is not in the venue spec.
  """
  @callback reserve(venue, sector, qty :: 1..6, mode :: :any | :contiguous) ::
              {:ok, hold_id, [seat_id]}
              | {:error, :sold_out | :no_contiguous_block | :bad_sector}

  @doc """
  Buy the seats of a live hold. All of them or none of them.

  On success the seats become sold, permanently. This call is not idempotent, so
  the second call on the same hold returns `{:error, :already_confirmed}`.

  * `:expired` means `ttl_ms` had already passed. The seats are free again.
  * `:unknown_hold` means the id was never issued by this venue, or it belonged to
    a hold that was cancelled or that expired long enough ago to be forgotten.
  """
  @callback confirm(venue, hold_id) ::
              {:ok, [ticket]}
              | {:error, :expired | :unknown_hold | :already_confirmed}

  @doc """
  Give up a hold early and free its seats.

  This call is idempotent, and cancelling a hold that has already expired is
  still `:ok`, because the outcome the caller asked for is the outcome it gets.
  Cancelling a confirmed hold returns `{:error, :already_confirmed}`, since a
  sale cannot be undone.
  """
  @callback cancel(venue, hold_id) :: :ok | {:error, :unknown_hold | :already_confirmed}

  @doc """
  How many seats of `sector` are free right now. Held and sold seats do not count.

  This is a hint for a client, not a promise. A reserve right after it may still
  fail, because other clients are running at the same time.
  """
  @callback availability(venue, sector) :: non_neg_integer | {:error, :bad_sector}

  @doc """
  A consistent cut of the venue. See `t:snapshot/0`.

  The grader calls this while load is running, so it has to be cheap enough not
  to stall the sale, and it must never show a seat as free and sold at the same
  time.
  """
  @callback snapshot(venue) :: snapshot
end
