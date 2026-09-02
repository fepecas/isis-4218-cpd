defmodule WordCountTest do
  use ExUnit.Case

  test "empty string" do
    assert WordCount.count("") == %{}
  end

  test "only whitespace" do
    assert WordCount.count("   \t\n  ") == %{}
  end

  test "count one word" do
    assert WordCount.count("word") == %{"word" => 1}
  end

  test "count one of each word" do
    assert WordCount.count("one of each") == %{"one" => 1, "of" => 1, "each" => 1}
  end

  test "multiple occurrences of a word" do
    assert WordCount.count("one fish two fish red fish blue fish") == %{
             "one" => 1,
             "fish" => 4,
             "two" => 1,
             "red" => 1,
             "blue" => 1
           }
  end

  test "handles cramped lists" do
    assert WordCount.count("one,two,three") == %{"one" => 1, "two" => 1, "three" => 1}
  end

  test "handles expanded lists" do
    assert WordCount.count("one,\ntwo,\nthree") == %{"one" => 1, "two" => 1, "three" => 1}
  end

  test "ignores punctuation" do
    assert WordCount.count("car: carpet as java: javascript!!&@$%^&") == %{
             "car" => 1,
             "carpet" => 1,
             "as" => 1,
             "java" => 1,
             "javascript" => 1
           }
  end

  test "includes numbers" do
    assert WordCount.count("testing, 1, 2 testing") == %{"testing" => 2, "1" => 1, "2" => 1}
  end

  test "normalizes case" do
    assert WordCount.count("go Go GO Stop stop") == %{"go" => 3, "stop" => 2}
  end

  test "with apostrophes" do
    assert WordCount.count("First: don't laugh. Then: don't cry.") == %{
             "first" => 1,
             "don't" => 2,
             "laugh" => 1,
             "then" => 1,
             "cry" => 1
           }
  end

  test "with quotations around a word are stripped" do
    assert WordCount.count("Joe can't tell between app, 'apple' and a.") == %{
             "joe" => 1,
             "can't" => 1,
             "tell" => 1,
             "between" => 1,
             "app" => 1,
             "apple" => 1,
             "and" => 1,
             "a" => 1
           }
  end

  test "tabs and newlines act as separators" do
    assert WordCount.count("one\ttwo\nthree  four") == %{
             "one" => 1,
             "two" => 1,
             "three" => 1,
             "four" => 1
           }
  end

  test "single letter words" do
    assert WordCount.count("a b c a") == %{"a" => 2, "b" => 1, "c" => 1}
  end

  test "numbers only phrase" do
    assert WordCount.count("1 22 333 1") == %{"1" => 2, "22" => 1, "333" => 1}
  end
end
