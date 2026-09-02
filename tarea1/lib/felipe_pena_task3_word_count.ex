defmodule WordCount do
  @word_pattern ~r/[a-z]+'[a-z]+|[a-z]+|\d+/

  def count(sentence) do
    sentence
    |> String.downcase()
    |> extract_words()
    |> Enum.reduce(%{}, fn word, acc -> Map.update(acc, word, 1, &(&1 + 1)) end)
  end

  defp extract_words(sentence) do
    @word_pattern
    |> Regex.scan(sentence)
    |> List.flatten()
  end
end
