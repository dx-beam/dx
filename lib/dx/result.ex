defmodule Dx.Result do
  @moduledoc """
  Result types and helpers to work with them.

  A result is either:

    - `{:error, e}` if an error occurred
    - `{:not_loaded, data_reqs}` if the result could not be determined without loading more data
    - `{:ok, boolean, binds}` otherwise, in contexts where a boolean is expected (type `t:b()`)
    - `{:ok, result, binds}` otherwise, where `result` can be any value (type `t:v()`)

  ## Data loading

  In general, `{:not_loaded, all_reqs}` only ever returns data requirements that are really needed.

  ### Example using `all`

  For example, using `all?/1` with 3 conditions A, B and C, where

      iex> [
      ...>   {:ok, true, %{}},   # A
      ...>   {:not_loaded, [1]}, # B
      ...>   {:ok, false, %{}},  # C
      ...> ]
      ...> |> Dx.Result.all?()
      {:ok, false, %{}}

  The overall result is `{:ok, false, %{}}`.
  While B would need more data to be loaded, C can already determined and is `false`,
  so and any additional data loaded will not change that.

  ### Example using `find`

  Another example, using `find/1` with 5 conditions A, B, C, D and E, where

      iex> [
      ...>   {:ok, false, %{}},  # A
      ...>   {:not_loaded, [1]}, # B
      ...>   {:not_loaded, [2]}, # C
      ...>   {:ok, true, %{}},   # D
      ...>   {:not_loaded, [3]}, # E
      ...> ]
      ...> |> Dx.Result.find()
      {:not_loaded, [1, 2]}

  The overall result is `{:not_loaded, data_reqs1 + data_reqs2}`.
  While D can already be determined and is `{:ok, true, %{}}`, B and C come first and need more data
  to be loaded, so they can be determined and returned if either is `{:ok, true, %{}}` first.
  All data requirements that might be needed are returned together in the result (those of B and C),
  while those of E can be ruled out, as D already returns `{:ok, true, %{}}` and comes first.
  """

  alias Dx.Util

  @typedoc """
  Possible return values from resolving predicates.
  """
  @type v() :: {:ok, any(), binds()} | {:not_loaded, any()} | {:error, any()}

  @typedoc """
  Possible return values from conditions.
  """
  @type b() :: {:ok, boolean(), binds()} | {:not_loaded, any()} | {:error, any()}

  @type binds() :: %{atom() => any()}

  # Shorthand to conveniently declare optional functions as `fun \\ &identity/1`.
  defp identity(term), do: term

  @doc """
  Wraps a value in an `:ok` result.
  """
  def ok(value, binds \\ %{}), do: {:ok, value, binds}

  @doc """
  Wraps a value in a compatible tuple for use with this module, if it's not wrapped already.
  """
  def wrap({:not_loaded, data_reqs}), do: {:not_loaded, data_reqs}
  def wrap({:error, e}), do: {:error, e}
  def wrap({:ok, term, binds}) when is_map(binds), do: {:ok, term, binds}
  def wrap(term), do: {:ok, term, %{}}

  @doc """
  If ok, binds the result to the given key and returns the updated tuple.
  Otherwise, returns first argument as is.
  """
  def bind({:ok, result, binds}, key, val), do: {:ok, result, Map.put(binds, key, val)}
  def bind(other, _key, _val), do: other

  @doc """
  When given `{:ok, value, binds}`, runs `fun` on `value` and returns the result.
  Otherwise, returns first argument as is.
  """
  def then({:ok, result, binds}, fun) do
    case fun.(result) do
      {:ok, result, new_binds} -> {:ok, result, Map.merge(new_binds, binds)}
      other -> other
    end
  end

  def then(other, _fun), do: other

  @doc """
  When given `{:ok, value, binds}`, runs `fun` on `value` and returns `{:ok, new_value, binds}`.
  Otherwise, returns first argument as is.
  """
  def transform({:ok, result, binds}, fun), do: {:ok, fun.(result), binds}
  def transform(other, _fun), do: other

  @doc """
  Converts the internal 3-tuple result format (type `t:v()` or `t:b()`) to a 2-tuple format.

  ## Examples

      iex> {:ok, 5, %{}}
      ...> |>Dx.Result.to_simple()
      {:ok, 5}

      iex> {:error, :err}
      ...> |>Dx.Result.to_simple()
      {:error, :err}
  """
  def to_simple({:ok, result, _binds}), do: {:ok, result}
  def to_simple(other), do: other

  def to_simple_if({:ok, result, _binds}, true), do: {:ok, result}
  def to_simple_if(other, _), do: other

  @doc """
  Converts 2-tuples to the internal 3-tuple result format (type `t:v()` or `t:b()`).

  ## Examples

      iex> {:ok, 5}
      ...> |>Dx.Result.from_simple()
      {:ok, 5, %{}}

      iex> {:error, :err}
      ...> |>Dx.Result.from_simple()
      {:error, :err}
  """
  def from_simple({:ok, result}), do: ok(result)
  def from_simple(other), do: other

  @doc """
  When given `{:ok, value, binds}` or `{:ok, value}`, returns `value`.
  Otherwise, raises an exception.
  """
  def unwrap!({:ok, result}), do: result
  def unwrap!({:ok, result, _binds}), do: result
  def unwrap!({:not_loaded, _data_reqs}), do: raise(Dx.Error.NotLoaded)
  def unwrap!({:error, {e, stacktrace}}), do: reraise(e, stacktrace)
  def unwrap!({:error, e}), do: raise(e)

  @doc """
  Returns `{:ok, true}` if `fun` evaluates to `{:ok, true}` for all elements in `enum`.
  Otherwise, returns `{:not_loaded, data_reqs}` if any yield that.
  Otherwise, returns `{:ok, false}`.

  ## Examples

      iex> [
      ...>   {:ok, true, %{}},
      ...>   {:not_loaded, []},
      ...>   {:ok, false, %{}},
      ...> ]
      ...> |> Dx.Result.all?()
      {:ok, false, %{}}

      iex> [
      ...>   {:ok, true, %{}},
      ...>   {:not_loaded, []},
      ...>   {:ok, true, %{}},
      ...> ]
      ...> |> Dx.Result.all?()
      {:not_loaded, []}

      iex> [
      ...>   {:ok, true, %{}},
      ...>   {:ok, true, %{}},
      ...> ]
      ...> |> Dx.Result.all?()
      {:ok, true, %{}}
  """
  @spec all?(Enum.t(), (any() -> b())) :: b()
  def all?(enum, mapper \\ &identity/1) do
    Enum.reduce_while(enum, ok(true), fn elem, acc ->
      combine(:all?, acc, mapper.(elem))
    end)
  end

  @doc """
  Returns `{:ok, true, binds}` if `fun` evaluates to `{:ok, true, binds}` for any element in `enum`.
  Otherwise, returns `{:not_loaded, data_reqs}` if any yields that.
  Otherwise, returns `{:ok, false, %{}}`.

  ## Examples

      iex> [
      ...>   {:ok, true, %{a: 1}},
      ...>   {:not_loaded, []},
      ...>   {:ok, false, %{}},
      ...> ]
      ...> |> Dx.Result.any?()
      {:ok, true, %{a: 1}}

      iex> [
      ...>   {:ok, false, %{}},
      ...>   {:not_loaded, []},
      ...>   {:ok, false, %{}},
      ...> ]
      ...> |> Dx.Result.any?()
      {:not_loaded, []}

      iex> [
      ...>   {:ok, false, %{}},
      ...>   {:ok, false, %{}},
      ...> ]
      ...> |> Dx.Result.any?()
      {:ok, false, %{}}
  """
  @spec any?(Enum.t(), (any() -> b())) :: b()
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
      ...>   {:ok, true, %{}},
      ...>   {:not_loaded, []},
      ...>   {:ok, false, %{}},
      ...> ]
      ...> |> Dx.Result.find()
      {:ok, {:ok, true, %{}}, %{}}

      iex> [
      ...>   {:ok, false, %{}},
      ...>   {:not_loaded, [1]},
      ...>   {:not_loaded, [2]},
      ...>   {:ok, true, %{}},
      ...>   {:not_loaded, [3]},
      ...> ]
      ...> |> Dx.Result.find()
      {:not_loaded, [1, 2]}

      iex> [
      ...>   {:ok, false, %{}},
      ...>   {:ok, false, %{}},
      ...> ]
      ...> |> Dx.Result.find()
      {:ok, nil, %{}}

      iex> [
      ...>   false,
      ...>   false,
      ...> ]
      ...> |> Dx.Result.find(&{:ok, not &1, %{}})
      {:ok, false, %{}}
  """
  @spec find(Enum.t(), (any() -> b()), (any() -> any()), any()) :: v()
  def find(enum, fun \\ &identity/1, result_mapper \\ &ok/2, default \\ ok(nil)) do
    Enum.reduce_while(enum, default, fn elem, acc ->
      combine(:find, acc, fun.(elem), &result_mapper.(elem, &1))
    end)
  end

  @doc """
  Returns `{:ok, mapped_results, binds}` if all elements map to `{:ok, result, binds}`.
  Otherwise, returns `{:error, e}` on error, or `{:not_loaded, data_reqs}` with all data requirements.

  ## Examples

      iex> [
      ...>   {:ok, 1, %{}},
      ...>   {:ok, 2, %{}},
      ...>   {:ok, 3, %{}},
      ...> ]
      ...> |> Dx.Result.map()
      {:ok, [1, 2, 3], %{}}

      iex> [
      ...>   {:ok, 1, %{}},
      ...>   {:not_loaded, [:x]},
      ...>   {:ok, 3, %{}},
      ...>   {:not_loaded, [:y]},
      ...> ]
      ...> |> Dx.Result.map()
      {:not_loaded, [:x, :y]}

      iex> [
      ...>   {:ok, 1, %{}},
      ...>   {:error, :x},
      ...>   {:ok, 3, %{}},
      ...>   {:not_loaded, [:y]},
      ...> ]
      ...> |> Dx.Result.map()
      {:error, :x}
  """
  @spec map(Enum.t(), (any() -> v())) :: v()
  def map(enum, mapper \\ &identity/1) do
    Enum.reduce_while(enum, ok([]), fn elem, acc ->
      combine(:all, acc, mapper.(elem))
    end)
    |> transform(&Enum.reverse/1)
  end

  def filter_map(enum, fun \\ &identity/1, result_mapper \\ &ok/2) do
    Enum.reduce_while(enum, ok([]), fn elem, acc ->
      combine(:filter, acc, fun.(elem), &result_mapper.(elem, &1))
    end)
    |> transform(&Enum.reverse/1)
  end

  @doc """
  Returns the number of elements before `fun` evaluates to `{:ok, false}` or an element is `nil`.
  Elements are skipped (not counted) whenever `fun` evaluates to `{:ok, :skip}`.
  If any elements before that return `{:not_loaded, data_reqs}`, returns all of them combined as `{:not_loaded, ...}`.
  Otherwise, returns `{:ok, default}`.

  ## Examples

      iex> [
      ...>   {:ok, true, %{}},
      ...>   {:not_loaded, []},
      ...>   {:ok, false, %{}},
      ...> ]
      ...> |> Dx.Result.count_while()
      {:not_loaded, []}

      iex> [
      ...>   {:ok, false, %{}},
      ...>   {:not_loaded, [1]},
      ...>   {:not_loaded, [2]},
      ...>   {:ok, true, %{}},
      ...>   {:not_loaded, [3]},
      ...> ]
      ...> |> Dx.Result.count_while()
      {:ok, 0, %{}}

      iex> [
      ...>   {:ok, true, %{}},
      ...>   {:ok, :skip, %{}},
      ...>   {:ok, false, %{}},
      ...>   {:ok, false, %{}},
      ...> ]
      ...> |> Dx.Result.count_while()
      {:ok, 1, %{}}

      iex> [
      ...>   false,
      ...>   false,
      ...> ]
      ...> |> Dx.Result.count_while(&{:ok, not &1, %{}})
      {:ok, 2, %{}}
  """
  @spec count_while(Enum.t(), (any() -> v())) :: v()
  def count_while(enum, fun \\ &identity/1) do
    Enum.reduce_while(enum, ok(0), fn elem, acc ->
      combine(:count_while, acc, fun.(elem))
    end)
  end

  @doc """
  Returns the number of elements for which `fun` evaluates to `{:ok, true}`.
  If any elements return `{:not_loaded, data_reqs}`, returns all of them combined as `{:not_loaded, ...}`.
  Otherwise, returns `{:ok, default}`.

  ## Examples

      iex> [
      ...>   {:ok, true, %{}},
      ...>   {:ok, false, %{}},
      ...>   {:ok, true, %{}},
      ...> ]
      ...> |> Dx.Result.count()
      {:ok, 2, %{}}

      iex> [
      ...>   {:ok, false, %{}},
      ...>   {:not_loaded, [1]},
      ...>   {:not_loaded, [2]},
      ...>   {:ok, true, %{}},
      ...>   {:not_loaded, [3]},
      ...> ]
      ...> |> Dx.Result.count()
      {:not_loaded, [1, 2, 3]}

      iex> [
      ...>   {:ok, true, %{}},
      ...>   {:ok, :skip, %{}},
      ...>   {:ok, false, %{}},
      ...>   {:ok, false, %{}},
      ...> ]
      ...> |> Dx.Result.count()
      {:ok, 1, %{}}

      iex> [
      ...>   false,
      ...>   false,
      ...> ]
      ...> |> Dx.Result.count(&{:ok, not &1, %{}})
      {:ok, 2, %{}}
  """
  @spec count(Enum.t(), (any() -> v())) :: v()
  def count(enum, fun \\ &identity/1) do
    Enum.reduce_while(enum, ok(0), fn elem, acc ->
      combine(:count, acc, fun.(elem))
    end)
  end

  @doc """
  Returns `{:ok, new_keyword_list, binds}` with new values if all values map to `{:ok, new_value, binds}`.
  Otherwise, returns `{:error, e}` on error, or `{:not_loaded, data_reqs}` with all data requirements.

  ## Examples

      iex> [
      ...>   a: {:ok, 1, %{}},
      ...>   b: {:ok, 2, %{}},
      ...>   c: {:ok, 3, %{}},
      ...> ]
      ...> |> Dx.Result.map_keyword_values()
      {:ok, [a: 1, b: 2, c: 3], %{}}

      iex> [
      ...>   a: {:ok, 1, %{}},
      ...>   b: {:not_loaded, MapSet.new([:x])},
      ...>   c: {:ok, 3, %{}},
      ...>   d: {:not_loaded, MapSet.new([:y])},
      ...> ]
      ...> |> Dx.Result.map_keyword_values()
      {:not_loaded, MapSet.new([:x, :y])}

      iex> [
      ...>   a: {:ok, 1, %{}},
      ...>   b: {:error, :x},
      ...>   c: {:ok, 3, %{}},
      ...>   d: {:not_loaded, [:y]},
      ...> ]
      ...> |> Dx.Result.map_keyword_values()
      {:error, :x}
  """
  def map_keyword_values(enum, mapper \\ &identity/1) do
    Enum.reduce_while(enum, ok([]), fn {key, elem}, acc ->
      combine(:all, acc, mapper.(elem) |> transform(&{key, &1}))
    end)
    |> transform(&Enum.reverse/1)
  end

  @doc """
  Returns `{:ok, new_map, binds}` with new values if all values map to `{:ok, new_value, binds}`.
  Otherwise, returns `{:error, e}` on error, or `{:not_loaded, data_reqs}` with all data requirements.

  ## Examples

      iex> %{
      ...>   a: {:ok, 1, %{}},
      ...>   b: {:ok, 2, %{}},
      ...>   c: {:ok, 3, %{}},
      ...> }
      ...> |> Dx.Result.map_values()
      {:ok, %{a: 1, b: 2, c: 3}, %{}}

      iex> %{
      ...>   a: {:ok, 1, %{}},
      ...>   b: {:not_loaded, MapSet.new([:x])},
      ...>   c: {:ok, 3, %{}},
      ...>   d: {:not_loaded, MapSet.new([:y])},
      ...> }
      ...> |> Dx.Result.map_values()
      {:not_loaded, MapSet.new([:x, :y])}

      iex> %{
      ...>   a: {:ok, 1, %{}},
      ...>   b: {:error, :x},
      ...>   c: {:ok, 3, %{}},
      ...>   d: {:not_loaded, [:y]},
      ...> }
      ...> |> Dx.Result.map_values()
      {:error, :x}
  """
  def map_values(enum, mapper \\ &identity/1) do
    Enum.reduce_while(enum, ok([]), fn {key, elem}, acc ->
      combine(:all, acc, mapper.(elem) |> transform(&{key, &1}))
    end)
    |> transform(&Map.new/1)
  end

  # The convenience functions `all?/2`, `any?/2`, `find/2`, and `map/2` use this under the hood.
  #
  # Passed to `Enum.reduce_while/3` to combine 2 results on each call.
  #
  # Third arg can be either
  #   - `:any?` (logical `OR`)
  #   - `:all?` (logical `AND`)
  #   - `:find` to return `{:ok, result}` on first match
  #   - `:all` to return all `{:ok, result}` combined as `{:ok, [result1, result2, ...]}`

  @spec combine(:any? | :all?, b(), b()) :: {:cont | :halt, b()}
  @spec combine(:find, b(), b()) :: {:cont | :halt, v()}
  @spec combine(:all, v(), v()) :: {:cont | :halt, v()}

  defp combine(mode, acc, elem, extra \\ nil)

  defp combine(_mode, _acc, {:error, e}, _), do: {:halt, {:error, e}}

  defp combine(_mode, {:not_loaded, r1}, {:not_loaded, r2}, _),
    do: {:cont, {:not_loaded, Util.deep_merge(r1, r2)}}

  defp combine(_mode, _acc, {:not_loaded, reqs}, _), do: {:cont, {:not_loaded, reqs}}

  # :find
  defp combine(:find, acc, {:ok, false, _}, _), do: {:cont, acc}
  defp combine(:find, {:not_loaded, reqs}, {:ok, true, _}, _), do: {:halt, {:not_loaded, reqs}}
  defp combine(:find, {:ok, _, _}, {:ok, true, binds}, mapper), do: {:halt, mapper.(binds)}

  # :all
  defp combine(:all, {:not_loaded, reqs}, {:ok, _, _}, _), do: {:cont, {:not_loaded, reqs}}

  defp combine(:all, {:ok, results, binds}, {:ok, result, new_binds}, _),
    do: {:cont, {:ok, [result | results], Map.merge(new_binds, binds)}}

  # :filter
  defp combine(:filter, acc, {:ok, true, binds}, mapper), do: combine(:all, acc, mapper.(binds))
  # defp combine(:filter, {:not_loaded, reqs}, {:ok, _, _}, _), do: {:cont, {:not_loaded, reqs}}
  defp combine(:filter, acc, {:ok, false, _}, _), do: {:cont, acc}

  # defp combine(:filter, {:ok, results, binds}, {:ok, true, new_binds}, result),
  #   do: {:cont, {:ok, [result | results], Map.merge(new_binds, binds)}}
  # defp combine(:filter, {:ok, _results, _binds} = acc, {:ok, true, new_binds}, mapper),
  #   do: combine(:all, acc, mapper.(new_binds))

  # :count
  defp combine(:count, {:ok, count, binds}, {:ok, true, new_binds}, _),
    do: {:cont, {:ok, count + 1, Map.merge(new_binds, binds)}}

  defp combine(:count, acc, {:ok, _, _}, _), do: {:cont, acc}

  # :count_while
  defp combine(:count_while, acc, {:ok, false, _}, _), do: {:halt, acc}
  defp combine(:count_while, acc, {:ok, :skip, _}, _), do: {:cont, acc}

  defp combine(:count_while, {:not_loaded, reqs}, {:ok, true, _}, _),
    do: {:cont, {:not_loaded, reqs}}

  defp combine(:count_while, {:ok, count, binds}, {:ok, true, new_binds}, _),
    do: {:cont, {:ok, count + 1, Map.merge(new_binds, binds)}}

  # :any?
  defp combine(:any?, _acc, {:ok, true, binds}, _), do: {:halt, {:ok, true, binds}}
  defp combine(:any?, acc, {:ok, false, _}, _), do: {:cont, acc}

  # :all?
  defp combine(:all?, _acc, {:ok, false, _}, _), do: {:halt, {:ok, false, %{}}}

  defp combine(:all?, {:not_loaded, reqs}, {:ok, true, _binds}, _),
    do: {:cont, {:not_loaded, reqs}}

  defp combine(:all?, {:ok, true, binds}, {:ok, true, new_binds}, _),
    do: {:cont, {:ok, true, Map.merge(new_binds, binds)}}
end
