defmodule ModuleDependencyVisualizer do
  alias ModuleDependencyVisualizer.AnalyzeCode

  @moduledoc """
  This is the public interface for this simple little tool to parse a file or
  list of files for dependencies between modules. It will use the `dot` command
  to generate a graph PNG for us thanks to graphviz.
  """

  @doc """
  Analyzes a given list of file paths (absolute or relative), creates the
  necessary Graphviz file, and then creates the graph and opens it.
  """
  @spec run(list, list) :: :ok
  def run(file_paths, options) do
    dependency_list =
      file_paths
      |> analyze()
      |> filter(options)
      |> reverse_edges(options)

    nodes_with_attributes = add_colors(dependency_list, Keyword.get(options, :colors, []))

    dependency_list
    |> create_gv_file(nodes_with_attributes)
    |> create_and_open_graph()

    :ok
  end

  def analyze(file_paths) do
    AnalyzeCode.analyze(file_paths)
  end

  @doc """
  removes all modules not matching the given list of include: names
  """
  @spec filter([{String.t(), String.t()}], include: String.t()) :: [{String.t(), String.t()}]
  def filter(deps_graph, opts \\ []) when is_list(opts) do
    include_from = Keyword.get(opts, :include, [])
    exclude_to = Keyword.get(opts, :exclude, [])

    remove_all_graphs_not_connected_to =
      Keyword.get(opts, :remove_all_graphs_not_connected_to, :keep_all_graphs)

    deps_graph
    |> Enum.filter(fn {from, _to} -> contains_include_from(include_from, from) end)
    |> Enum.reject(fn {_from, to} -> exclude_to_contains?(exclude_to, to) end)
    |> RemoveUnconnectedGraphs.remove_unconnected_graphs(remove_all_graphs_not_connected_to)
  end

  @doc """
  reverse the direction on edges
  """
  @spec reverse_edges([{String.t(), String.t()}], [{String.t(), String.t()}]) :: [
          {String.t(), String.t()}
        ]
  def reverse_edges(deps_graph, opts) do
    edges_to_reverse = Keyword.get(opts, :edges_to_reverse, [])

    deps_graph
    |> Enum.map(fn {from, to} = deps_edge ->
      case edge_matches?(edges_to_reverse, deps_edge) do
        true ->
          {to, from}

        false ->
          deps_edge
      end
    end)
  end

  defp edge_matches?(edges_to_reverse, {dep_from, dep_to}) when is_list(edges_to_reverse) do
    Enum.any?(edges_to_reverse, fn {remove_from, remove_to} ->
      matches?(dep_from, remove_from) && matches?(dep_to, remove_to)
    end)
  end

  defp contains_include_from([], _from), do: true

  defp contains_include_from(include_to, from) do
    Enum.any?(include_to, fn list_elem when is_binary(list_elem) ->
      String.contains?(from, list_elem)
    end)
  end

  defp exclude_to_contains?(list, value) when is_binary(value) and is_list(list) do
    Enum.any?(list, fn list_elem ->
      matches?(value, list_elem)
    end)
  end

  defp matches?(value, pattern) when is_binary(pattern) do
    String.contains?(value, pattern)
  end

  defp matches?(value, pattern) do
    Regex.match?(pattern, value)
  end

  @doc """
  Creates nodes associated with the given color. Used for rendering of the graph with graphviz.
  """
  def add_colors(dependency_list, color_definitions) do
    dependency_list
    |> distinct_nodes()
    |> Enum.map(fn node ->
      Enum.find_value(color_definitions, fn {pattern, color} ->
        if Regex.match?(pattern, node) do
          node_with_color(node, color)
        end
      end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp distinct_nodes(dependency_list) do
    dependency_list
    |> Enum.reduce(MapSet.new(), fn {from, to}, set ->
      MapSet.put(set, from) |> MapSet.put(to)
    end)
    |> MapSet.to_list()
  end

  defp node_with_color(name, color) do
    {name, [fillcolor: color, style: "filled"]}
  end

  @doc """
  Takes a list of dependencies and returns a string that is a valid `dot` file.
  """
  @spec create_gv_file(list, list) :: String.t()
  def create_gv_file(dependency_list, nodes_with_attributes) do
    nodes =
      Enum.map(nodes_with_attributes, fn {node, attributes} ->
        serialized_attributes = Enum.map(attributes, fn {name, value} -> "#{name}=#{value}" end)
        ~s|  "#{node}" [#{Enum.join(serialized_attributes, ", ")}];|
      end)

    body = Enum.map(dependency_list, fn {mod1, mod2} -> "  \"#{mod1}\" -> \"#{mod2}\";" end)
    "digraph G {\n#{Enum.join(body, "\n")}\n#{Enum.join(nodes, "\n")}\n}\n"
  end

  @doc """
  This creates the graphviz file on disk, then runs the `dot` command to
  generate the graph as a PNG, and opens that PNG for you.
  """
  @spec create_and_open_graph(String.t()) :: {Collectable.t(), exit_status :: non_neg_integer}
  def create_and_open_graph(gv_file) do
    gv_file_path = "./output.gv"
    graph_path = "./graph.png"
    File.write(gv_file_path, gv_file)
    execute_graphviz(gv_file_path, graph_path)
    System.cmd("open", [graph_path])
  end

  defp execute_graphviz(gv_file_path, graph_path) do
    try do
      System.cmd("dot", ["-Tpng", gv_file_path, "-o", graph_path])
    rescue
      e ->
        IO.puts(
          "============================================================\n" <>
            "Could not generate graph.\n" <>
            "Do you have graphviz installed? Seems like the dot executable is not available.\n" <>
            "============================================================\n"
        )

        raise e
    end
  end
end
