defmodule RemoveUnconnectedGraphs do
  @doc """
  Removes all graphs not connected to given nodes.
  """
  def remove_unconnected_graphs(graph, :keep_all_graphs) do
    graph
  end

  def remove_unconnected_graphs(graph, node) when is_list(graph) do
    graph
    |> graph_from_dependencies()
    |> remove_unconnected_graphs(node)
    |> to_edges()
  end

  def remove_unconnected_graphs(%Graph{} = graph, node) do
    component_with_node =
      graph
      |> Graph.components()
      |> Enum.find(:node_not_found_in_any_component, fn components ->
        Enum.member?(components, node)
      end)

    Graph.subgraph(graph, component_with_node)
  end

  defp graph_from_dependencies(dependencies) do
    Enum.reduce(dependencies, Graph.new(), fn {from, to}, g -> Graph.add_edge(g, from, to) end)
  end

  defp to_edges(graph) do
    graph |> Graph.edges() |> Enum.map(fn %Graph.Edge{v1: from, v2: to} -> {from, to} end)
  end
end
