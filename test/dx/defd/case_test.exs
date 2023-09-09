defmodule Dx.Defd.CaseTest do
  use Dx.Test.DefdCase, async: false

  describe "data loading" do
    setup do
      user = create(User, %{role: %{name: "Assistant"}})
      list = create(List, %{created_by: user})
      task = create(Task, %{list: list, created_by: user})

      [
        user: unload(user),
        preloaded_user: user,
        preloaded_list: %{list | tasks: [task]},
        list: unload(list),
        preloaded_task: task,
        task: unload(task)
      ]
    end

    test "matches field in association", %{list: list, user: %{id: user_id}} do
      defmodule AssocFieldTest do
        import Dx.Defd

        defd created_by_id(list) do
          case list do
            %{created_by: %{id: id}} -> id
            _other -> nil
          end
        end
      end

      assert load(AssocFieldTest.created_by_id(list)) == {:ok, user_id}
    end

    test "matches field in nested association", %{task: task, user: %{id: user_id}} do
      defmodule DeepAssocFieldTest do
        import Dx.Defd

        defd created_by_id(task) do
          case task do
            %{list: %{created_by: %{id: id}}} -> id
            _other -> nil
          end
        end
      end

      assert load(DeepAssocFieldTest.created_by_id(task)) == {:ok, user_id}
    end

    test "matches field in typed association", %{task: task, user: %{id: user_id}} do
      defmodule TypedAssocFieldTest do
        import Dx.Defd

        defd created_by_id(task) do
          case task do
            %Task{list: %List{created_by: %{id: id}}} -> id
            _other -> nil
          end
        end
      end

      assert load(TypedAssocFieldTest.created_by_id(task)) == {:ok, user_id}
    end

    test "matches entire associated record", %{list: list, user: %{id: user_id}} do
      defmodule FullAssocTest do
        import Dx.Defd

        defd created_by(list) do
          case list do
            %{created_by: user} -> user
            _other -> nil
          end
        end
      end

      assert {:ok, %{id: ^user_id}} = load(FullAssocTest.created_by(list))
    end

    test "supports anonymous functions", %{
      list: list,
      preloaded_user: %{role: %{name: role_name}}
    } do
      defmodule InnerFnTest do
        import Dx.Defd

        defd indirect_enum_map(list) do
          case list do
            %List{created_by: user} ->
              call(
                defp_enum_map(list.tasks, fn _task ->
                  user.role.name
                end)
              )
          end
        end

        defp defp_enum_map(enum, fun), do: Enum.map(enum, fun)
      end

      assert load(InnerFnTest.indirect_enum_map(list)) == {:ok, [role_name]}
    end

    test "nested cases", %{
      list: list,
      preloaded_user: %{role: %{name: role_name}}
    } do
      defmodule NestedTest do
        import Dx.Defd

        defd indirect_enum_map(list) do
          case list do
            %List{created_by: user} ->
              case user.role do
                %{name: _role_name} ->
                  call(
                    defp_enum_map(list.tasks, fn _task ->
                      user.role.name
                    end)
                  )
              end
          end
        end

        defp defp_enum_map(enum, fun), do: Enum.map(enum, fun)
      end

      assert load(NestedTest.indirect_enum_map(list)) == {:ok, [role_name]}
    end

    test "nested cases calling defd functions", %{
      list: list,
      preloaded_user: %{role: %{name: role_name}}
    } do
      defmodule Nested2Test do
        import Dx.Defd

        defd user_role(user) do
          user.role
        end

        defd indirect_enum_map(list) do
          case list do
            %List{created_by: user} ->
              case user_role(user) do
                %{name: "Assistant"} ->
                  user_role(user).name
              end
          end
        end
      end

      assert load(Nested2Test.indirect_enum_map(list)) == {:ok, role_name}
    end

    test "matches list", %{list: list, user: %{id: user_id}} do
      defmodule ListTest do
        import Dx.Defd

        defd created_by(list, mode) do
          case [list, mode] do
            [%{created_by: user}, :record] -> user
            [%{created_by_id: user_id}, :id] -> user_id
            _other -> nil
          end
        end
      end

      assert {:ok, %{id: ^user_id}} = load(ListTest.created_by(list, :record))
      assert {:ok, ^user_id} = load(ListTest.created_by(list, :id))
    end

    test "matches simple list", %{list: list, user: %{id: user_id}} do
      defmodule SimpleListTest do
        import Dx.Defd

        defd created_by(arg) do
          case [nil] do
            [nil] -> arg
          end
        end
      end

      assert {:ok, :record} = load(SimpleListTest.created_by(:record))
    end

    test "matches empty list", %{list: list, user: %{id: user_id}} do
      defmodule EmptyListTest do
        import Dx.Defd

        defd created_by(arg) do
          case [] do
            [] -> arg
          end
        end
      end

      assert {:ok, :record} = load(EmptyListTest.created_by(:record))
    end

    test "matches 2-tuple", %{list: list, user: %{id: user_id}} do
      defmodule TupleTest do
        import Dx.Defd

        defd created_by(list, mode) do
          case {list, mode} do
            {%{created_by: user}, :record} -> user
            {%{created_by_id: user_id}, :id} -> user_id
            _other -> nil
          end
        end
      end

      assert {:ok, %{id: ^user_id}} = load(TupleTest.created_by(list, :record))
      assert {:ok, ^user_id} = load(TupleTest.created_by(list, :id))
    end

    test "matches 3-tuple", %{list: list, user: %{id: user_id}} do
      defmodule Tuple3Test do
        import Dx.Defd

        defd created_by(list, mode) do
          case {list, mode, nil} do
            {%{created_by: user}, :record, nil} -> user
            {%{created_by_id: user_id}, :id, nil} -> user_id
            _other -> nil
          end
        end
      end

      assert {:ok, %{id: ^user_id}} = load(Tuple3Test.created_by(list, :record))
      assert {:ok, ^user_id} = load(Tuple3Test.created_by(list, :id))
    end
  end

  describe "compile error" do
    test "on case without clauses" do
      refute_stderr(fn ->
        assert_raise CompileError,
                     ~r"#{location(+6)}: Invalid case syntax",
                     fn ->
                       defmodule TupleMatchTest do
                         import Dx.Defd

                         defd add(a) do
                           case(a)
                         end
                       end
                     end
      end)
    end
  end
end
