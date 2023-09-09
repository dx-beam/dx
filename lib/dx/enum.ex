defmodule Dx.Enum do
  alias Dx.Defd.Ast
  alias Dx.Defd.Compiler
  alias Dx.Defd.Result

  @chunk_while_chunk_fun_warning """
  Dx can't load data efficiently within functions passed as chunk_fun to Enum.chunk_while

  Please pass a function that doesn't load any data, for example replace

      Enum.chunk_while(records, 0, fn record, acc ->
        {:cont, [record.assoc.weight + acc], acc + 1}
      end, fn acc -> {:cont, acc} end)

  with

      records
      |> Enum.map(& &1.assoc.weight)
      |> Enum.chunk_while(0, fn weight, acc ->
        {:cont, [weight + acc], acc + 1}
      end, fn acc -> {:cont, acc} end)
  """

  @each_warning """
  Enum.each does not return any data, so you might try using it for side effects.

  Dx does not support any side effects within functions defined with defd,
  such as sending messages, printing output, modifying external data, etc.

  Side effects can be repeated any number of times, depending on how exactly
  the data will be loaded by Dx. They are not predictable and hence not supported.
  """

  @flat_map_reduce_warning """
  Dx can't load data efficiently within functions passed to Enum.flat_map_reduce

  Please pass a function that doesn't load any data, for example replace

      Enum.flat_map_reduce(records, 0, fn record, acc ->
        [record.assoc.weight + acc]
      end)

  with

      records
      |> Enum.map(& &1.assoc.weight)
      |> Enum.flat_map_reduce(0, fn weight, acc -> [weight + acc] end)
  """

  @map_reduce_warning """
  Dx can't load data efficiently within functions passed to Enum.map_reduce

  Please pass a function that doesn't load any data, for example replace

      Enum.map_reduce(records, 0, fn record, acc ->
        record.assoc.weight + acc
      end)

  with

      records
      |> Enum.map(& &1.assoc.weight)
      |> Enum.map_reduce(0, fn weight, acc -> weight + acc end)
  """

  @max_warning """
  Dx can't load data efficiently within sorter functions.

  Please use max_by/3 instead.
  """

  @min_warning """
  Dx can't load data efficiently within sorter functions.

  Please use min_by/3 instead.
  """

  @reduce_warning """
  Dx can't load data efficiently within functions passed to Enum.reduce

  Please pass a function that doesn't load any data, for example replace

      Enum.reduce(records, 0, fn record, acc ->
        record.assoc.weight + acc
      end)

  with

      records
      |> Enum.map(& &1.assoc.weight)
      |> Enum.reduce(0, fn weight, acc -> weight + acc end)
  """

  @reduce_while_warning """
  Dx can't load data efficiently within functions passed to Enum.reduce_while

  Please pass a function that doesn't load any data, for example replace

  Enum.reduce_while(records, 0, fn record, acc ->
    {:cont, record.assoc.weight + acc}
  end)

  with

  records
  |> Enum.map(& &1.assoc.weight)
  |> Enum.reduce_while(0, fn weight, acc -> {:cont, weight + acc} end)
  """

  @scan_warning """
  Dx can't load data efficiently within functions passed to Enum.scan

  Please pass a function that doesn't load any data, for example replace

      Enum.scan(records, 0, fn record, acc ->
        record.assoc.weight + acc
      end)

  with

      records
      |> Enum.map(& &1.assoc.weight)
      |> Enum.scan(0, fn weight, acc -> weight + acc end)
  """

  @sort_warning """
  Dx can't load data efficiently within sorter functions.

  Please use sort_by/2 instead.
  """

  @sorter_warning """
  Dx can't load data efficiently within sorter functions.

  Please load all needed data in the mapping function.
  """

  @zip_reduce_3_warning """
  Dx can't load data efficiently within functions passed to Enum.zip_reduce/3

  Please pass a function that doesn't load any data, for example replace

      Enum.zip_reduce([enum1, enum2], 0, fn record1, record2, acc ->
        record1.assoc.weight + record2.assoc.weight + acc
      end)

  with

      enum1_loaded = Enum.map(enum1, & &1.assoc.weight)
      enum2_loaded = Enum.map(enum2, & &1.assoc.weight)

      [enum1_loaded, enum2_loaded]
      |> Enum.reduce(0, fn weight1, weight2, acc -> weight1 + weight2 + acc end)
  """

  @zip_reduce_4_warning """
  Dx can't load data efficiently within functions passed to Enum.zip_reduce/4

  Please pass a function that doesn't load any data, for example replace

      Enum.zip_reduce(enum1, enum2, 0, fn record1, record2, acc ->
        record1.assoc.weight + record2.assoc.weight + acc
      end)

  with

      enum1_loaded = Enum.map(enum1, & &1.assoc.weight)
      enum2_loaded = Enum.map(enum2, & &1.assoc.weight)

      Enum.reduce(enum1_loaded, enum2_loaded, 0, fn weight1, weight2, acc ->
        weight1 + weight2 + acc
      end)
  """

  @static_warnings %{
    {:each, 2} => @each_warning
  }

  @warnings %{
    {:flat_map_reduce, 3} => @flat_map_reduce_warning,
    {:map_reduce, 3} => @map_reduce_warning,
    {:max, 3} => @max_warning,
    {:min, 3} => @min_warning,
    {:reduce, 2} => @reduce_warning,
    {:reduce, 3} => @reduce_warning,
    {:reduce_while, 3} => @reduce_while_warning,
    {:scan, 2} => @scan_warning,
    {:scan, 3} => @scan_warning,
    {:sort, 2} => @sort_warning,
    {:zip_reduce, 3} => @zip_reduce_3_warning,
    {:zip_reduce, 4} => @zip_reduce_4_warning
  }

  # &Enum.fun/3
  def rewrite(
        {:&, meta, [{:/, [], [{{:., [], [Enum, fun_name]}, [], []}, arity]}]} = fun,
        state
      ) do
    ast =
      cond do
        state.in_external? and state.in_fn? ->
          fun

        function_exported?(__MODULE__, fun_name, arity) ->
          args = Macro.generate_arguments(arity, __MODULE__)
          line = meta[:line] || state.line

          quote line: line do
            {:ok,
             fn unquote_splicing(args) ->
               unquote(__MODULE__).unquote(fun_name)(unquote_splicing(args))
             end}
          end

        true ->
          args = Macro.generate_arguments(arity, __MODULE__)
          line = meta[:line] || state.line

          quote line: line do
            {:ok,
             fn unquote_splicing(args) ->
               {:ok, unquote(Enum).unquote(fun_name)(unquote_splicing(args))}
             end}
          end
      end

    {ast, state}
  end

  def rewrite({{:., meta, [Enum, fun_name]}, meta2, args} = orig, state) do
    arity = length(args)

    {args, state} = Enum.map_reduce(args, state, &Compiler.normalize/2)

    ast =
      cond do
        Enum.all?(args, &Ast.ok?/1) ->
          maybe_warn_static(meta, fun_name, arity, args, state)

          args = Enum.map(args, &Ast.unwrap_inner/1)

          {:ok, {{:., meta, [Enum, fun_name]}, meta2, args}}

        function_exported?(__MODULE__, fun_name, arity) ->
          maybe_warn(meta, fun_name, arity, args, state)

          args = Enum.map(args, &Ast.unwrap/1)
          {{:., meta, [__MODULE__, fun_name]}, meta2, args}

        true ->
          maybe_warn_static(meta, fun_name, arity, args, state)

          orig
      end

    {ast, state}
  end

  defp maybe_warn(meta, fun_name, arity, args, state) do
    cond do
      fun_name == :chunk_while and Ast.is_function(Enum.at(args, 2), 2) and
          not Ast.ok?(Enum.at(args, 2)) ->
        Compiler.warn(meta, state, @chunk_while_chunk_fun_warning)

      fun_name == :max and Ast.is_function(Enum.at(args, 1), 2) and
          not Ast.ok?(Enum.at(args, 1)) ->
        Compiler.warn(meta, state, @max_warning)

      fun_name == :max_by and Ast.is_function(Enum.at(args, 2), 2) and
          not Ast.ok?(Enum.at(args, 2)) ->
        Compiler.warn(meta, state, @sorter_warning)

      fun_name == :min and Ast.is_function(Enum.at(args, 1), 2) and
          not Ast.ok?(Enum.at(args, 1)) ->
        Compiler.warn(meta, state, @min_warning)

      fun_name == :min_by and Ast.is_function(Enum.at(args, 2), 2) and
          not Ast.ok?(Enum.at(args, 2)) ->
        Compiler.warn(meta, state, @sorter_warning)

      fun_name == :min_max_by and Ast.is_function(Enum.at(args, 2), 2) and
          not Ast.ok?(Enum.at(args, 2)) ->
        Compiler.warn(meta, state, @sorter_warning)

      fun_name == :sort_by and Ast.is_function(Enum.at(args, 2), 2) and
          not Ast.ok?(Enum.at(args, 2)) ->
        Compiler.warn(meta, state, @sorter_warning)

      warning = Map.get(@warnings, {fun_name, arity}) ->
        Compiler.warn(meta, state, warning)

      true ->
        :ok
    end
  end

  defp maybe_warn_static(meta, fun_name, arity, _args, state) do
    cond do
      warning = Map.get(@static_warnings, {fun_name, arity}) ->
        Compiler.warn(meta, state, warning)

      true ->
        :ok
    end
  end

  def all?(enumerable, fun) do
    Result.all?(enumerable, fun)
  end

  def any?(enumerable, fun) do
    Result.any?(enumerable, fun)
  end

  def chunk_by([], _fun) do
    {:ok, []}
  end

  def chunk_by(enumerable, fun) do
    Result.map_then_reduce_ok(enumerable, fun, [], fn
      elem, mapped, [] ->
        {mapped, [[elem]]}

      elem, prev_mapped, {prev_mapped, [group | rest]} ->
        {prev_mapped, [[elem | group] | rest]}

      elem, mapped, {_prev_mapped, [prev_group | rest]} ->
        {mapped, [[elem], :lists.reverse(prev_group) | rest]}
    end)
    |> Result.transform(fn
      [] ->
        []

      {_last_mapped, [last_group | groups]} ->
        [:lists.reverse(last_group) | groups]
        |> :lists.reverse()
    end)
  end

  def chunk_while(enumerable, acc, chunk_fun, after_fun) do
    Result.reduce_while(enumerable, {[], acc}, fn entry, {buffer, acc} ->
      chunk_fun.(entry, acc)
      |> Result.transform_while(fn
        {:cont, chunk, acc} -> {:cont, {[chunk | buffer], acc}}
        {:cont, acc} -> {:cont, {buffer, acc}}
        {:halt, acc} -> {:halt, {buffer, acc}}
      end)
    end)
    |> Result.then(fn {res, acc} ->
      after_fun.(acc)
      |> Result.transform(fn
        {:cont, _acc} -> :lists.reverse(res)
        {:cont, chunk, _acc} -> :lists.reverse([chunk | res])
      end)
    end)
  end

  def count(enumerable, fun) do
    Result.map_then_reduce_ok(enumerable, fun, 0, fn mapped, acc ->
      if mapped, do: acc + 1, else: acc
    end)
  end

  def count_until(enumerable, fun, limit) do
    stop_at = limit - 1

    Result.map_then_reduce_ok_while(enumerable, fun, 0, fn
      mapped, ^stop_at ->
        if mapped, do: {:halt, limit}, else: {:cont, stop_at}

      mapped, acc ->
        if mapped, do: {:cont, acc + 1}, else: {:cont, acc}
    end)
  end

  def dedup_by(enumerable, fun) do
    map(enumerable, fun)
    |> Result.transform(fn mapped ->
      Enum.zip(enumerable, mapped)
      |> Enum.dedup_by(fn {_, mapped} -> mapped end)
      |> Enum.map(fn {elem, _} -> elem end)
    end)
  end

  def drop_while(enumerable, fun) do
    Result.map_then_reduce_ok(enumerable, fun, [], fn
      elem, mapped, [] -> if mapped, do: [], else: [elem]
      elem, _mapped, acc -> [elem | acc]
    end)
    |> Result.transform(&:lists.reverse/1)
  end

  def each(enumerable, fun) do
    map(enumerable, fun)
    |> Result.transform(fn _ -> :ok end)
  end

  def filter(enumerable, fun) do
    Result.map_then_reduce_ok(enumerable, fun, [], fn elem, mapped, acc ->
      if mapped, do: [elem | acc], else: acc
    end)
    |> Result.transform(&:lists.reverse/1)
  end

  @doc false
  @deprecated "Use Enum.filter/2 + Enum.map/2 or for comprehensions instead"
  def filter_map(enumerable, filter, mapper) do
    filter(enumerable, filter)
    |> Result.then(&map(&1, mapper))
  end

  def find(enumerable, default \\ nil, fun) do
    Result.find(enumerable, fun, &Result.ok/1, Result.ok(default))
  end

  def find_index(enumerable, fun) do
    Result.map_then_reduce_ok_while(enumerable, fun, 0, fn mapped, index ->
      if mapped, do: {:halt, {:found, index}}, else: {:cont, index + 1}
    end)
    |> Result.transform(fn
      {:found, index} -> index
      _last_index -> nil
    end)
  end

  def find_value(enumerable, default \\ nil, fun) do
    Result.find_value(enumerable, fun, Result.ok(default))
  end

  def flat_map(enumerable, fun) do
    Enum.map(enumerable, fun)
    |> Result.collect_reverse()
    |> Result.transform(&flat_reverse(&1, []))
  end

  def flat_map_reduce(enumerable, acc, fun) do
    Result.reduce_while(enumerable, {[], acc}, fn elem, {list, acc} ->
      fun.(elem, acc)
      |> Result.transform(fn
        {:halt, result} ->
          {:halt, {list, result}}

        {new_list, new_acc} ->
          {:cont, {[new_list | list], new_acc}}

        other ->
          raise ArgumentError,
                """
                The function passed to Enum.flat_map_reduce must return a 2-tuple.

                Got: #{inspect(other, pretty: true, limit: 10)}
                """
      end)
    end)
    |> Result.transform(fn
      {list, acc} -> {flat_reverse(list, []), acc}
    end)
  end

  defp flat_reverse([h | t], acc), do: flat_reverse(t, h ++ acc)
  defp flat_reverse([], acc), do: acc

  def frequencies_by(enumerable, key_fun) do
    Result.map_then_reduce_ok(enumerable, key_fun, %{}, fn mapped, acc ->
      Map.update(acc, mapped, 1, &(&1 + 1))
    end)
  end

  def group_by(enumerable, key_fun) when is_function(key_fun) do
    Result.map_then_reduce_ok(enumerable, key_fun, %{}, fn elem, mapped_key, acc ->
      Map.update(acc, mapped_key, [elem], &[elem | &1])
    end)
    |> Result.transform(fn acc ->
      Map.new(acc, fn {k, v} -> {k, :lists.reverse(v)} end)
    end)
  end

  def group_by(enumerable, key_fun, value_fun)
      when is_function(key_fun) do
    Result.map_then_reduce_ok(
      enumerable,
      &Result.collect_reverse([key_fun.(&1), value_fun.(&1)]),
      %{},
      fn [mapped_value, mapped_key], acc ->
        Map.update(acc, mapped_key, [mapped_value], &[mapped_value | &1])
      end
    )
    |> Result.transform(fn acc ->
      Map.new(acc, fn {k, v} -> {k, :lists.reverse(v)} end)
    end)
  end

  def into(enumerable, collectable, transform) do
    map(enumerable, transform)
    |> Result.transform(&Enum.into(&1, collectable))
  end

  def map(enumerable, fun) do
    Result.map(enumerable, fun)
  end

  def map_every(enumerable, 1, fun), do: map(enumerable, fun)
  def map_every(enumerable, 0, _fun), do: {:ok, Enum.to_list(enumerable)}
  def map_every([], nth, _fun) when is_integer(nth) and nth > 1, do: {:ok, []}

  def map_every(enumerable, nth, fun) when is_integer(nth) and nth > 1 do
    Enum.reduce_while(enumerable, {{:ok, []}, nth}, fn
      elem, {acc, ^nth} ->
        Result.combine(fun.(elem), acc)
        |> case do
          {:cont, combined} -> {:cont, {combined, 1}}
          other -> other
        end

      elem, {acc, index} ->
        Result.combine({:ok, elem}, acc)
        |> case do
          {:cont, combined} -> {:cont, {combined, index + 1}}
          other -> other
        end
    end)
    |> elem(0)
    |> Result.transform(&:lists.reverse/1)
  end

  def map_intersperse(enumerable, separator, mapper) do
    Result.map_then_reduce_ok(enumerable, mapper, :first, fn
      mapped, :first -> [mapped]
      mapped, acc -> [mapped, separator | acc]
    end)
    |> Result.transform(fn
      :first -> []
      acc -> :lists.reverse(acc)
    end)
  end

  def map_join(enumerable, joiner \\ "", mapper) do
    enumerable
    |> map_intersperse(joiner, fn entry ->
      mapper.(entry)
      |> Result.transform(&entry_to_string/1)
    end)
    |> Result.transform(&IO.iodata_to_binary/1)
  end

  def map_reduce(enumerable, acc, fun) do
    Result.reduce(enumerable, {[], acc}, fn elem, {list, acc} ->
      fun.(elem, acc)
      |> Result.transform(fn
        {mapped, new_acc} -> {[mapped | list], new_acc}
      end)
    end)
    |> Result.transform(fn
      {list, acc} -> {:lists.reverse(list), acc}
    end)
  end

  def max(enumerable, empty_fallback) when is_function(empty_fallback, 0) do
    case Enum.max(enumerable, fn -> :empty end) do
      :empty -> empty_fallback.()
      max -> {:ok, max}
    end
  end

  def max(enumerable, sorter, empty_fallback \\ fn -> raise Enum.EmptyError end) do
    sorter = max_sort_fun(sorter)

    Result.reduce(enumerable, fn elem, acc ->
      sorter.(acc, elem)
      |> Result.transform(fn
        true -> acc
        false -> elem
      end)
    end)
    |> Result.transform(empty_fallback)
  end

  defp max_sort_fun(sorter) when is_function(sorter, 2), do: sorter
  defp max_sort_fun(module) when is_atom(module), do: &{:ok, module.compare(&1, &2) != :lt}

  def max_by(enumerable, fun) do
    max_by(enumerable, fun, fn -> raise Enum.EmptyError end)
  end

  def max_by(enumerable, fun, empty_fallback)
      when is_function(fun, 1) and is_function(empty_fallback, 0) do
    max_by(enumerable, fun, &{:ok, &1 >= &2}, empty_fallback)
  end

  def max_by(enumerable, fun, sorter, empty_fallback \\ fn -> raise Enum.EmptyError end)
      when is_function(fun, 1) do
    first_fun = fn elem -> fun.(elem) |> Result.transform(&{elem, &1}) end
    sorter = max_sort_fun(sorter)

    Result.map_then_reduce(enumerable, fun, first_fun, fn elem, mapped, {acc_elem, acc_mapped} ->
      sorter.(acc_mapped, mapped)
      |> Result.transform(fn
        true -> {acc_elem, acc_mapped}
        false -> {elem, mapped}
      end)
    end)
    |> Result.transform(empty_fallback, &elem(&1, 0))
  end

  def min(enumerable, empty_fallback) when is_function(empty_fallback, 0) do
    case Enum.min(enumerable, fn -> :empty end) do
      :empty -> empty_fallback.()
      min -> {:ok, min}
    end
  end

  def min(enumerable, sorter, empty_fallback \\ fn -> raise Enum.EmptyError end) do
    Result.reduce(enumerable, fn elem, acc ->
      sorter.(acc, elem)
      |> Result.transform(fn
        true -> acc
        false -> elem
      end)
    end)
    |> Result.transform(empty_fallback)
  end

  def min_by(enumerable, fun) when is_function(fun, 1) do
    min_by(enumerable, fun, &{:ok, &1 <= &2}, fn -> raise Enum.EmptyError end)
  end

  def min_by(enumerable, fun, empty_fallback)
      when is_function(fun, 1) and is_function(empty_fallback, 0) do
    min_by(enumerable, fun, &{:ok, &1 <= &2}, empty_fallback)
  end

  def min_by(enumerable, fun, sorter, empty_fallback \\ fn -> raise Enum.EmptyError end)
      when is_function(fun, 1) do
    first_fun = fn elem -> fun.(elem) |> Result.transform(&{elem, &1}) end
    sorter = min_sort_fun(sorter)

    Result.map_then_reduce(enumerable, fun, first_fun, fn elem, mapped, {acc_elem, acc_mapped} ->
      sorter.(acc_mapped, mapped)
      |> Result.transform(fn
        true -> {acc_elem, acc_mapped}
        false -> {elem, mapped}
      end)
    end)
    |> Result.transform(empty_fallback, &elem(&1, 0))
  end

  defp min_sort_fun(sorter) when is_function(sorter, 2), do: sorter
  defp min_sort_fun(module) when is_atom(module), do: &{:ok, module.compare(&1, &2) != :gt}

  def min_max(enumerable, empty_fallback) when is_function(empty_fallback, 0) do
    if Enum.empty?(enumerable) do
      empty_fallback.()
    else
      {:ok, Enum.min_max(enumerable)}
    end
  end

  def min_max_by(enumerable, fun, empty_fallback)
      when is_function(fun, 1) and is_function(empty_fallback, 0) do
    min_max_by(enumerable, fun, &{:ok, &1 < &2}, empty_fallback)
  end

  def min_max_by(
        enumerable,
        fun,
        sorter_or_empty_fallback \\ &{:ok, &1 < &2},
        empty_fallback \\ fn -> raise Enum.EmptyError end
      )

  def min_max_by(enumerable, fun, sorter, empty_fallback)
      when is_function(fun, 1) and is_atom(sorter) and is_function(empty_fallback, 0) do
    min_max_by(enumerable, fun, min_max_by_sort_fun(sorter), empty_fallback)
  end

  def min_max_by(enumerable, fun, sorter, empty_fallback)
      when is_function(fun, 1) and is_function(sorter, 2) and is_function(empty_fallback, 0) do
    first_fun = fn elem -> fun.(elem) |> Result.transform(&{elem, &1, elem, &1}) end

    Result.map_then_reduce(enumerable, fun, first_fun, fn
      elem, mapped, {min_elem, min_mapped, max_elem, max_mapped} ->
        sorter.(mapped, min_mapped)
        |> Result.then(fn
          true ->
            {:ok, {elem, mapped, max_elem, max_mapped}}

          false ->
            sorter.(max_mapped, mapped)
            |> Result.transform(fn
              true -> {min_elem, min_mapped, elem, mapped}
              false -> {min_elem, min_mapped, max_elem, max_mapped}
            end)
        end)
    end)
    |> Result.transform(empty_fallback, fn
      {min_elem, _, max_elem, _} -> {min_elem, max_elem}
    end)
  end

  defp min_max_by_sort_fun(module) when is_atom(module), do: &{:ok, module.compare(&1, &2) == :lt}

  @doc false
  @deprecated "Use Enum.split_with/2 instead"
  def partition(enumerable, fun) do
    split_with(enumerable, fun)
  end

  def reduce([h | t], fun) do
    reduce(t, h, fun)
  end

  def reduce([], _fun) do
    raise Enum.EmptyError
  end

  def reduce(enumerable, fun) do
    Result.reduce(enumerable, fun)
    |> Result.transform()
  end

  def reduce(enumerable, acc, fun) do
    Result.reduce(enumerable, acc, fun)
  end

  def reduce_while(enumerable, acc, fun) do
    Result.reduce_while(enumerable, acc, fun)
  end

  def reject(enumerable, fun) do
    Result.map_then_reduce_ok(enumerable, fun, [], fn elem, mapped, acc ->
      if mapped, do: acc, else: [elem | acc]
    end)
    |> Result.transform(&:lists.reverse/1)
  end

  def scan(enumerable, fun) do
    Result.reduce(enumerable, [], fn
      entry, [] ->
        {:ok, [entry]}

      entry, [prev_entry | _] = acc ->
        fun.(entry, prev_entry)
        |> Result.transform(&[&1 | acc])
    end)
    |> Result.transform(&:lists.reverse/1)
  end

  def scan(enumerable, acc, fun) do
    Result.reduce(enumerable, {:empty, acc}, fn
      entry, {:empty, acc} ->
        fun.(entry, acc)
        |> Result.transform(&[&1])

      entry, [prev_entry | _] = acc ->
        fun.(entry, prev_entry)
        |> Result.transform(&[&1 | acc])
    end)
    |> Result.transform(fn
      {:empty, _} -> []
      list -> :lists.reverse(list)
    end)
  end

  def sort(enumerable, sorter) when is_function(sorter, 2) do
    Result.reduce(enumerable, [], &sort_reducer(&1, &2, sorter))
    |> Result.then(&sort_terminator(&1, sorter))
  end

  defp to_sort_fun(sorter) when is_function(sorter, 2), do: sorter
  defp to_sort_fun(:asc), do: &{:ok, &1 <= &2}
  defp to_sort_fun(:desc), do: &{:ok, &1 >= &2}
  defp to_sort_fun(module) when is_atom(module), do: &{:ok, module.compare(&1, &2) != :gt}
  defp to_sort_fun({:asc, module}) when is_atom(module), do: &{:ok, module.compare(&1, &2) != :gt}

  defp to_sort_fun({:desc, module}) when is_atom(module),
    do: &{:ok, module.compare(&1, &2) != :lt}

  def sort_by(enumerable, mapper, sorter \\ :asc)

  def sort_by(enumerable, mapper, :desc) when is_function(mapper, 1) do
    enumerable
    |> Result.map_then_reduce_ok(mapper, [], &[{&1, &2} | &3])
    |> Result.transform(fn list ->
      list
      |> List.keysort(1, :asc)
      |> List.foldl([], &[elem(&1, 0) | &2])
    end)
  end

  def sort_by(enumerable, mapper, sorter) when is_function(mapper, 1) do
    fun = to_sort_fun(sorter)

    enumerable
    |> Result.map(mapper, &{&1, &2})
    |> Result.then(fn list ->
      list
      |> sort(fn {_left_elem, left_mapped}, {_right_elem, right_mapped} ->
        fun.(left_mapped, right_mapped)
      end)
      |> Result.transform(fn list -> Enum.map(list, &elem(&1, 0)) end)
    end)
  end

  def split_while(enumerable, fun) do
    Result.map_then_reduce_ok(enumerable, fun, {[], []}, fn
      entry, mapped, {acc1, []} ->
        if mapped, do: {[entry | acc1], []}, else: {acc1, [entry]}

      entry, _mapped, {acc1, acc2} ->
        {:ok, {acc1, [entry | acc2]}}
    end)
    |> Result.transform(fn
      {list1, list2} -> {:lists.reverse(list1), :lists.reverse(list2)}
    end)
  end

  def split_with(enumerable, fun) do
    Result.map_then_reduce_ok(enumerable, fun, {[], []}, fn entry, mapped, {acc1, acc2} ->
      if mapped do
        {[entry | acc1], acc2}
      else
        {acc1, [entry | acc2]}
      end
    end)
    |> Result.transform(fn
      {acc1, acc2} -> {:lists.reverse(acc1), :lists.reverse(acc2)}
    end)
  end

  def take_while(enumerable, fun) do
    Result.map_then_reduce_ok_while(enumerable, fun, [], fn entry, mapped, acc ->
      if mapped, do: {:cont, [entry | acc]}, else: {:halt, acc}
    end)
    |> Result.transform(&:lists.reverse/1)
  end

  @doc false
  @deprecated "Use Enum.uniq_by/2 instead"
  def uniq(enumerable, fun) do
    uniq_by(enumerable, fun)
  end

  def uniq_by(enumerable, fun) do
    Result.map_then_reduce_ok(enumerable, fun, {[], %{}}, fn entry, mapped, {list, prev} ->
      if Map.has_key?(prev, mapped) do
        {list, prev}
      else
        {[entry | list], Map.put(prev, mapped, true)}
      end
    end)
    |> Result.transform(fn
      {list, _} -> :lists.reverse(list)
    end)
  end

  def with_index(enumerable, fun_or_offset \\ 0)

  def with_index(enumerable, offset) when is_integer(offset) do
    {:ok, Enum.with_index(enumerable, offset)}
  end

  def with_index(enumerable, fun) when is_function(fun, 2) do
    Result.reduce(enumerable, {[], 0}, fn entry, {acc, index} ->
      fun.(entry, index)
      |> Result.transform(fn
        mapped -> {[mapped | acc], index + 1}
      end)
    end)
    |> Result.transform(fn
      {list, _} -> :lists.reverse(list)
    end)
  end

  def zip_with(enumerable1, enumerable2, zip_fun) when is_function(zip_fun, 2) do
    zip_with([enumerable1, enumerable2], fn [elem1, elem2] -> zip_fun.(elem1, elem2) end)
  end

  def zip_with(enumerables, zip_fun) do
    Stream.zip(enumerables)
    |> Result.map(fn elems -> elems |> Tuple.to_list() |> zip_fun.() end)
  end

  def zip_reduce(left, right, acc, reducer) when is_function(reducer, 3) do
    zip_reduce([left, right], acc, fn [elem1, elem2], acc -> reducer.(elem1, elem2, acc) end)
  end

  def zip_reduce(enums, acc, reducer) when is_function(reducer, 2) do
    Stream.zip(enums)
    |> Result.reduce(acc, fn elems, acc -> elems |> Tuple.to_list() |> reducer.(acc) end)
  end

  ## Helpers

  @compile {:inline, entry_to_string: 1}

  defp entry_to_string(entry) when is_binary(entry), do: entry
  defp entry_to_string(entry), do: String.Chars.to_string(entry)

  ## sort

  defp sort_reducer(entry, {:split, y, x, r, rs, bool}, fun) do
    fun.(y, entry)
    |> Result.then(fn
      ^bool ->
        {:ok, {:split, entry, y, [x | r], rs, bool}}

      _other ->
        fun.(x, entry)
        |> Result.transform(fn
          ^bool ->
            {:split, y, entry, [x | r], rs, bool}

          _other ->
            case r do
              [] -> {:split, y, x, [entry], rs, bool}
              _other -> {:pivot, y, x, r, rs, entry, bool}
            end
        end)
    end)
  end

  defp sort_reducer(entry, {:pivot, y, x, r, rs, s, bool}, fun) do
    fun.(y, entry)
    |> Result.then(fn
      ^bool ->
        {:ok, {:pivot, entry, y, [x | r], rs, s, bool}}

      _other ->
        fun.(x, entry)
        |> Result.then(fn
          ^bool ->
            {:ok, {:pivot, y, entry, [x | r], rs, s, bool}}

          _other ->
            fun.(s, entry)
            |> Result.transform(fn
              ^bool ->
                {:split, entry, s, [], [[y, x | r] | rs], bool}

              _other ->
                {:split, s, entry, [], [[y, x | r] | rs], bool}
            end)
        end)
    end)
  end

  defp sort_reducer(entry, [x], fun) do
    fun.(x, entry)
    |> Result.transform(&{:split, entry, x, [], [], &1})
  end

  defp sort_reducer(entry, acc, _fun) do
    {:ok, [entry | acc]}
  end

  defp sort_terminator({:split, y, x, r, rs, bool}, fun) do
    sort_merge([[y, x | r] | rs], fun, bool)
  end

  defp sort_terminator({:pivot, y, x, r, rs, s, bool}, fun) do
    sort_merge([[s], [y, x | r] | rs], fun, bool)
  end

  defp sort_terminator(acc, _fun) do
    {:ok, acc}
  end

  defp sort_merge(list, fun, true), do: reverse_sort_merge(list, [], fun, true)

  defp sort_merge(list, fun, false), do: sort_merge(list, [], fun, false)

  defp sort_merge([t1, [h2 | t2] | l], acc, fun, true) do
    sort_merge1(t1, h2, t2, [], fun, false)
    |> Result.then(fn mapped ->
      sort_merge(l, [mapped | acc], fun, true)
    end)
  end

  defp sort_merge([[h2 | t2], t1 | l], acc, fun, false) do
    sort_merge1(t1, h2, t2, [], fun, false)
    |> Result.then(fn mapped ->
      sort_merge(l, [mapped | acc], fun, false)
    end)
  end

  defp sort_merge([l], [], _fun, _bool), do: {:ok, l}

  defp sort_merge([l], acc, fun, bool),
    do: reverse_sort_merge([:lists.reverse(l, []) | acc], [], fun, bool)

  defp sort_merge([], acc, fun, bool), do: reverse_sort_merge(acc, [], fun, bool)

  defp reverse_sort_merge([[h2 | t2], t1 | l], acc, fun, true) do
    sort_merge1(t1, h2, t2, [], fun, true)
    |> Result.then(fn mapped ->
      reverse_sort_merge(l, [mapped | acc], fun, true)
    end)
  end

  defp reverse_sort_merge([t1, [h2 | t2] | l], acc, fun, false) do
    sort_merge1(t1, h2, t2, [], fun, true)
    |> Result.then(fn mapped ->
      reverse_sort_merge(l, [mapped | acc], fun, false)
    end)
  end

  defp reverse_sort_merge([l], acc, fun, bool),
    do: sort_merge([:lists.reverse(l, []) | acc], [], fun, bool)

  defp reverse_sort_merge([], acc, fun, bool), do: sort_merge(acc, [], fun, bool)

  defp sort_merge1([h1 | t1], h2, t2, m, fun, bool) do
    fun.(h1, h2)
    |> Result.then(fn
      ^bool -> sort_merge2(h1, t1, t2, [h2 | m], fun, bool)
      _other -> sort_merge1(t1, h2, t2, [h1 | m], fun, bool)
    end)
  end

  defp sort_merge1([], h2, t2, m, _fun, _bool), do: {:ok, :lists.reverse(t2, [h2 | m])}

  defp sort_merge2(h1, t1, [h2 | t2], m, fun, bool) do
    fun.(h1, h2)
    |> Result.then(fn
      ^bool -> sort_merge2(h1, t1, t2, [h2 | m], fun, bool)
      _other -> sort_merge1(t1, h2, t2, [h1 | m], fun, bool)
    end)
  end

  defp sort_merge2(h1, t1, [], m, _fun, _bool), do: {:ok, :lists.reverse(t1, [h1 | m])}
end
