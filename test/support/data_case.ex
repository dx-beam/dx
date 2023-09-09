defmodule Dx.Test.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Dx.Test.Repo
      alias Dx.Test.Schema.{List, ListCalendarOverride, ListTemplate, Role, Task, User}

      import Test.Support.Factories
      import Test.Support.DateTimeHelpers
      import Dx.Test.DataCase.Helpers
    end
  end

  defmodule Helpers do
    def unload(record) when is_struct(record) do
      Dx.Test.Repo.reload!(record)
    end

    def unload(map) when is_map(map) do
      Map.new(map, fn {k, v} -> {unload(k), unload(v)} end)
    end

    def unload(records) when is_list(records) do
      Enum.map(records, &unload/1)
    end

    def unload(tuple) when is_tuple(tuple) do
      tuple |> Tuple.to_list() |> unload() |> List.to_tuple()
    end

    def unload(other), do: other
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dx.Test.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Dx.Test.Repo, {:shared, self()})
    end

    :ok
  end
end
