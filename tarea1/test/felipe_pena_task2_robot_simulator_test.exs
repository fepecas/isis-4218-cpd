defmodule RobotSimulatorTest do
  use ExUnit.Case

  test "create with a valid direction and position" do
    robot = RobotSimulator.create(:north, {0, 0})
    assert RobotSimulator.direction(robot) == :north
    assert RobotSimulator.position(robot) == {0, 0}
  end

  test "create with negative coordinates" do
    robot = RobotSimulator.create(:south, {-3, -8})
    assert RobotSimulator.position(robot) == {-3, -8}
  end

  test "create with an invalid direction raises" do
    direction = Function.identity(:north_east)
    assert_raise(FunctionClauseError, fn -> RobotSimulator.create(direction, {0, 0}) end)
  end

  test "create with an invalid position raises" do
    position = Function.identity({0, 0, 0})
    assert_raise(FunctionClauseError, fn -> RobotSimulator.create(:north, position) end)
  end

  test "create with non-integer coordinates raises" do
    position = Function.identity({0.0, 0})
    assert_raise(FunctionClauseError, fn -> RobotSimulator.create(:north, position) end)
  end

  test "empty instructions do not move the robot" do
    robot = RobotSimulator.create(:north, {0, 0}) |> RobotSimulator.simulate("")
    assert RobotSimulator.direction(robot) == :north
    assert RobotSimulator.position(robot) == {0, 0}
  end

  test "turning right cycles through all directions" do
    robot = RobotSimulator.create(:north, {0, 0})
    robot = RobotSimulator.simulate(robot, "R")
    assert RobotSimulator.direction(robot) == :east
    robot = RobotSimulator.simulate(robot, "R")
    assert RobotSimulator.direction(robot) == :south
    robot = RobotSimulator.simulate(robot, "R")
    assert RobotSimulator.direction(robot) == :west
    robot = RobotSimulator.simulate(robot, "R")
    assert RobotSimulator.direction(robot) == :north
  end

  test "turning left cycles through all directions" do
    robot = RobotSimulator.create(:north, {0, 0})
    robot = RobotSimulator.simulate(robot, "L")
    assert RobotSimulator.direction(robot) == :west
    robot = RobotSimulator.simulate(robot, "L")
    assert RobotSimulator.direction(robot) == :south
    robot = RobotSimulator.simulate(robot, "L")
    assert RobotSimulator.direction(robot) == :east
    robot = RobotSimulator.simulate(robot, "L")
    assert RobotSimulator.direction(robot) == :north
  end

  test "advancing in each direction" do
    assert RobotSimulator.create(:north, {0, 0})
           |> RobotSimulator.simulate("A")
           |> RobotSimulator.position() ==
             {0, 1}

    assert RobotSimulator.create(:south, {0, 0})
           |> RobotSimulator.simulate("A")
           |> RobotSimulator.position() ==
             {0, -1}

    assert RobotSimulator.create(:east, {0, 0})
           |> RobotSimulator.simulate("A")
           |> RobotSimulator.position() ==
             {1, 0}

    assert RobotSimulator.create(:west, {0, 0})
           |> RobotSimulator.simulate("A")
           |> RobotSimulator.position() ==
             {-1, 0}
  end

  test "the example from the PDF: RAALAL from {7, 3} facing north" do
    robot = RobotSimulator.create(:north, {7, 3})
    robot = RobotSimulator.simulate(robot, "RAALAL")
    assert RobotSimulator.position(robot) == {9, 4}
    assert RobotSimulator.direction(robot) == :west
  end

  test "an unknown instruction raises" do
    robot = RobotSimulator.create(:north, {0, 0})
    assert_raise(FunctionClauseError, fn -> RobotSimulator.simulate(robot, "Z") end)
  end

  test "a valid prefix followed by an invalid instruction raises" do
    robot = RobotSimulator.create(:north, {0, 0})
    assert_raise(FunctionClauseError, fn -> RobotSimulator.simulate(robot, "AAX") end)
  end
end
