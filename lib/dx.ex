defmodule Dx do
  @moduledoc """
  This is the main entry for using the Dx API.

  - `get/3` evaluates the given predicate(s) using only the (pre)loaded data available, and returns the result(s)
  - `load/3` is like `get`, but loads any additional data as needed
  - `put/3` is like `load`, but puts the results into the `:inferred` field
    (or virtual schema field) of the subject(s) as a map, and returns the subject(s)

  These functions return a tuple, either `{:ok, result}`, `{:error, error}`, or `{:not_loaded, data_reqs}` (only `get`).

  The corresponding `get!/3`, `load!/3` and `put!/3` functions return `result`
  directly, or otherwise raise an exception.

  Arguments:
  - **subjects** can either be an individual subject (with the given predicates defined on it), or a list of subjects.
    Passing an individual subject will return the predicates for the subject, passing a list will return a list of them.
  - **predicates** can either be a single predicate, or a list of predicates.
    Passing a single predicate will return the resulting value, passing a list will return a **map**
    of the predicates and their resulting values.
  - **options** (optional) See below.

  Options:
  - **args** (list or map) can be used to pass in data from the caller's context that can be used in
    rules (see *Arguments* below). A classic example is the `current_user`, e.g.
    ```elixir
    put!(project, :can_edit?, args: [user: current_user])
    ```
  - **extra_rules** (module or list of modules) can be used to add context-specific rules that are
    not defined directly on the subject. This can be used to structure rules into their own modules
    and use them only where needed.
  - **debug** (boolean) makes Dx print additional information to the console as rules are evaluated.
    Should only be used while debugging.
  - **return_cache** (boolean) makes non-bang functions return `{:ok, result, cache}` instead of
    `{:ok, result}` on success. This `cache` can be passed to other Dx functions (see `cache` option)
  - **cache** (`Dataloader` struct) can be used to pass in an existing cache, so data already loaded
    doesn't need to be loaded again. Can be initialized using `Dx.Loaders.Dataloader.init/1`.
  - **loader** allows choosing a loader module. Defaults to `Dx.Loaders.Dataloader`.
  - **loader_options** are passed to `loader.init/1` function. See `Dx.Loaders.Dataloader` for options
    supported by the default loader.
  """

  alias Dx.{Engine, Result, Util}
  alias Dx.Evaluation, as: Eval

  @doc """
  Evaluates one or multiple predicates for one or multiple records and returns the results.

  Does not load any additional data.
  """
  def get(records, predicates, opts \\ []) do
    eval = Eval.from_options(opts)

    do_get(records, predicates, eval)
    |> Result.to_simple_if(not eval.return_cache?)
  end

  defp do_get(records, predicates, eval) when is_list(records) do
    Result.map(records, &do_get(&1, predicates, eval))
  end

  defp do_get(record, predicates, eval) when is_list(predicates) do
    Result.map(predicates, &Engine.resolve_predicate(&1, record, eval))
    |> Result.transform(&Util.Map.zip(predicates, &1))
  end

  defp do_get(record, predicate, eval) when is_atom(predicate) do
    Engine.resolve_predicate(predicate, record, eval)
  end

  defp do_get(record, result, eval) do
    Engine.map_result(result, %{eval | root_subject: record})
  end

  @doc """
  Like `get/3` but returns the result value, or raises an error.
  """
  def get!(records, predicates, opts \\ []) do
    get(records, predicates, opts)
    |> Result.unwrap!()
  end

  @doc """
  Like `get/3`, but loads additional data if needed.
  """
  def load(records, predicates, opts \\ []) do
    eval = Eval.from_options(opts)

    do_load(records, predicates, eval)
    |> Result.to_simple_if(not eval.return_cache?)
  end

  defp do_load(records, predicates, eval) do
    load_all_data_reqs(eval, fn eval ->
      do_get(records, predicates, eval)
    end)
  end

  def load_all_data_reqs(eval, fun) do
    case fun.(eval) do
      {:not_loaded, data_reqs} ->
        Eval.load_data_reqs(eval, data_reqs) |> load_all_data_reqs(fun)

      {:ok, result, _binds} ->
        {:ok, result, eval.cache}

      {:error, :timeout} ->
        {:error, %Dx.Error.Timeout{configured_timeout: eval.loader_options[:timeout]}}

      other ->
        other
    end
  rescue
    e ->
      # Remove Dx's inner stacktrace and convert defd function names
      Dx.Defd.Error.filter_and_reraise(e, __STACKTRACE__)
  end

  @doc """
  Like `get!/3`, but loads additional data if needed.
  """
  def load!(records, predicates, opts \\ []) do
    load(records, predicates, opts)
    |> Result.unwrap!()
  end

  @doc """
  Loads the given predicate(s) for the given record(s) and merges the
  results into the `inferred` map field of the record(s), returning them.

  ## Options

  Same as for `get/3`.
  """
  def put(records, predicates, opts \\ []) do
    eval = Eval.from_options(opts)

    do_load(records, List.wrap(predicates), eval)
    |> Result.transform(&do_put(records, &1))
    |> Result.to_simple_if(not eval.return_cache?)
  end

  defp do_put(records, results) when is_list(records) do
    Util.Enum.zip(records, results, &do_put/2)
  end

  defp do_put(record, results) do
    Map.update!(record, :inferred, &Util.Map.maybe_merge(&1, results))
  end

  def put!(records, predicates, opts \\ []) do
    put(records, predicates, opts)
    |> Result.unwrap!()
  end

  defp get_type(%Ecto.Query{from: %{source: {_, type}}}), do: type
  defp get_type(%type{}), do: type
  defp get_type([%type{} | _]), do: type

  defp get_type(type) when is_atom(type) do
    Code.ensure_compiled(type)

    if Util.Module.has_function?(type, :dx_rules_for, 2) do
      type
    else
      raise ArgumentError, "Could not derive type from " <> inspect(type, pretty: true)
    end
  end

  @doc "Removes all elements not matching the given condition from the given list."
  def filter(records, condition, opts \\ []) when is_list(records) do
    eval = Eval.from_options(opts)

    do_filter(records, condition, eval)
  end

  defp do_filter(records, true, _eval) do
    records
  end

  defp do_filter(records, condition, eval) do
    if eval.debug?, do: IO.puts("Dx Filter: #{inspect(condition, pretty: true)}")

    load_all_data_reqs(eval, fn eval ->
      Result.filter_map(
        records,
        &Engine.evaluate_condition(condition, &1, %{eval | root_subject: &1})
      )
    end)
    |> Result.unwrap!()
  end

  @doc "Removes all elements matching the given condition from the given list."
  def reject(records, condition, opts \\ []) when is_list(records) do
    filter(records, {:not, condition}, opts)
  end

  @doc """
  Returns all records matching the given condition.

  ## Caveat

  In general, as much work as possible is done in the database.
  If possible, the condition is completely translated to an `Ecto.Query`
  so the database only returns matching records.
  All condition parts that can not be translated to an `Ecto.Query`, will be
  evaluated by **loading all remaining records**, and associations as needed,
  and evaluating the rules on them.
  """
  def query_all(queryable, condition, opts \\ []) do
    {queryable, condition, repo, eval} = build_query(queryable, condition, opts)

    queryable
    |> repo.all()
    |> do_filter(condition, eval)
    |> apply_select(eval)
  end

  @doc """
  Returns the first record matching the given condition.

  ## Options

  Same as for `query_all/3`.
  """
  def query_one(queryable, condition, opts \\ []) do
    {queryable, condition, repo, eval} = build_query(queryable, condition, opts)

    queryable
    |> repo.one!()
    |> do_filter(condition, eval)
    |> apply_select(eval)
  end

  defp build_query(queryable, condition, opts) do
    type = get_type(queryable)
    query_mod = type.dx_query_module()
    repo = type.dx_repo()

    {queryable, opts} = query_mod.apply_options(queryable, opts)

    eval = Eval.from_options(opts)
    {queryable, condition} = query_mod.apply_condition(queryable, condition, eval)

    if eval.debug? do
      sql = query_mod.to_sql(repo, queryable)
      IO.puts("Dx SQL: #{sql}")
    end

    {queryable, condition, repo, eval}
  end

  defp apply_select(records, %{select: nil}), do: records

  defp apply_select(records, %{select: mapping} = eval) do
    load_all_data_reqs(eval, fn eval ->
      Result.map(records, &Engine.map_result(mapping, %{eval | root_subject: &1}))
    end)
    |> Result.unwrap!()
  end
end
