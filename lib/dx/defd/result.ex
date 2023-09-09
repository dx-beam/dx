defmodule Dx.Defd.Result do
  # Shorthand to conveniently declare optional functions as `fun \\ &identity/1`.
  defp identity(term), do: term

  @doc """
  Wraps a value in an `:ok` result.
  """
  def ok(value), do: {:ok, value}

  @doc """
  When given `{:ok, value}`, runs `fun` on `value` and returns the result.
  Otherwise, returns first argument as is.
  """
  def then({:ok, result}, fun), do: fun.(result)
  def then(other, _fun), do: other

  @doc """
  When given `{:ok, value}`, runs `fun` on `value` and returns `{:ok, new_value}`.
  Otherwise, returns first argument as is.
  """

  # transform/1
  def transform(:empty), do: raise(Enum.EmptyError)
  def transform(other), do: other

  # transform/2 with empty_fallback
  def transform({:ok, result}, empty_fallback) when is_function(empty_fallback, 0),
    do: {:ok, result}

  def transform(:empty, empty_fallback) when is_function(empty_fallback, 0), do: empty_fallback.()
  def transform(other, empty_fallback) when is_function(empty_fallback, 0), do: other

  # transform/2 with fun
  def transform({:ok, result}, fun), do: {:ok, fun.(result)}
  def transform(:empty, _fun), do: raise(Enum.EmptyError)
  def transform(other, _fun), do: other

  # transform_while/2 with fun
  def transform_while({:ok, result}, fun), do: {:ok, fun.(result)}
  def transform_while(other, _fun), do: other

  # transform/3
  def transform({:ok, result}, _empty_fallback, fun), do: {:ok, fun.(result)}

  def transform(:empty, empty_fallback, _fun) when is_function(empty_fallback, 0),
    do: empty_fallback.()

  def transform(:empty, empty_fallback, _fun), do: empty_fallback
  def transform(other, _empty_fallback, _fun), do: other

  @doc """
  Returns `{:ok, mapped_results}` if all elements map to `{:ok, result}`.
  Otherwise, returns `{:error, e}` on error, or `{:not_loaded, data_reqs}` with all data requirements.

  ## Examples

      iex> [
      ...>   {:ok, 1},
      ...>   {:ok, 2},
      ...>   {:ok, 3},
      ...> ]
      ...> |> Dx.Defd.Result.map()
      {:ok, [1, 2, 3]}

      iex> [
      ...>   {:ok, 1},
      ...>   {:not_loaded, [:x]},
      ...>   {:ok, 3},
      ...>   {:not_loaded, [:y]},
      ...> ]
      ...> |> Dx.Defd.Result.map()
      {:not_loaded, [:x, :y]}

      iex> [
      ...>   {:ok, 1},
      ...>   {:error, :x},
      ...>   {:ok, 3},
      ...>   {:not_loaded, [:y]},
      ...> ]
      ...> |> Dx.Defd.Result.map()
      {:error, :x}
  """
  def map(enum, mapper \\ &identity/1) do
    Enum.reduce_while(enum, ok([]), fn elem, acc ->
      combine(:all, acc, mapper.(elem), & &1)
    end)
    |> transform(&Enum.reverse/1)
  end

  def map(enum, mapper, result_mapper) when is_function(result_mapper, 2) do
    Enum.reduce_while(enum, ok([]), fn elem, acc ->
      combine(:all, acc, mapper.(elem), &result_mapper.(elem, &1))
    end)
    |> transform(&Enum.reverse/1)
  end

  @doc """
  Applies the `mapper` function to each element and reduces the mapped results
  using `acc` and `fun` as long as the mapped results are `{:ok, _}` tuples.
  Returns `{:ok, reduced_acc}` if all elements map to `{:ok, result}`.
  Otherwise, returns `{:error, e}` on error, or `{:not_loaded, data_reqs}` with all data requirements.

  ## Examples

      iex> [
      ...>   {:ok, 1},
      ...>   {:ok, 2},
      ...>   {:ok, 3},
      ...> ]
      ...> |> Dx.Defd.Result.map_then_reduce_ok(& &1, [], &[&1 | &2])
      {:ok, [3, 2, 1]}

      iex> [
      ...>   {:ok, 1},
      ...>   {:not_loaded, [:x]},
      ...>   {:ok, 3},
      ...>   {:not_loaded, [:y]},
      ...> ]
      ...> |> Dx.Defd.Result.map_then_reduce_ok(& &1, [], &[&1 | &2])
      {:not_loaded, [:x, :y]}

      iex> [
      ...>   {:ok, 1},
      ...>   {:error, :x},
      ...>   {:ok, 3},
      ...>   {:not_loaded, [:y]},
      ...> ]
      ...> |> Dx.Defd.Result.map_then_reduce_ok(& &1, [], &[&1 | &2])
      {:error, :x}
  """
  def map_then_reduce_ok(enum, mapper, acc, fun) when is_function(fun, 2) do
    Enum.reduce_while(enum, ok(acc), fn elem, acc ->
      combine(:map_then_reduce_ok, acc, mapper.(elem), fun)
    end)
  end

  def map_then_reduce_ok(enum, mapper, acc, fun) when is_function(fun, 3) do
    Enum.reduce_while(enum, ok(acc), fn elem, acc ->
      combine(:map_then_reduce_ok, acc, mapper.(elem), &fun.(elem, &1, &2))
    end)
  end

  def map_then_reduce(enum, mapper, fun) when is_function(fun, 2) do
    Enum.reduce_while(enum, :empty, fn
      elem, :empty -> {:cont, mapper.(elem)}
      elem, acc -> combine(:map_then_reduce, acc, mapper.(elem), fun)
    end)
  end

  def map_then_reduce(enum, mapper, first_fun, fun)
      when is_function(first_fun) and is_function(fun, 3) do
    Enum.reduce_while(enum, :empty, fn
      elem, :empty -> {:cont, first_fun.(elem)}
      elem, acc -> combine(:map_then_reduce, acc, mapper.(elem), &fun.(elem, &1, &2))
    end)
  end

  def map_then_reduce(enum, mapper, acc, fun) when is_function(fun, 2) do
    Enum.reduce_while(enum, ok(acc), fn elem, acc ->
      combine(:map_then_reduce, acc, mapper.(elem), fun)
    end)
  end

  def map_then_reduce(enum, mapper, acc, fun) when is_function(fun, 3) do
    Enum.reduce_while(enum, ok(acc), fn elem, acc ->
      combine(:map_then_reduce, acc, mapper.(elem), &fun.(elem, &1, &2))
    end)
  end

  def map_then_reduce_ok_while(enum, mapper, acc, fun) when is_function(fun, 2) do
    Enum.reduce_while(enum, ok(acc), fn elem, acc ->
      combine(:map_then_reduce_ok_while, acc, mapper.(elem), fun)
    end)
  end

  def map_then_reduce_ok_while(enum, mapper, acc, fun) when is_function(fun, 3) do
    Enum.reduce_while(enum, ok(acc), fn elem, acc ->
      combine(:map_then_reduce_ok_while, acc, mapper.(elem), &fun.(elem, &1, &2))
    end)
  end

  def reduce(enum, fun) do
    Enum.reduce_while(enum, :empty, fn
      elem, :empty ->
        {:cont, {:ok, elem}}

      elem, {:ok, acc} ->
        case fun.(elem, acc) do
          {:ok, new_acc} -> {:cont, {:ok, new_acc}}
          other -> {:halt, other}
        end
    end)
  end

  def reduce(enum, acc, fun) do
    Enum.reduce_while(enum, {:ok, acc}, fn elem, {:ok, acc} ->
      combine(:reduce, acc, fun.(elem, acc))
    end)
  end

  def reduce_while(enum, acc, fun) do
    Enum.reduce_while(enum, {:ok, acc}, fn elem, {:ok, acc} ->
      combine(:reduce_while, acc, fun.(elem, acc))
    end)
  end

  @doc """
  Returns `{:ok, true}` if `fun` evaluates to `{:ok, true}` for all elements in `enum`.
  Otherwise, returns `{:not_loaded, data_reqs}` if any yield that.
  Otherwise, returns `{:ok, false}`.

  ## Examples

      iex> [
      ...>   {:ok, true},
      ...>   {:not_loaded, []},
      ...>   {:ok, false},
      ...> ]
      ...> |> Dx.Defd.Result.all?()
      {:ok, false}

      iex> [
      ...>   {:ok, true},
      ...>   {:not_loaded, []},
      ...>   {:ok, true},
      ...> ]
      ...> |> Dx.Defd.Result.all?()
      {:not_loaded, []}

      iex> [
      ...>   {:ok, true},
      ...>   {:ok, true},
      ...> ]
      ...> |> Dx.Defd.Result.all?()
      {:ok, true}
  """
  def all?(enum, mapper \\ &identity/1) do
    Enum.reduce_while(enum, ok(true), fn elem, acc ->
      combine(:all?, acc, mapper.(elem))
    end)
  end

  @doc """
  Returns `{:ok, true}` if `fun` evaluates to `{:ok, true}` for any element in `enum`.
  Otherwise, returns `{:not_loaded, data_reqs}` if any yields that.
  Otherwise, returns `{:ok, false}`.

  ## Examples

      iex> [
      ...>   {:ok, true},
      ...>   {:not_loaded, []},
      ...>   {:ok, false},
      ...> ]
      ...> |> Dx.Defd.Result.any?()
      {:ok, true}

      iex> [
      ...>   {:ok, false},
      ...>   {:not_loaded, []},
      ...>   {:ok, false},
      ...> ]
      ...> |> Dx.Defd.Result.any?()
      {:not_loaded, []}

      iex> [
      ...>   {:ok, false},
      ...>   {:ok, false},
      ...> ]
      ...> |> Dx.Defd.Result.any?()
      {:ok, false}
  """
  def any?(enum, mapper \\ &identity/1) do
    Enum.reduce_while(enum, ok(false), fn elem, acc ->
      combine(:any?, acc, mapper.(elem))
    end)
  end

  @doc """
  Returns `{:ok, elem}` for the first `elem` for which `fun` evaluates to `{:ok, true}`.
  If any elements before that return `{:not_loaded, data_reqs}`, returns all of them combined as `{:not_loaded, ...}`.
  Otherwise, returns `{:ok, default}`.

  ## Examples

      iex> [
      ...>   {:ok, true},
      ...>   {:not_loaded, []},
      ...>   {:ok, false},
      ...> ]
      ...> |> Dx.Defd.Result.find()
      {:ok, {:ok, true}}

      iex> [
      ...>   {:ok, false},
      ...>   {:not_loaded, [1]},
      ...>   {:not_loaded, [2]},
      ...>   {:ok, true},
      ...>   {:not_loaded, [3]},
      ...> ]
      ...> |> Dx.Defd.Result.find()
      {:not_loaded, [1, 2]}

      iex> [
      ...>   {:ok, false},
      ...>   {:ok, false},
      ...> ]
      ...> |> Dx.Defd.Result.find()
      {:ok, nil}

      iex> [
      ...>   false,
      ...>   false,
      ...> ]
      ...> |> Dx.Defd.Result.find(&{:ok, not &1})
      {:ok, false}
  """
  def find(enum, fun \\ &identity/1, result_mapper \\ &ok/1, default \\ ok(nil)) do
    Enum.reduce_while(enum, default, fn elem, acc ->
      combine(:find, acc, fun.(elem), fn -> result_mapper.(elem) end)
    end)
  end

  def find_value(enum, fun, default \\ ok(nil)) do
    Enum.reduce_while(enum, default, fn elem, acc ->
      mapped = fun.(elem)
      combine(:find, acc, mapped, fn -> mapped end)
    end)
  end

  @doc """
  Returns `{:ok, mapped_results}` if all elements map to `{:ok, result}`.
  Otherwise, returns `{:error, e}` on error, or `{:not_loaded, data_reqs}` with all data requirements.

  ## Examples

      iex> [
      ...>   {:ok, 1},
      ...>   {:ok, 2},
      ...>   {:ok, 3},
      ...> ]
      ...> |> Dx.Defd.Result.collect_reverse()
      {:ok, [3, 2, 1]}

      iex> [
      ...>   {:ok, 1},
      ...>   {:not_loaded, [:x]},
      ...>   {:ok, 3},
      ...>   {:not_loaded, [:y]},
      ...> ]
      ...> |> Dx.Defd.Result.collect_reverse()
      {:not_loaded, [:y, :x]}

      iex> [
      ...>   {:ok, 1},
      ...>   {:error, :x},
      ...>   {:ok, 3},
      ...>   {:not_loaded, [:y]},
      ...> ]
      ...> |> Dx.Defd.Result.collect_reverse()
      {:error, :x}
  """
  def collect_reverse(list, acc \\ {:ok, []})

  def collect_reverse([], acc) do
    acc
  end

  def collect_reverse([{:error, e} | _tail], _acc) do
    {:error, e}
  end

  def collect_reverse([{:not_loaded, r1} | tail], {:not_loaded, r2}) do
    acc = {:not_loaded, Dx.Util.deep_merge(r1, r2)}
    collect_reverse(tail, acc)
  end

  def collect_reverse([{:not_loaded, _reqs} = reqs | tail], _acc) do
    collect_reverse(tail, reqs)
  end

  def collect_reverse([{:ok, result} | tail], {:ok, results}) do
    acc = {:ok, [result | results]}
    collect_reverse(tail, acc)
  end

  def collect_reverse([{:ok, _result} | tail], acc) do
    collect_reverse(tail, acc)
  end

  def collect(results) do
    collect_reverse(results, {:ok, []})
    |> transform(&Enum.reverse/1)
  end

  def collect_map_pairs(flat_pairs) do
    flat_pairs
    |> collect()
    |> transform(&Enum.chunk_every(&1, 2))
    |> transform(fn pairs -> Map.new(pairs, fn [k, v] -> {k, v} end) end)
  end

  def collect_ok(results) do
    collect_ok_reverse(results, [])
    |> transform(&Enum.reverse/1)
  end

  def collect_ok_reverse([], acc) do
    {:ok, acc}
  end

  def collect_ok_reverse([{:ok, result} | tail], acc) do
    collect_ok_reverse(tail, [result | acc])
  end

  def collect_ok_reverse([_ | _tail], _acc) do
    :error
  end

  def merge(_acc, {:error, e}), do: {:halt, {:error, e}}

  def merge({:not_loaded, r1}, {:not_loaded, r2}),
    do: {:cont, {:not_loaded, Dx.Util.deep_merge(r1, r2)}}

  def merge(_acc, {:not_loaded, reqs}), do: {:cont, {:not_loaded, reqs}}

  def merge({:not_loaded, reqs}, {:ok, _}), do: {:cont, {:not_loaded, reqs}}

  def merge({:ok, results}, {:ok, result}),
    do: {:cont, {:ok, Dx.Util.deep_merge(results, result)}}

  def combine(elem, acc) do
    combine(:all, acc, elem, & &1)
  end

  defp combine(mode, acc, elem, extra \\ nil)

  defp combine(_mode, _acc, {:error, e}, _), do: {:halt, {:error, e}}

  defp combine(_mode, {:not_loaded, r1}, {:not_loaded, r2}, _),
    do: {:cont, {:not_loaded, Dx.Util.deep_merge(r1, r2)}}

  # handle :not_loaded
  defp combine(:reduce, _acc, {:not_loaded, reqs}, _), do: {:halt, {:not_loaded, reqs}}
  defp combine(:reduce_while, _acc, {:not_loaded, reqs}, _), do: {:halt, {:not_loaded, reqs}}
  defp combine(_mode, _acc, {:not_loaded, reqs}, _), do: {:cont, {:not_loaded, reqs}}

  # :map_then_reduce_ok
  defp combine(:map_then_reduce_ok, {:not_loaded, reqs}, {:ok, _}, _),
    do: {:cont, {:not_loaded, reqs}}

  defp combine(:map_then_reduce_ok, {:ok, results}, {:ok, result}, fun),
    do: {:cont, {:ok, fun.(result, results)}}

  # :map_then_reduce
  defp combine(:map_then_reduce, {:not_loaded, reqs}, {:ok, _}, _),
    do: {:cont, {:not_loaded, reqs}}

  defp combine(:map_then_reduce, {:ok, results}, {:ok, result}, fun) do
    case fun.(result, results) do
      {:error, _} = e -> {:halt, e}
      other -> {:cont, other}
    end
  end

  # :map_then_reduce_ok_while
  defp combine(:map_then_reduce_ok_while, {:not_loaded, reqs}, {:ok, _}, _),
    do: {:cont, {:not_loaded, reqs}}

  defp combine(:map_then_reduce_ok_while, {:ok, results}, {:ok, result}, fun) do
    case fun.(result, results) do
      {control, result} ->
        {control, {:ok, result}}

      other ->
        raise ArgumentError, """
        The `fun` passed to Dx.Enum.Result.map_then_reduce_ok_while/4 must return either
        `{:cont, result}` or `{:halt, result}` but instead returned:

        #{inspect(other, pretty: true, limit: 10)}
        """
    end
  end

  # :reduce
  defp combine(:reduce, _results, {:ok, result}, _), do: {:cont, {:ok, result}}

  # :reduce_while
  defp combine(:reduce_while, _results, {:ok, {control, result}}, _) do
    {control, {:ok, result}}
  end

  # :all
  defp combine(:all, {:not_loaded, reqs}, {:ok, _}, _), do: {:cont, {:not_loaded, reqs}}

  defp combine(:all, {:ok, results}, {:ok, result}, fun),
    do: {:cont, {:ok, [fun.(result) | results]}}

  # :any?
  defp combine(:any?, _acc, {:ok, true}, _), do: {:halt, {:ok, true}}
  defp combine(:any?, acc, {:ok, false}, _), do: {:cont, acc}

  # :all?
  defp combine(:all?, _acc, {:ok, false}, _), do: {:halt, {:ok, false}}

  defp combine(:all?, {:not_loaded, reqs}, {:ok, true}, _),
    do: {:cont, {:not_loaded, reqs}}

  defp combine(:all?, {:ok, true}, {:ok, true}, _),
    do: {:cont, {:ok, true}}

  # :find
  defp combine(:find, acc, {:ok, false}, _), do: {:cont, acc}
  defp combine(:find, {:not_loaded, reqs}, {:ok, true}, _), do: {:halt, {:not_loaded, reqs}}
  defp combine(:find, {:ok, _}, {:ok, true}, mapper), do: {:halt, mapper.()}
end
