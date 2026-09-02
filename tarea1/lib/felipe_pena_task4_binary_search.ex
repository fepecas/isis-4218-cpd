defmodule BinarySearch do
  def search(numbers, key) do
    search(numbers, key, 0, tuple_size(numbers) - 1)
  end

  defp search(_numbers, _key, low, high) when low > high do
    :not_found
  end

  defp search(numbers, key, low, high) do
    mid = div(low + high, 2)
    midpoint_value = elem(numbers, mid)

    cond do
      midpoint_value == key -> {:ok, mid}
      midpoint_value > key -> search(numbers, key, low, mid - 1)
      midpoint_value < key -> search(numbers, key, mid + 1, high)
    end
  end
end
