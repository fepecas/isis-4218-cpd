# Hack the Gate

Project 1 of the course, concurrency. You are building the part of a ticket selling
service that decides who gets which seat, for a sale where far more people turn up than
there are seats.

The venue is Estadio El Campin in Bogota, laid out for the BTS 2026 concert with a stage
in the middle of the field: ten sectors, three price tiers, 36,016 seats. It is in
`lib/gate/venue_spec.ex`, which is handed to you and must not be edited.

Read `project1_spec.pdf` for the rules. Read the addendum for your assignment for what
your concurrency layer has to be. This file is only about getting started.

## What you hand in

This project, with the files below filled in.

| File | Who writes it | Changes between assignments |
| --- | --- | --- |
| `lib/gate/api.ex` | handed to you | never, and editing it means no grade |
| `lib/gate/venue_spec.ex` | handed to you | never, and editing it means no grade |
| `lib/mix/tasks/gate.check.ex` | handed to you | never |
| `lib/gate/venue.ex` | you, in assignment 1 | no |
| `lib/gate/sector.ex` | you, in assignment 1 | no |
| `lib/gate/row.ex` | you, in assignment 1 | no, and you may delete it |
| `lib/gate/sync.ex` | you, every assignment | **yes, this is the assignment** |
| `.gate_model` | you | yes, one word: the model |

The grader calls `Gate.Venue` and nothing else. Add as many files under `lib/gate/sync/`
as you like.

## Before you hand in

```sh
mix compile --warnings-as-errors
mix gate.check
```

`mix gate.check` checks the rules of the assignment: a banned module, or concurrency in
the ticketing rules, means the submission is not graded until it is fixed.

There are no public tests. The specification is the contract, it is complete, and it says
what every call returns in every case listed. If you find something the specification does
not answer, ask, and the answer goes to the whole class.
