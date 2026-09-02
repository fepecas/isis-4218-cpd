defmodule TopSecret do
  @doc """
  Turn a string of Elixir code into its AST representation.
  """
  @spec to_ast(String.t()) :: Macro.t()
  def to_ast(string) do
    Code.string_to_quoted!(string)
  end

  @doc """
  Parse a single AST node, prepending the decoded fragment of a function
  definition (`def`/`defp`) to the accumulator. Any other node leaves the
  accumulator unchanged. The AST node itself is always returned unchanged.
  """
  @spec decode_secret_message_part(Macro.t(), list(String.t())) ::
          {Macro.t(), list(String.t())}
  def decode_secret_message_part({op, _meta, [signature, _body]} = ast, acc)
      when op in [:def, :defp] do
    {name, arity} = name_and_arity(signature)
    {ast, [String.slice(Atom.to_string(name), 0, arity) | acc]}
  end

  def decode_secret_message_part(ast, acc) do
    {ast, acc}
  end

  defp name_and_arity({:when, _meta, [{name, _, args}, _guard]}),
    do: {name, length(List.wrap(args))}

  defp name_and_arity({name, _meta, args}), do: {name, length(List.wrap(args))}

  @doc """
  Decode the full secret message hidden across all function definitions in
  the given Elixir source code.
  """
  @spec decode_secret_message(String.t()) :: String.t()
  def decode_secret_message(code) do
    {_ast, parts} =
      code
      |> to_ast()
      |> Macro.prewalk([], &decode_secret_message_part/2)

    parts
    |> Enum.reverse()
    |> Enum.join()
  end
end
