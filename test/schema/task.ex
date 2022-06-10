defmodule Infer.Test.Schema.Task do
  use Ecto.Schema

  alias Infer.Test.Schema.{List, User}

  schema "tasks" do
    field :title, :string
    field :desc, :string

    belongs_to :list, List
    belongs_to :created_by, User

    field :completed_at, :utc_datetime
    field :archived_at, :utc_datetime
    timestamps()
  end
end