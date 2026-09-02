defmodule BinarySearchTest do
  use ExUnit.Case

  test "finds a value in an empty tuple" do
    assert BinarySearch.search({}, 6) == :not_found
  end

  test "finds a value in a single element tuple" do
    assert BinarySearch.search({6}, 6) == {:ok, 0}
  end

  test "value not found in single element tuple" do
    assert BinarySearch.search({6}, 1) == :not_found
  end

  test "finds a value in the middle of a tuple" do
    assert BinarySearch.search({1, 3, 5}, 3) == {:ok, 1}
  end

  test "finds a value at the beginning of a tuple" do
    assert BinarySearch.search({1, 3, 5}, 1) == {:ok, 0}
  end

  test "finds a value at the end of a tuple" do
    assert BinarySearch.search({1, 3, 5}, 5) == {:ok, 2}
  end

  test "finds a value in a larger tuple" do
    assert BinarySearch.search({1, 3, 5, 7, 9, 11, 13, 15, 17}, 13) == {:ok, 6}
  end

  test "finds first and last index of large tuple" do
    numbers = List.to_tuple(Enum.to_list(1..100))
    assert BinarySearch.search(numbers, 1) == {:ok, 0}
    assert BinarySearch.search(numbers, 100) == {:ok, 99}
  end

  test "identifies that a value is not included in the tuple" do
    assert BinarySearch.search({1, 3, 5}, 2) == :not_found
  end

  test "a value smaller than the tuple's smallest value is not found" do
    assert BinarySearch.search({1, 3, 5, 7}, 0) == :not_found
  end

  test "a value larger than the tuple's largest value is not found" do
    assert BinarySearch.search({1, 3, 5, 7}, 8) == :not_found
  end

  test "even number of elements" do
    assert BinarySearch.search({1, 3, 5, 7}, 5) == {:ok, 2}
  end
end
