defmodule TopSecret do
  def to_ast(string) do
    Code.string_to_quoted!(string)
  end

  def decode_secret_message_part({op, _meta, [signature, _body]} = ast, acc)
      when op in [:def, :defp] do
    {name, arity} = name_and_arity(signature)
    {ast, [String.slice(Atom.to_string(name), 0, arity) | acc]}
  end

  def decode_secret_message_part(ast, acc) do
    {ast, acc}
  end

  # `when` wraps the head as {:when, _, [head, guard]}; unwrap it to reach {name, _, args}.
  # args is `nil` for a 0-arity head written without parens, so List.wrap makes it [] before counting.
  defp name_and_arity({:when, _meta, [{name, _, args}, _guard]}),
    do: {name, length(List.wrap(args))}

  defp name_and_arity({name, _meta, args}), do: {name, length(List.wrap(args))}

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
