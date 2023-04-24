defmodule Dx.Repo do
  @moduledoc """
  Defines a repository with default options, similar to `Ecto.Repo`.

  When used, the repository expects the `:otp_app` as option.
  The `:otp_app` should point to an OTP application that has
  the repository configuration. For example, the repository:

      defmodule Repo do
        use Dx.Repo,
          otp_app: :my_app,
          loader: Dx.Loaders.Dataloader,
          loader_options: [telemetry_options: [dx: true]]
      end

  Could be configured with:

      config :my_app, Repo,
        loader_options: [timeout: 20_000]

  See `Dx` for further options. The options are deep-merged,
  with the following order of precedence:

  1. Options passed to boundary functions, such as `Dx.get/3`
  2. Options returned by `Dx.Repo.default_options/1` callback
  3. Options from config
  4. Options from `use Dx.Repo, ...`.
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Dx.Repo
      @otp_app Keyword.fetch!(opts, :otp_app)
      @opts opts

      def default_options(_operation), do: []
      defoverridable default_options: 1

      @compile {:inline, prepare_opts: 2}
      defp prepare_opts(operation_name, opts) do
        config = Application.get_env(otp_app, __MODULE__, [])

        @opts
        |> Dx.Util.Keyword.deep_merge(config)
        |> Dx.Util.Keyword.deep_merge(default_options(operation_name))
        |> Dx.Util.Keyword.deep_merge(opts)
      end

      def get(records, predicates, opts \\ []) do
        Dx.get(records, predicates, prepare_opts(opts, :get))
      end

      def get!(records, predicates, opts \\ []) do
        Dx.get!(records, predicates, prepare_opts(opts, :get))
      end

      def load(records, predicates, opts \\ []) do
        Dx.load(records, predicates, prepare_opts(opts, :load))
      end

      def load!(records, predicates, opts \\ []) do
        Dx.load!(records, predicates, prepare_opts(opts, :load))
      end

      def put(records, predicates, opts \\ []) do
        Dx.put(records, predicates, prepare_opts(opts, :put))
      end

      def put!(records, predicates, opts \\ []) do
        Dx.put!(records, predicates, prepare_opts(opts, :put))
      end

      def filter(records, condition, opts \\ []) when is_list(records) do
        Dx.filter(records, condition, prepare_opts(opts, :filter))
      end

      def reject(records, condition, opts \\ []) when is_list(records) do
        Dx.reject(records, condition, prepare_opts(opts, :reject))
      end

      def query_all(queryable, condition, opts \\ []) do
        Dx.query_all(queryable, condition, prepare_opts(opts, :query_all))
      end

      def query_one(queryable, condition, opts \\ []) do
        Dx.query_one(queryable, condition, prepare_opts(opts, :query_one))
      end
    end
  end

  ## User callbacks

  @doc """
  A user customizable callback invoked to retrieve default options
  for operations.
  This can be used to provide default values per operation that
  have higher precedence than the values given on configuration.
  """
  @doc group: "User callbacks"
  @callback default_options(operation) :: Keyword.t()
            when operation: :get | :load | :put | :filter | :reject | :query_one | :query_all

  ## Query API

  @type record :: any()
  @type predicate :: any()
  @type condition :: any()
  @type queryable :: any()
  @type opts :: Keyword.t()

  @doc group: "Query API"
  @callback get([record], [predicate], opts) :: any()

  @doc group: "Query API"
  @callback get!([record], [predicate], opts) :: any()

  @doc group: "Query API"
  @callback load([record], [predicate], opts) :: any()

  @doc group: "Query API"
  @callback load!([record], [predicate], opts) :: any()

  @doc group: "Query API"
  @callback put([record], [predicate], opts) :: any()

  @doc group: "Query API"
  @callback put!([record], [predicate], opts) :: any()

  @doc group: "Query API"
  @callback filter([record], condition, opts) :: any()

  @doc group: "Query API"
  @callback reject([record], condition, opts) :: any()

  @doc group: "Query API"
  @callback query_all(queryable, condition, opts) :: any()

  @doc group: "Query API"
  @callback query_one(queryable, condition, opts) :: any()
end
