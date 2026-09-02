defmodule TopSecretTest do
  use ExUnit.Case

  test "to_ast/1 turns code into an AST" do
    assert TopSecret.to_ast("div(4, 3)") == {:div, [line: 1], [4, 3]}
  end

  test "to_ast/1 with a literal" do
    assert TopSecret.to_ast("42") == 42
  end

  test "decode_secret_message_part/2 on a public function" do
    ast_node = TopSecret.to_ast("defp cat(a, b, c), do: nil")
    assert TopSecret.decode_secret_message_part(ast_node, ["day"]) == {ast_node, ["cat", "day"]}
  end

  test "decode_secret_message_part/2 on a non-function node returns accumulator unchanged" do
    ast_node = TopSecret.to_ast("10 + 3")
    assert TopSecret.decode_secret_message_part(ast_node, ["day"]) == {ast_node, ["day"]}
  end

  test "decode_secret_message_part/2 truncates the name to the arity" do
    ast_node = TopSecret.to_ast("defp cat(a, b), do: nil")
    assert TopSecret.decode_secret_message_part(ast_node, ["day"]) == {ast_node, ["ca", "day"]}
  end

  test "decode_secret_message_part/2 with arity zero returns an empty string" do
    ast_node = TopSecret.to_ast("defp cat(), do: nil")
    assert TopSecret.decode_secret_message_part(ast_node, ["day"]) == {ast_node, ["", "day"]}
  end

  test "decode_secret_message_part/2 with a bare arity zero function (no parens)" do
    ast_node = TopSecret.to_ast("defp cat, do: nil")
    assert TopSecret.decode_secret_message_part(ast_node, ["day"]) == {ast_node, ["", "day"]}
  end

  test "decode_secret_message_part/2 with a guard" do
    ast_node = TopSecret.to_ast("defp cat(a, b) when is_nil(a), do: nil")
    assert TopSecret.decode_secret_message_part(ast_node, ["day"]) == {ast_node, ["ca", "day"]}
  end

  test "decode_secret_message_part/2 with a public function and a guard" do
    ast_node = TopSecret.to_ast("def cat(a, b, c) when is_nil(a), do: nil")
    assert TopSecret.decode_secret_message_part(ast_node, []) == {ast_node, ["cat"]}
  end

  test "decode_secret_message_part/2 with an empty accumulator" do
    ast_node = TopSecret.to_ast("defp cat(a), do: nil")
    assert TopSecret.decode_secret_message_part(ast_node, []) == {ast_node, ["c"]}
  end

  test "decode_secret_message_part/2 on a module definition node" do
    ast_node = TopSecret.to_ast("defmodule Foo do\nend")
    assert TopSecret.decode_secret_message_part(ast_node, ["day"]) == {ast_node, ["day"]}
  end

  test "decode_secret_message/1 decodes the PDF example" do
    code = """
    defmodule MyCalendar do
      def busy?(date, time) do
        Date.day_of_week(date) != 7 and
          time.hour in 10..16
      end

      def yesterday?(date) do
        Date.diff(Date.utc_today, date)
      end
    end
    """

    assert TopSecret.decode_secret_message(code) == "buy"
  end

  test "decode_secret_message/1 with no function definitions" do
    assert TopSecret.decode_secret_message("1 + 1") == ""
  end

  test "decode_secret_message/1 with a single arity-0 function" do
    assert TopSecret.decode_secret_message("defp foo(), do: nil") == ""
  end

  test "decode_secret_message/1 with multiple functions including guards" do
    code = """
    defmodule Multi do
      defp aardvark(a, b) when is_integer(a), do: a + b
      def zebra(x), do: x
    end
    """

    assert TopSecret.decode_secret_message(code) == "aaz"
  end
end
