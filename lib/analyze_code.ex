defmodule ModuleDependencyVisualizer.AnalyzeCode do
  @doc """
  This will accept a list of file paths (absolute or relative), read each of
  those files, and return a keyword list of all the module dependencies in
  all those files. The output looks something like this:

  [{"ModuleName", "String"}, {"ModuleName", "lists"}]

  The lowercase modules are Erlang modules, and the camelcase modules are all
  Elixir modules.
  """
  @spec analyze([String.t()]) :: [{String.t(), String.t()}]
  def analyze(file_paths) when is_list(file_paths) do
    Enum.flat_map(file_paths, fn file_path ->
      {:ok, file} = File.read(file_path)
      analyze(file)
    end)
  end

  # Analyzes a single file for dependencies between modules. This is the real meat
  # of this tool. After this is done, then it's just formatting the graphviz file
  # correctly and that's pretty easy.

  @spec analyze(String.t()) :: [{String.t(), String.t()}]
  def analyze(file) when is_binary(file) do
    {:ok, ast} = Code.string_to_quoted(file)

    {_, all_modules} =
      Macro.postwalk(ast, [], fn
        ast = {:defmodule, _meta, module_ast}, modules ->
          {ast, modules ++ [deps_for_module(module_ast)]}

        ast, modules ->
          {ast, modules}
      end)

    List.flatten(all_modules)
  end

  defp deps_for_module(ast) do
    # ast
    # |> IO.inspect(label: "#{__MODULE__}:#{__ENV__.line} #{DateTime.utc_now()}", limit: :infinity)

    {_, dependencies} =
      Macro.postwalk(ast, [], fn
        ast = {:., _meta, [module, _]}, modules when is_atom(module) ->
          {ast, modules ++ [[module]]}

        ast = {:., _meta, [{:__aliases__, _, [{:@, _, _}, module]}, _]}, modules ->
          {ast, modules ++ [[module]]}

        ast = {:., _meta, [{:__aliases__, _, module_info}, _]}, modules ->
          {ast, modules ++ [module_info]}

        ast, modules ->
          {ast, modules}
      end)

    {_, [dependent | other_modules]} =
      Macro.postwalk(ast, [], fn
        ast = {:__aliases__, _meta, [{:@, _meta2, [_more_meta]}, module]}, modules ->
          {ast, modules ++ [[module]]}

        ast = {:__aliases__, _meta, module_info}, modules ->
          {ast, modules ++ [module_info]}

        ast, modules ->
          {ast, modules}
      end)

    {_, alias_info} =
      Macro.postwalk(ast, [], fn
        ast = {:alias, _meta, info}, aliases ->
          {ast, aliases ++ [info]}

        ast = {:require, _, alias_info = [{:__aliases__, _, _}, [as: {:__aliases__, _, _}]]},
        aliases ->
          {ast, aliases ++ [alias_info]}

        ast, aliases ->
          {ast, aliases}
      end)

    total_modules = Enum.uniq(dependencies ++ other_modules)

    total_modules
    |> reconcile_aliases(alias_info)
    |> Enum.map(fn module_info ->
      {format_module(dependent), format_module(module_info)}
    end)
  end

  defp reconcile_aliases(mods, []), do: mods

  defp reconcile_aliases(mods, aliases) do
    mods
    |> remove_bare_aliases(aliases)
    |> remove_as_aliases(aliases)
    |> remove_multi_aliases(aliases)
  end

  # defp remove_module_attribute_aliases(mods, aliases) do
  #   bare_aliases =
  #     aliases
  #     |> Enum.filter(fn
  #       [{:__aliases__, _meta, _alias_info}] -> true
  #       _ -> false
  #     end)
  #     |> Enum.map(fn [{:__aliases__, _meta, alias_info}] -> alias_info end)

  #   filtered =
  #     mods
  #     |> Enum.filter(fn module_info -> !Enum.member?(bare_aliases, module_info) end)
  #     |> Enum.map(fn module_info ->
  #       matching_alias =
  #         Enum.find(bare_aliases, fn alias_info ->
  #           List.last(alias_info) == hd(module_info)
  #         end)

  #       if is_nil(matching_alias) do
  #         module_info
  #       else
  #         Enum.drop(matching_alias, -1) ++ module_info
  #       end
  #     end)

  #   filtered
  # end

  defp remove_bare_aliases(mods, aliases) do
    bare_aliases =
      aliases
      |> Enum.filter(fn
        [{:__aliases__, _meta, _alias_info}] -> true
        _ -> false
      end)
      |> Enum.map(fn [{:__aliases__, _meta, alias_info}] -> alias_info end)

    filtered =
      mods
      |> Enum.filter(fn module_info -> !Enum.member?(bare_aliases, module_info) end)
      |> Enum.map(fn module_info ->
        matching_alias =
          Enum.find(bare_aliases, fn alias_info ->
            List.last(alias_info) == hd(module_info)
          end)

        if is_nil(matching_alias) do
          module_info
        else
          Enum.drop(matching_alias, -1) ++ module_info
        end
      end)

    filtered
  end

  defp remove_as_aliases(mods, aliases) do
    as_aliases =
      aliases
      |> Enum.filter(fn
        [{:__aliases__, _, _}, [as: {:__aliases__, _, _}]] -> true
        _ -> false
      end)
      |> Enum.map(fn [{_, _, full_info}, [as: {_, _, alias_info}]] -> {full_info, alias_info} end)

    filtered =
      mods
      |> Enum.reject(fn module_info ->
        Enum.any?(as_aliases, fn {full_name, _alias_name} ->
          module_info == full_name
        end)
      end)
      |> Enum.map(fn module_info ->
        matching_alias =
          Enum.find(as_aliases, fn {_, alias_name} ->
            alias_name == module_info
          end)

        if is_nil(matching_alias) do
          module_info
        else
          {new_name, _} = matching_alias
          new_name
        end
      end)

    filtered
  end

  defp remove_multi_aliases(mods, aliases) do
    multi_aliases =
      aliases
      |> Enum.filter(fn
        [{{:., _, [{:__aliases__, _, _}, :{}]}, _, _}] -> true
        _ -> false
      end)
      |> Enum.flat_map(fn [{{:., _, [{_, _, outside}, _]}, _, aliases}] ->
        Enum.map(aliases, fn {:__aliases__, _, suffix} -> outside ++ suffix end)
      end)

    filtered =
      mods
      |> Enum.reject(fn module_info ->
        Enum.any?(multi_aliases, fn alias_info ->
          module_info == Enum.drop(alias_info, -1)
        end)
      end)
      |> Enum.map(fn module_info ->
        matching_alias =
          Enum.find(multi_aliases, fn alias_info ->
            [List.last(alias_info)] == module_info
          end)

        if is_nil(matching_alias) do
          module_info
        else
          matching_alias
        end
      end)

    filtered
  end

  defp format_module(module_info) do
    Enum.join(module_info, ".")
  end
end
