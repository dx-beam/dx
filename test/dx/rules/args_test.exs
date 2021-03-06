defmodule Dx.Rules.ArgsTest do
  use Dx.Test.DataCase

  defmodule Rules do
    use Dx.Rules, for: List

    infer active?: true, when: %{args: %{active?: true}}
    infer active?: false

    infer has_user_verified?: true, when: %{args: %{user: %{last_name: {:not, nil}}}}
    infer has_user_verified?: false

    infer created_by?: true,
          when: %{
            args: %{user: %{last_name: {:not, nil}}},
            created_by_id: {:ref, [:args, :user, :id]}
          }

    infer created_by?: false
  end

  describe "args can be passed to rules" do
    setup do
      user = create(User, %{last_name: "Medina"})
      list = create(List, %{created_by: user})
      [list: list, user: user]
    end

    test "args can be read directly in a rule", %{list: list} do
      assert Dx.get!(list, :active?, extra_rules: [Rules], args: [active?: true]) ==
               true

      assert Dx.get!(list, :active?, extra_rules: [Rules], args: [active?: false]) == false
      assert Dx.get!(list, :active?, extra_rules: [Rules], args: [active?: "yep"]) == false

      assert_raise(KeyError, fn ->
        Dx.get!(list, :active?, extra_rules: [Rules], args: [passive?: true])
      end)

      assert_raise(KeyError, fn ->
        Dx.get!(list, :active?, extra_rules: [Rules])
      end)
    end

    test "nested args can be read directly in a rule", %{list: list, user: user} do
      assert Dx.get!(list, :has_user_verified?, extra_rules: [Rules], args: [user: user]) ==
               true

      other_user = create(User, %{last_name: nil})

      assert Dx.get!(list, :has_user_verified?, extra_rules: [Rules], args: [user: other_user]) ==
               false

      assert_raise(KeyError, fn ->
        Dx.get!(list, :has_user_verified?, extra_rules: [Rules])
      end)
    end

    test "nested args can be matched directly in a rule", %{list: list, user: user} do
      assert Dx.get!(list, :created_by?, extra_rules: [Rules], args: [user: user]) ==
               true

      user = %{user | last_name: nil}

      assert Dx.get!(list, :created_by?, extra_rules: [Rules], args: [user: user]) ==
               false

      other_user = create(User, %{last_name: "Vega"})

      assert Dx.get!(list, :created_by?, extra_rules: [Rules], args: [user: other_user]) ==
               false

      assert_raise(KeyError, fn ->
        Dx.get!(list, :created_by?, extra_rules: [Rules])
      end)
    end
  end
end
