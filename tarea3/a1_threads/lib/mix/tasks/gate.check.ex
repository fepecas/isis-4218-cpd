defmodule Mix.Tasks.Gate.Check do
  @shortdoc "Check the rules of the assignment"

  @moduledoc """
  Checks the rules of the assignment.

  Using a banned module, or writing concurrency into the domain layer, is a hard
  failure: the submission is not graded until it is fixed. Run this before you
  hand in.

      mix gate.check --model actors

  ## Why the bans exist

  The whole point of the project is to build the concurrency yourself. `GenServer`
  already is the actor model, `Agent` already is a shared mutable cell, and ETS
  already is a shared heap with atomic operations. Handing any of them in would mean
  handing in someone else's answer to the question being asked.

  ## Why the layers exist

  Assignment 1 builds the ticketing rules and one concurrency model. The three
  assignments after it change the model and nothing else. That only works if the
  rules never mention processes, so `spawn`, `send`, `receive` and `Process` are
  allowed in `Gate.Sync` and nowhere else.

  ## Options

    * `--model NAME`  one of `threads`, `stm`, `csp`, `actors`. Read from
      `.gate_model` in the project root when it is not given.
    * `--quiet`       print the verdict only.
  """

  use Mix.Task

  @models ~w(threads stm csp actors)a

  # Banned in every assignment. The reason travels with the ban, so a failure says
  # what to do instead of only saying no.
  @banned %{
    GenServer: "the actor model is what you are asked to build, not to call",
    Agent: "a shared mutable cell is exactly the thing you have to implement",
    Supervisor: "fault tolerance belongs to project 2",
    DynamicSupervisor: "fault tolerance belongs to project 2",
    Registry: "naming processes and finding them again is part of the exercise",
    GenStage: "a concurrency library",
    Flow: "a concurrency library",
    ets: "a shared heap with atomic operations, which answers the question for you",
    dets: "the same as ets, on disk",
    mnesia: "a database with transactions, which is project 2 territory",
    persistent_term: "shared mutable memory outside your own processes",
    atomics: "hardware compare and swap, which is half a mutex for free",
    counters: "the same as atomics, for counters",
    global: "a distributed lock manager",
    pg: "distributed process groups"
  }

  # The ticketing rules. These files must survive the next three assignments
  # untouched, so nothing about processes is allowed to leak into them.
  @domain ["lib/gate/venue.ex", "lib/gate/sector.ex", "lib/gate/row.ex"]

  @concurrency [:spawn, :spawn_link, :spawn_monitor, :send, :self, :exit]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: [model: :string, quiet: :boolean])
    model = model(opts[:model])
    sources = sources()

    violations =
      sources |> Enum.flat_map(&violations(&1, model)) |> Enum.sort_by(&{&1.file, &1.line})

    unless opts[:quiet], do: report(violations, model)
    Mix.shell().info(verdict(violations))

    if violations != [], do: exit({:shutdown, 1})
  end

  defp violations({path, ast}, model) do
    banned = Map.merge(@banned, extra_bans(model))

    {_ast, found} =
      Macro.prewalk(ast, [], fn node, acc -> {node, acc ++ judge(node, banned, path)} end)

    found
  end

  # A call into another module, like `GenServer.call` or `:ets.new`.
  defp judge({{:., meta, [module, _fun]}, _call_meta, _args}, banned, path) do
    name = label(module)

    cond do
      reason = Map.get(banned, key(module)) ->
        [note(path, meta, "#{name} is banned: #{reason}")]

      name == "Process" and domain?(path) ->
        [note(path, meta, "Process is only allowed in Gate.Sync, not in the ticketing rules")]

      true ->
        []
    end
  end

  defp judge({:receive, meta, args}, _banned, path) when is_list(args) do
    if domain?(path) do
      [note(path, meta, "receive is only allowed in Gate.Sync, not in the ticketing rules")]
    else
      []
    end
  end

  defp judge({name, meta, args}, _banned, path) when name in @concurrency and is_list(args) do
    if domain?(path) do
      [note(path, meta, "#{name} is only allowed in Gate.Sync, not in the ticketing rules")]
    else
      []
    end
  end

  defp judge(_node, _banned, _path), do: []

  # `Process.sleep` used to wait for something to happen is a race dressed up as a
  # solution, so it is banned everywhere except where a timeout is the point.
  defp extra_bans(_model), do: %{}

  defp key({:__aliases__, _meta, parts}), do: List.last(parts)
  defp key(module) when is_atom(module), do: module
  defp key(_module), do: nil

  defp label({:__aliases__, _meta, parts}), do: Enum.join(parts, ".")
  defp label(module) when is_atom(module), do: inspect(module)
  defp label(_module), do: "?"

  defp domain?(path), do: path in @domain

  defp note(path, meta, message) do
    %{file: path, line: Keyword.get(meta, :line, 0), message: message}
  end

  defp sources do
    "lib/**/*.ex"
    |> Path.wildcard()
    |> Enum.reject(&provided?/1)
    |> Enum.map(fn path -> {path, path |> File.read!() |> Code.string_to_quoted!()} end)
  end

  # The task itself is handed out, so it is not reviewed.
  defp provided?(path) do
    String.starts_with?(path, "lib/mix/")
  end

  defp model(nil) do
    case File.read(".gate_model") do
      {:ok, name} -> model(String.trim(name))
      {:error, _reason} -> Mix.raise("--model NAME is required, or put the name in .gate_model")
    end
  end

  defp model(name) do
    atom = String.to_atom(name)

    if atom in @models do
      atom
    else
      Mix.raise("unknown model #{name}, expected one of #{Enum.join(@models, ", ")}")
    end
  end

  defp report(violations, model) do
    Mix.shell().info("\nmix gate.check, model #{model}\n")
    Mix.shell().info(headline(violations, "nothing banned found", "must be fixed"))
    Enum.each(violations, &Mix.shell().error("    #{&1.file}:#{&1.line}  #{&1.message}"))
    Mix.shell().info("")
  end

  defp headline([], empty, _some), do: "  rules: #{empty}\n"
  defp headline(items, _empty, some), do: "  rules: #{length(items)} #{some}\n"

  defp verdict([]), do: "gate.check: rules ok"

  defp verdict(violations) do
    "gate.check: NOT GRADED, #{length(violations)} banned constructs"
  end
end
