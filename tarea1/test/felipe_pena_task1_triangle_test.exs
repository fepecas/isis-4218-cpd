defmodule TriangleTest do
  use ExUnit.Case

  test "equilateral triangle" do
    assert Triangle.kind(2, 2, 2) == {:ok, :equilateral}
  end

  test "smallest possible equilateral triangle" do
    assert Triangle.kind(1, 1, 1) == {:ok, :equilateral}
  end

  test "isosceles triangle, first two sides equal" do
    assert Triangle.kind(3, 4, 4) == {:ok, :isosceles}
  end

  test "isosceles triangle, last two sides equal" do
    assert Triangle.kind(4, 3, 4) == {:ok, :isosceles}
  end

  test "isosceles triangle, first and last sides equal" do
    assert Triangle.kind(4, 4, 3) == {:ok, :isosceles}
  end

  test "isosceles triangle, exactly the smallest possible" do
    assert Triangle.kind(1, 1, 2) == {:ok, :isosceles}
    assert Triangle.kind(2, 1, 1) == {:ok, :isosceles}
  end

  test "scalene triangle" do
    assert Triangle.kind(3, 4, 5) == {:ok, :scalene}
  end

  test "scalene triangle, different order" do
    assert Triangle.kind(5, 3, 4) == {:ok, :scalene}
  end

  test "very small scalene triangle" do
    assert Triangle.kind(0.4, 0.6, 0.3) == {:ok, :scalene}
  end

  test "zero length sides are illegal" do
    assert {:error, _} = Triangle.kind(0, 0, 0)
  end

  test "one side is zero" do
    assert {:error, _} = Triangle.kind(0, 3, 4)
  end

  test "negative sides are illegal" do
    assert {:error, _} = Triangle.kind(-3, 4, 5)
  end

  test "sum of two sides less than the largest side is illegal" do
    assert {:error, _} = Triangle.kind(1, 1, 3)
  end

  test "sum of two sides less than the largest side, order matters" do
    assert {:error, _} = Triangle.kind(1, 3, 1)
    assert {:error, _} = Triangle.kind(3, 1, 1)
  end

  test "error is a {:error, String.t()} tuple" do
    {:error, message} = Triangle.kind(0, 0, 0)
    assert is_binary(message)
  end
end
