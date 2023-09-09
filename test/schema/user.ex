defmodule Dx.Test.Schema.User do
  use Ecto.Schema
  use Dx.Ecto.Schema, repo: Dx.Test.Repo

  alias Dx.Test.Schema.{List, Role}

  schema "users" do
    field :email, :string
    field :verified_at, :utc_datetime

    field :first_name, :string
    field :last_name, :string

    has_many :lists, List, foreign_key: :created_by_id
    belongs_to :role, Role
  end

  infer full_name: {&Enum.join/1, [[{:ref, :first_name}, {:ref, :last_name}]]}
end
