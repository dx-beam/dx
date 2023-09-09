defmodule Dx.Defd.Case do
  alias Dx.Defd.Ast
  alias Dx.Defd.Compiler

  def normalize({:case, meta, [subject, [do: clauses]]}, state) do
    data_req = data_req_from_clauses(clauses, %{})

    {subject, state} = Compiler.normalize(subject, state)

    {subject, state} =
      case subject do
        {:ok, subject} ->
          {subject, state}

        loader ->
          reqs = Map.put_new(state.data_reqs, loader, Macro.unique_var(:data, __MODULE__))
          var = reqs[loader]
          {var, %{state | data_reqs: reqs}}
      end

    {clauses, state} = normalize_clauses(clauses, state)

    ast =
      if data_req == %{} do
        # nothing to load in any pattern
        {:case, meta, [subject, [do: clauses]]}
      else
        # ensure data requirements are preloaded
        subject_var = Macro.unique_var(:subject, __MODULE__)
        case_ast = {:case, meta, [subject_var, [do: clauses]]}

        quote do
          case Dx.Defd.Util.fetch(
                 unquote(subject),
                 unquote(Macro.escape(data_req)),
                 unquote(state.eval_var)
               ) do
            {:ok, unquote(subject_var)} -> unquote(case_ast)
            other -> other
          end
        end
      end

    {ast, state}
  end

  def normalize({:case, meta, _args}, state) do
    Compiler.compile_error!(meta, state, """
    Invalid case syntax. Add a do .. end block like the following:

    case ... do
      pattern -> result
      ...
    end
    """)
  end

  def normalize_clauses(clauses, state) do
    Enum.map_reduce(clauses, state, &normalize_clause/2)
  end

  def normalize_clause({:->, meta, [[pattern], ast]}, state) do
    {ast, state} =
      Ast.with_args(pattern, state, fn state ->
        Compiler.normalize(ast, state)
      end)

    ast = {:->, meta, [[pattern], ast]}

    {ast, state}
  end

  defp data_req_from_clauses([], acc) do
    acc
  end

  defp data_req_from_clauses([{:->, _meta, [[pattern], _result]} | tail], acc) do
    data_req = quoted_data_req(pattern)
    acc = Dx.Util.deep_merge(acc, data_req)
    data_req_from_clauses(tail, acc)
  end

  defp quoted_data_req({elem_0, elem_1}) do
    maybe_add_elems({:__tuple__, 2}, [elem_0, elem_1])
  end

  defp quoted_data_req({:{}, _meta, tuple_elems}) do
    maybe_add_elems({:__tuple__, length(tuple_elems)}, tuple_elems)
  end

  defp quoted_data_req(list) when is_list(list) do
    maybe_add_elems(:__list__, list)
  end

  defp quoted_data_req({:%, _meta, [_type, map]}) do
    quoted_data_req(map)
  end

  defp quoted_data_req({:%{}, _meta, pairs}) do
    Map.new(pairs, fn
      {k, v} when is_atom(k) -> {k, quoted_data_req(v)}
      {k, v} -> {quoted_data_req(k), quoted_data_req(v)}
    end)
  end

  defp quoted_data_req(_other) do
    %{}
  end

  defp maybe_add_elems(key, elems) do
    maybe_add_nested(%{}, key, maybe_add_elems(elems))
  end

  defp maybe_add_elems(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {elem, index}, acc ->
      maybe_add_nested(acc, index, quoted_data_req(elem))
    end)
  end

  defp maybe_add_nested(map, _key, val) when val == %{}, do: map
  defp maybe_add_nested(map, key, val), do: Map.put(map, key, val)
end
