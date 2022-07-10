defmodule Dx.Loaders.Dataloader do
  @moduledoc """
  Uses `Dataloader` to load missing data incrementally.
  """

  alias Dx.Result

  # Query = Wrapper around Loader ✅
  # 1. extract the part that can be translated to query
  #   -> can use lookup, may return {:not_loaded, data_reqs}
  # 2. pass translatable part to lookup (unchanged)
  # 3. later: optimize batching
  # 4. on successful lookup, if not all translated, return {:partial, result, condition} for Dx.Engine
  def lookup(cache, data_req) do
    case apply(Dataloader, :get, [cache | args_for(data_req)]) do
      {:error, "Unable to find " <> _} ->
        # try to translate to query here
        #   -> loader needs eval, pass it in/through
        # how to ensure optimized batching can happen here?
        {:not_loaded, MapSet.new([data_req])}

      {:ok, result} ->
        Result.ok(result)

      other ->
        other
    end
  end

  defp args_for({:assoc, subject, key}) do
    [:assoc, key, subject]
  end

  defp args_for({:query_one, type, [main_condition | other_conditions], opts}) do
    opts = opts |> where(other_conditions)
    [:assoc, {:one, type, opts}, [main_condition]]
  end

  defp args_for({:query_first, type, [main_condition | other_conditions], opts}) do
    opts = opts |> where(other_conditions) |> Keyword.put(:limit, 1)
    [:assoc, {:one, type, opts}, [main_condition]]
  end

  defp args_for({:query_all, type, [main_condition | other_conditions], opts}) do
    opts = opts |> where(other_conditions)
    [:assoc, {:many, type, opts}, [main_condition]]
  end

  defp where(opts, []), do: opts
  defp where(opts, conditions), do: Keyword.put(opts, :where, {:all, conditions})

  def init() do
    repo = config(:repo)

    # workaround for dataloader incompatibility with transactions
    #   -> https://github.com/absinthe-graphql/dataloader/issues/129#issuecomment-965492108
    run_concurrently? = not db_conn_checked_out?(repo)

    source =
      Dataloader.Ecto.new(repo,
        query: &Dx.Ecto.Query.from_options/2,
        async: run_concurrently?
      )

    Dataloader.new(get_policy: :tuples, async: run_concurrently?)
    |> Dataloader.add_source(:assoc, source)
  end

  defp db_conn_checked_out?(repo_name) do
    case Ecto.Repo.Registry.lookup(repo_name) do
      # Ecto < 3.8.0
      {adapter, meta} -> adapter.checked_out?(meta)
      # Ecto >= 3.8.0
      %{adapter: adapter} = meta -> adapter.checked_out?(meta)
    end
  end

  def load(cache, data_reqs) do
    Enum.reduce(data_reqs, cache, fn data_req, cache ->
      apply(Dataloader, :load, [cache | args_for(data_req)])
    end)
    |> Dataloader.run()
  end

  def config(:repo), do: Application.fetch_env!(:dx, :repo)
end
