defmodule RobotSimulator do
  @directions [:north, :east, :south, :west]

  def create(direction, {x, y} = position)
      when direction in @directions and is_integer(x) and is_integer(y) do
    {direction, position}
  end

  def simulate(robot, instructions) when is_binary(instructions) do
    instructions
    |> String.graphemes()
    |> Enum.reduce(robot, &step/2)
  end

  defp step("R", {direction, position}), do: {turn_right(direction), position}
  defp step("L", {direction, position}), do: {turn_left(direction), position}
  defp step("A", {direction, position}), do: {direction, advance(direction, position)}

  defp turn_right(:north), do: :east
  defp turn_right(:east), do: :south
  defp turn_right(:south), do: :west
  defp turn_right(:west), do: :north

  defp turn_left(:north), do: :west
  defp turn_left(:west), do: :south
  defp turn_left(:south), do: :east
  defp turn_left(:east), do: :north

  defp advance(:north, {x, y}), do: {x, y + 1}
  defp advance(:south, {x, y}), do: {x, y - 1}
  defp advance(:east, {x, y}), do: {x + 1, y}
  defp advance(:west, {x, y}), do: {x - 1, y}

  def direction({direction, _position}), do: direction

  def position({_direction, position}), do: position
end
