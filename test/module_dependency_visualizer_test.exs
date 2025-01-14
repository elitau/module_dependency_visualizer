defmodule ModuleDependencyVisualizerTest do
  use ExUnit.Case
  alias ModuleDependencyVisualizer, as: MDV

  describe "analyze/1 when is_binary" do
    test "analyzing a file without aliases produces the right dependencies" do
      file = """
      defmodule Tester.One do
        def first(input) do
          String.length(input)
          List.first(input)
        end

        def second(input) do
          :lists.sort(input)
        end

        def third(input) do
          Tester.Other.first(input)
        end

        def fourth(input) do
          My.Long.Module.Chain.first(input)
        end
      end
      """

      result = file |> MDV.analyze() |> Enum.sort()

      assert result ==
               Enum.sort([
                 {"Tester.One", "String"},
                 {"Tester.One", "List"},
                 {"Tester.One", "lists"},
                 {"Tester.One", "Tester.Other"},
                 {"Tester.One", "My.Long.Module.Chain"}
               ])
    end

    @tag :skip
    test "analyzing a file with a module attribute produces the right dependencies" do
      file = """
      defmodule Tester.One do
        @other Tester.Other

        def third(input) do
          @other.YetAnother.first(input)
        end
      end
      """

      result = file |> MDV.analyze() |> Enum.sort()

      assert result ==
               Enum.sort([
                 {"Tester.One", "Tester.Other.YetAnother"}
               ])
    end

    test "analyzing a file with aliases produces the right dependencies" do
      file = """
      defmodule Tester.One do
        alias Tester.MyOther, as: Other
        alias My.Long.Module.Chain

        def first(input) do
          String.length(input)
          List.first(input)
        end

        def second(input) do
          :lists.sort(input)
        end

        def third(input) do
          Other.first(input)
        end

        def fourth(input) do
          Chain.first(input)
        end
      end

      defmodule Tester.Two do
        alias Tester.Four
        alias Tester.Multi.{One, Three}

        def first(input) do
          input
            |> One.first
            |> Three.first
            |> Four.first
        end
      end
      """

      result = file |> MDV.analyze() |> Enum.sort()

      assert result ==
               Enum.sort([
                 {"Tester.One", "String"},
                 {"Tester.One", "List"},
                 {"Tester.One", "lists"},
                 {"Tester.One", "Tester.MyOther"},
                 {"Tester.One", "My.Long.Module.Chain"},
                 {"Tester.Two", "Tester.Multi.One"},
                 {"Tester.Two", "Tester.Multi.Three"},
                 {"Tester.Two", "Tester.Four"}
               ])
    end

    test "analyzing a file with use/import/require produces the right dependencies" do
      file = """
      defmodule Tester.One do
        alias Tester.MyOther, as: Other
        alias My.Long

        def first(input) do
          String.length(input)
          List.first(input)
        end

        def second(input) do
          :lists.sort(input)
        end

        def third(input) do
          Other.first(input)
        end

        def fourth(input) do
          Long.Module.Chain.first(input)
        end
      end

      defmodule Tester.Two do
        alias Tester.{One, Three}
        import Tester.Five
        use Tester.Macro
        require Tester.Logger, as: Logger

        def first(input) do
          input |> One.third |> Tester.Logger.log
          Three.first(input)
        end
      end
      """

      result = file |> MDV.analyze() |> Enum.sort()

      assert result ==
               Enum.sort([
                 {"Tester.One", "String"},
                 {"Tester.One", "List"},
                 {"Tester.One", "lists"},
                 {"Tester.One", "Tester.MyOther"},
                 {"Tester.One", "My.Long.Module.Chain"},
                 {"Tester.Two", "Tester.One"},
                 {"Tester.Two", "Tester.Three"},
                 {"Tester.Two", "Tester.Five"},
                 {"Tester.Two", "Tester.Macro"},
                 {"Tester.Two", "Tester.Logger"}
               ])
    end
  end

  describe "filter/2" do
    test "removes all modules not matching the given list of include: names only by looking at from node" do
      file = """
      defmodule Include.Me do
        def third(input) do
          AnotherModule.first(input)
        end
      end

      defmodule Remove.Me do
        def third(input) do
          AnotherModule.first(input)
        end
      end
      """

      result = file |> MDV.analyze() |> MDV.filter(include: ["Include.Me"])

      assert result == [{"Include.Me", "AnotherModule"}]
    end

    test "excludes all modules matching the given list of exclude: names only by looking at to node" do
      file = """
      defmodule Top.Module do
        def third(input) do
          UsedModule.first(input)
          PartOf.call(input)
          PartOf.WithMore.call(input)
          AnotherModule.first(input)
        end
      end
      """

      result =
        file |> MDV.analyze() |> MDV.filter(exclude: ["UsedModule", ~r/PartOf\Z/]) |> Enum.sort()

      assert result ==
               Enum.sort([{"Top.Module", "PartOf.WithMore"}, {"Top.Module", "AnotherModule"}])
    end

    test "remove unconnected nodes aka. there can be only one graph" do
      file = """
      defmodule One do
        def call(input) do
          Two.first(input)
        end
      end

      defmodule Three do
        def call(input) do
          Two.first(input)
        end
      end

      defmodule Four do
        def call(input) do
          Five.first(input)
        end
      end
      """

      result =
        file
        |> MDV.analyze()
        |> MDV.filter(remove_all_graphs_not_connected_to: "One")
        |> Enum.sort()

      assert result == Enum.sort([{"One", "Two"}, {"Three", "Two"}])
    end

    test "no filters" do
      file = """
      defmodule First.Me do
        def third(input) do
          AnotherModule.first(input)
        end
      end

      defmodule Second.Me do
        def third(input) do
          AnotherModule.first(input)
        end
      end
      """

      result = file |> MDV.analyze() |> MDV.filter() |> Enum.sort()

      assert result == Enum.sort([{"First.Me", "AnotherModule"}, {"Second.Me", "AnotherModule"}])
    end
  end

  describe "reverse edge direction" do
    test "for matching from and to nodes" do
      file = ~s|
      defmodule First.Me do
        def third(input) do
          AnotherModule.first(input)
        end
      end

      defmodule Second.Me do
        def third(input) do
          AnotherModule.first(input)
        end
      end

      defmodule Third.Me do
        def third(input) do
          AnotherModule.first(input)
        end
      end
      |

      result =
        file
        |> MDV.analyze()
        |> MDV.reverse_edges(
          edges_to_reverse: [{"First.Me", "AnotherModule"}, {~r/Third/, "AnotherModule"}]
        )
        |> Enum.sort()

      assert result ==
               Enum.sort([
                 {"AnotherModule", "First.Me"},
                 {"Second.Me", "AnotherModule"},
                 {"AnotherModule", "Third.Me"}
               ])
    end
  end

  describe "add node color" do
    test "assign colors to nodes" do
      graph = [
        {"AnotherModule", "First.Me"},
        {"Second.Me", "AnotherModule"},
        {"AnotherModule", "Third.They"}
      ]

      assert MDV.add_colors(graph, [{~r|Me|, "red"}, {~r|Third|, "green"}]) == [
               {"First.Me", [fillcolor: "red", style: "filled"]},
               {"Second.Me", [fillcolor: "red", style: "filled"]},
               {"Third.They", [fillcolor: "green", style: "filled"]}
             ]
    end
  end

  describe "create_gv_file/1" do
    test "turns a dependency list into a properly formatted graphviz file" do
      dependency_list = [
        {"Tester.One", "String"},
        {"Tester.One", "lists"},
        {"Tester.One", "Tester.MyOther"},
        {"Tester.One", "My.Long.Module.Chain"},
        {"Tester.Two", "Tester.One"}
      ]

      expected = """
      digraph G {
        "Tester.One" -> "String";
        "Tester.One" -> "lists";
        "Tester.One" -> "Tester.MyOther";
        "Tester.One" -> "My.Long.Module.Chain";
        "Tester.Two" -> "Tester.One";

      }
      """

      assert MDV.create_gv_file(dependency_list, []) == expected
    end

    # Example of the format
    # digraph D {
    #   B [shape=box]
    #   C [shape=circle]

    #   A -> B [style=dashed, color=grey]
    #   A -> C [color="black:invis:black"]
    #   A -> D [penwidth=5, arrowhead=none]

    #   A [shape=diamond, fillcolor=red, style=filled]
    # }
    test "colorize" do
      dependency_list = [
        {"Tester.One", "String"}
      ]

      nodes_with_attributes = [
        {"Tester.One", [fillcolor: "red", style: "filled"]}
      ]

      expected = """
      digraph G {
        "Tester.One" -> "String";
        "Tester.One" [fillcolor=red, style=filled];
      }
      """

      assert MDV.create_gv_file(dependency_list, nodes_with_attributes) == expected
    end
  end
end
