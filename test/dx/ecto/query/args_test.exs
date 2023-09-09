defmodule Dx.Ecto.Query.ArgsTest do
  use Dx.Test.DataLoadingCase

  alias Dx.Ecto.Query
  alias Dx.Test.Repo

  defmodule UserRules do
    use Dx.Rules, for: User

    infer admin?: true, when: %{role: %{name: "ADMIN"}}
  end

  defmodule Rules do
    use Dx.Rules, for: List

    import_rules UserRules

    infer created_by_current_user?: true,
          when: %{created_by_id: {:ref, [:args, :current_user, :id]}}

    infer created_by_current_user?: false

    infer can_manage?: true, when: :created_by_current_user?
    infer can_manage?: true, when: %{args: %{current_user: %{admin?: true}}}
    infer can_manage?: false
  end

  defp to_sql(query), do: Query.to_sql(Repo, query)

  test "condition on args record field" do
    user = create(User)

    query =
      Query.where(List, %{created_by_current_user?: true},
        extra_rules: Rules,
        args: [current_user: user]
      )

    assert to_sql(query) =~ "\"created_by_id\" = #{user.id}"
  end

  test "loads args record for condition on args record predicate" do
    user = create(User)

    query =
      Query.where(List, %{can_manage?: true},
        extra_rules: Rules,
        args: [current_user: user]
      )

    assert to_sql(query) =~ "\"created_by_id\" = #{user.id}"
  end

  test "loads args record for condition on args record predicate2" do
    user = create(User, %{role: %{name: "ADMIN"}})

    query =
      Query.where(List, %{can_manage?: true},
        extra_rules: Rules,
        args: [current_user: user]
      )

    refute to_sql(query) =~ "\"created_by_id\" = #{user.id}"
  end

  test "loads args record for condition on args record predicate3" do
    user = create(User, %{role: %{name: "ADMIN"}}) |> unload()

    query =
      Query.where(List, %{can_manage?: true},
        extra_rules: Rules,
        args: [current_user: user]
      )

    refute to_sql(query) =~ "\"created_by_id\" = #{user.id}"
  end
end
