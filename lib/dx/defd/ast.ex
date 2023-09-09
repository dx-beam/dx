defmodule Dx.Defd.Ast do
  import __MODULE__.Guards

  def ensure_loaded(ast, data_reqs) do
    {loaders, vars} = Enum.unzip(data_reqs)
    ensure_loaded(ast, loaders, vars)
  end

  def ensure_loaded(ast, [], _vars) do
    ast
  end

  def ensure_loaded({:ok, var}, [loader], [var]) do
    loader
  end

  def ensure_loaded(ast, [loader], [var]) do
    quote do
      case unquote(loader) do
        {:ok, unquote(var)} -> unquote(ast)
        other -> other
      end
    end
  end

  def ensure_loaded(ast, list, vars) do
    deps = get_dependencies(list, vars)

    ensure_loaded(ast, list, vars, deps)
  end

  def ensure_loaded(ast, [], [], []) do
    ast
  end

  def ensure_loaded(ast, list, vars, deps) do
    {{ready_loaders, ready_vars}, {defer_loaders, defer_vars, defer_deps}} =
      [list, vars, deps]
      |> Enum.zip_reduce({{[], []}, {[], [], []}}, fn
        [loader, var, []], {{ready_loaders, ready_vars}, defer} ->
          {{[loader | ready_loaders], [var | ready_vars]}, defer}

        [loader, var, deps], {ready, {defer_loaders, defer_vars, defer_deps}} ->
          {ready, {[loader | defer_loaders], [var | defer_vars], [deps | defer_deps]}}
      end)

    defer_deps = Enum.map(defer_deps, fn loader_deps -> loader_deps -- ready_vars end)
    ast = ensure_loaded(ast, defer_loaders, defer_vars, defer_deps)

    quote do
      case Dx.Defd.Result.collect_reverse(unquote(ready_loaders), {:ok, []}) do
        {:ok, unquote(Enum.reverse(ready_vars))} -> unquote(ast)
        other -> other
      end
    end
  end

  defp get_dependencies(loaders, vars) do
    Enum.map(loaders, fn loader_ast ->
      loader_deps = collect_vars(loader_ast, %{})
      Enum.filter(vars, &Map.has_key?(loader_deps, var_id(&1)))
    end)
  end

  def is_function({:ok, {:fn, _meta, [{:->, _meta2, [args, _body]}]}}, arity) do
    length(args) == arity
  end

  def is_function({:&, _meta, [{:/, [], [{_fun_name, [], nil}, arity]}]}, arity) do
    true
  end

  def is_function({:&, _meta, [{:/, [], [{{:., [], [_mod, _fun_name]}, [], []}, arity]}]}, arity) do
    true
  end

  def is_function(_ast, _arity), do: false

  def ok({ast, state}) do
    {{:ok, ast}, state}
  end

  def ok?({:ok, {:fn, _meta, [{:->, _meta2, [_args, {:ok, _body}]}]}}), do: true
  def ok?({:ok, {:fn, _meta, [{:->, _meta2, [_args, _body]}]}}), do: false
  def ok?({:ok, _}), do: true
  def ok?(_other), do: false

  def unwrap_inner({:ok, {:fn, meta, [{:->, meta2, [args, {:ok, body}]}]}}) do
    {:fn, meta, [{:->, meta2, [args, body]}]}
  end

  def unwrap_inner(other) do
    unwrap(other)
  end

  def unwrap({:ok, ast}) do
    ast
  end

  def unwrap(ast) do
    quote location: :keep do
      Dx.Result.unwrap!(unquote(ast))
    end
  end

  def wrap_args([arg]) do
    arg
  end

  def wrap_args(args) do
    List.wrap(args)
  end

  def flatten_kv_list(kv_list) do
    Enum.flat_map(kv_list, fn {k, v} -> [k, v] end)
  end

  def unflatten_kv_list(kv_list) do
    Enum.chunk_every(kv_list, 2)
    |> Enum.map(fn [k, v] -> {k, v} end)
  end

  def var_id({var_name, meta, context}) do
    {var_name, Keyword.take(meta, [:version, :counter]), context}
  end

  def with_root_args(args, state, fun) do
    temp_state = Map.update!(state, :args, &collect_vars(args, &1))

    case fun.(temp_state) do
      {ast, updated_state} ->
        ast = ensure_loaded(ast, updated_state.data_reqs)
        {ast, %{updated_state | args: state.args, data_reqs: %{}}}

      other ->
        IO.inspect(other)
        raise CompileError
    end
  end

  # merge given args into state.args for calling fun,
  # then reset state.args to its original value
  def with_args(args, state, fun) do
    new_vars = collect_vars(args, %{})
    temp_state = Map.update!(state, :args, &collect_vars(args, &1))

    case fun.(temp_state) do
      {ast, updated_state} ->
        {ast, %{updated_state | args: state.args}}
        |> prepend_data_reqs_in(new_vars)
    end
  end

  defp prepend_data_reqs_in({ast, state}, vars) do
    {local_data_reqs, other_data_reqs} =
      Enum.split_with(state.data_reqs, fn {loader_ast, _data_var} ->
        any_var_in?(loader_ast, vars)
      end)

    ast = ensure_loaded(ast, Map.new(local_data_reqs))

    {ast, %{state | data_reqs: Map.new(other_data_reqs)}}
  end

  defp any_var_in?(ast, vars) do
    ast
    |> collect_vars(%{})
    |> Enum.any?(fn {var, _} -> Map.has_key?(vars, var) end)
  end

  def collect_vars({:%, _meta, [_type, map]}, acc) do
    collect_vars(map, acc)
  end

  def collect_vars({:%{}, _meta, pairs}, acc) do
    Enum.reduce(pairs, acc, fn {k, v}, acc ->
      acc = collect_vars(k, acc)
      collect_vars(v, acc)
    end)
  end

  def collect_vars({_, _, args}, acc) when is_list(args) do
    collect_vars(args, acc)
  end

  def collect_vars({arg0, arg1}, acc) do
    acc = collect_vars(arg0, acc)
    collect_vars(arg1, acc)
  end

  def collect_vars([ast | tail], acc) do
    acc = collect_vars(ast, acc)
    collect_vars(tail, acc)
  end

  def collect_vars(var, acc) when is_var(var) do
    Map.put(acc, var_id(var), true)
  end

  def collect_vars(_other, acc) do
    acc
  end

  def fetch({:ok, ast}, key, eval, line) when is_var(ast) do
    asty = {{:., [line: line], [ast, key]}, [no_parens: true, line: line], []}

    quote line: line do
      Dx.Defd.Util.fetch(unquote(ast), unquote(asty), unquote(key), unquote(eval))
    end
  end

  def fetch({:ok, ast}, key, eval, line) do
    var = Macro.unique_var(:map, __MODULE__)
    asty = {{:., [line: line], [var, key]}, [no_parens: true, line: line], []}

    {:__block__, [],
     [
       {:=, [], [var, ast]},
       {{:., [line: line],
         [{:__aliases__, [line: line, alias: false], [:Dx, :Defd, :Util]}, :fetch]}, [line: line],
        [var, asty, key, eval]}
     ]}
  end

  def fetch(ast, key, eval, line) do
    var = Macro.unique_var(:map, __MODULE__)
    asty = {{:., [line: line], [var, key]}, [no_parens: true, line: line], []}

    quote line: line do
      case unquote(ast) do
        {:ok, unquote(var)} ->
          Dx.Defd.Util.fetch(unquote(var), unquote(asty), unquote(key), unquote(eval))

        other ->
          other
      end
    end
  end

  # Helpers

  def p(ast, label \\ nil)

  def p(ast, nil) do
    IO.puts("\n\n" <> Macro.to_string(ast) <> "\n\n")
    ast
  end

  def p(ast, label) do
    IO.puts("\n\n#{label}:\n" <> Macro.to_string(ast) <> "\n\n")
    ast
  end
end
