defmodule Dx.Defd.EnumTest do
  use Dx.Test.DefdCase, async: false

  use ExUnitProperties

  setup do
    user =
      create(User, %{
        email: "zoria@max.net",
        verified_at: ~U[2022-01-13 00:01:00Z],
        role: %{name: "Assistant"}
      })

    user2 =
      create(User, %{
        email: "charlie@xoom.ie",
        verified_at: ~U[2022-02-12 00:01:00Z],
        role: %{name: "Assistant"}
      })

    assert user.verified_at > user2.verified_at
    assert DateTime.compare(user.verified_at, user2.verified_at) == :lt

    users = [user, user2]

    list = create(List, %{created_by: user})

    tasks = [
      task = create(Task, %{list: list, created_by: user}),
      task2 = create(Task, %{list: list, created_by: user2}),
      create(Task, %{list: list, created_by: user}),
      create(Task, %{list: list, created_by: user2}),
      create(Task, %{list: list, created_by: user2})
    ]

    task_user_ids = Enum.map(tasks, & &1.created_by_id)
    task_user_emails = Enum.map(tasks, & &1.created_by.email)

    [
      user: unload(user),
      user2: unload(user2),
      users: unload(users),
      preloaded_user: user,
      preloaded_user2: user2,
      preloaded_users: users,
      preloaded_list: %{list | tasks: tasks},
      list: unload(list),
      preloaded_task: task,
      preloaded_task2: task2,
      task: unload(task),
      task2: unload(task2),
      tasks: Enum.map(tasks, &Repo.reload!/1),
      task_user_ids: task_user_ids,
      task_user_emails: task_user_emails,
      preloaded_tasks: tasks
    ]
  end

  describe "nested" do
    test "Enum result as external function arg", %{list: list, preloaded_list: preloaded_list} do
      refute_stderr(fn ->
        defmodule NestedTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            Enum.map(list.tasks, fn task ->
              call(
                simple_arg(
                  Enum.find(task.created_by.lists, fn list ->
                    Enum.count(list.tasks) > 1
                  end)
                )
              )
            end)
          end

          @dx def: :original
          defd run2(list) do
            Enum.map(list.tasks, fn task ->
              call(
                __MODULE__.simple_arg(
                  Enum.find(task.created_by.lists, fn list ->
                    Enum.count(list.tasks) > 1
                  end)
                )
              )
            end)
          end

          def simple_arg(arg) do
            arg
          end

          defp call(arg) do
            arg
          end
        end

        preloaded_list = Repo.preload(preloaded_list, tasks: [created_by: [lists: :tasks]])
        assert load!(NestedTest.run(list)) == unload(NestedTest.run(preloaded_list))
        assert load!(NestedTest.run2(list)) == unload(NestedTest.run2(preloaded_list))
      end)
    end

    test "Enum in external fn body", %{
      list: list,
      preloaded_list: preloaded_list,
      task: task,
      user: user
    } do
      refute_stderr(fn ->
        defmodule EnumInExtFnTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            call(
              enum_map(list.tasks, fn task ->
                Enum.map([task], & &1.created_by.email)
              end)
            )
          end

          @dx def: :original
          defd run2(list) do
            call(
              enum_map(list.tasks, fn task ->
                Enum.map([%{a: %{b: task}}], & &1.a.b.created_by.email)
              end)
            )
          end

          defp enum_map(enum, mapper) do
            Enum.map(enum, mapper)
          end

          defp call(arg) do
            arg
          end
        end

        preloaded_list = Repo.preload(preloaded_list, tasks: :created_by)
        assert load!(EnumInExtFnTest.run(preloaded_list)) == EnumInExtFnTest.run(preloaded_list)
        assert load!(EnumInExtFnTest.run2(preloaded_list)) == EnumInExtFnTest.run2(preloaded_list)
      end)
    end

    test "function reference in fn body", %{
      list: list,
      preloaded_list: preloaded_list,
      task: task,
      user: user
    } do
      refute_stderr(fn ->
        defmodule FunRefInFnTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            call(enum_map(list.tasks, &created_by_email/1))
          end

          @dx def: :original
          defd run2(list) do
            call(enum_map(list.tasks, &__MODULE__.created_by_email/1))
          end

          def created_by_email(task) do
            task.created_by.email
          end

          defp enum_map(enum, mapper) do
            Enum.map(enum, mapper)
          end

          defp call(arg) do
            arg
          end
        end

        preloaded_list = Repo.preload(preloaded_list, tasks: :created_by)

        assert load!(FunRefInFnTest.run(preloaded_list)) ==
                 FunRefInFnTest.run(preloaded_list)

        assert load!(FunRefInFnTest.run2(preloaded_list)) ==
                 FunRefInFnTest.run2(preloaded_list)
      end)
    end

    test "function reference in external fn body", %{
      list: list,
      preloaded_list: preloaded_list,
      task: task,
      user: user
    } do
      refute_stderr(fn ->
        defmodule FunRefInExtFnTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            call(
              enum_map(list.tasks, fn task ->
                Enum.map([task], &created_by_email/1)
              end)
            )
          end

          @dx def: :original
          defd run2(list) do
            call(
              enum_map(list.tasks, fn task ->
                Enum.map([task], &__MODULE__.created_by_email/1)
              end)
            )
          end

          def created_by_email(task) do
            task.created_by.email
          end

          defp enum_map(enum, mapper) do
            Enum.map(enum, mapper)
          end

          defp call(arg) do
            arg
          end
        end

        preloaded_list = Repo.preload(preloaded_list, tasks: :created_by)

        assert load!(FunRefInExtFnTest.run(preloaded_list)) ==
                 FunRefInExtFnTest.run(preloaded_list)

        assert load!(FunRefInExtFnTest.run2(preloaded_list)) ==
                 FunRefInExtFnTest.run2(preloaded_list)
      end)
    end
  end

  test "all?/1", %{list: list} do
    refute_stderr(fn ->
      defmodule All1Test do
        import Dx.Defd

        defd run(list) do
          Enum.all?(list.tasks)
        end

        defd mapped(list) do
          Enum.all?(Enum.map(list.tasks, & &1))
        end
      end

      assert load(All1Test.run(list)) == {:ok, true}
      assert load(All1Test.mapped(list)) == {:ok, true}
    end)
  end

  describe "all?/2" do
    test "returns false if one element is not truthy", %{list: list} do
      refute_stderr(fn ->
        defmodule All2LoadTest do
          import Dx.Defd

          defd run(list) do
            Enum.all?(
              list.tasks ++ [%{created_by: %{email: nil}}],
              &(not is_nil(&1.created_by.email))
            )
          end
        end

        assert load(All2LoadTest.run(list)) == {:ok, false}
      end)
    end

    test "loads no data if one element is not truthy", %{tasks: tasks} do
      refute_stderr(fn ->
        defmodule All2PartialLoadTest do
          import Dx.Defd

          defd run(tasks) do
            Enum.all?(tasks ++ [%{created_by: %{email: nil}}], &(not is_nil(&1.created_by.email)))
          end
        end

        assert get(All2PartialLoadTest.run(tasks)) == {:ok, false}
      end)
    end
  end

  test "any?/1", %{list: list} do
    refute_stderr(fn ->
      defmodule Any1Test do
        import Dx.Defd

        defd run(list) do
          Enum.any?(list.tasks)
        end

        defd mapped(list) do
          Enum.any?(Enum.map(list.tasks, & &1))
        end

        defd with_nil(list) do
          Enum.any?(list.tasks ++ [nil])
        end

        defd no_truthy() do
          Enum.any?([nil, false])
        end
      end

      assert load(Any1Test.run(list)) == {:ok, true}
      assert load(Any1Test.mapped(list)) == {:ok, true}
      assert load(Any1Test.with_nil(list)) == {:ok, true}
      assert load(Any1Test.no_truthy()) == {:ok, false}
    end)
  end

  describe "any?/2" do
    test "returns true if one element is truthy", %{list: list} do
      refute_stderr(fn ->
        defmodule Any2LoadTest1 do
          import Dx.Defd

          defd run(list) do
            Enum.any?(
              list.tasks,
              &(not is_nil(&1.created_by.email))
            )
          end
        end

        assert load(Any2LoadTest1.run(list)) == {:ok, true}
      end)
    end

    test "returns false if no element is truthy", %{list: list} do
      refute_stderr(fn ->
        defmodule Any2LoadTest2 do
          import Dx.Defd

          defd run(list) do
            Enum.any?(
              list.tasks,
              &is_nil(&1.created_by.email)
            )
          end
        end

        assert load(Any2LoadTest2.run(list)) == {:ok, false}
      end)
    end

    test "loads no data if one element is truthy", %{tasks: tasks} do
      refute_stderr(fn ->
        defmodule Any2PartialLoadTest do
          import Dx.Defd

          defd run(tasks) do
            Enum.any?(tasks ++ [%{created_by: %{email: nil}}], &is_nil(&1.created_by.email))
          end
        end

        assert get(Any2PartialLoadTest.run(tasks)) == {:ok, true}
      end)
    end
  end

  describe "chunk_by/2" do
    test "works for binary return value", %{
      tasks: [t0, t1, t2, t3, t4] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule ChunkBy2BinTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.chunk_by(tasks, & &1.created_by.email)
          end
        end

        assert load(ChunkBy2BinTest.run([])) == {:ok, []}

        assert unload(load!(ChunkBy2BinTest.run([]))) ==
                 unload(ChunkBy2BinTest.run([]))

        assert load(ChunkBy2BinTest.run(tasks)) == {:ok, [[t0], [t1], [t2], [t3, t4]]}

        assert unload(load!(ChunkBy2BinTest.run(tasks))) ==
                 unload(ChunkBy2BinTest.run(preloaded_tasks))
      end)
    end

    test "works for boolean return value", %{
      list: list,
      preloaded_list: preloaded_list,
      tasks: tasks
    } do
      refute_stderr(fn ->
        defmodule ChunkBy2Test do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            Enum.chunk_by(list.tasks, &is_nil(&1.created_by.email))
          end
        end

        assert load(ChunkBy2Test.run(list)) == {:ok, [tasks]}
        assert unload(load!(ChunkBy2Test.run(list))) == unload(ChunkBy2Test.run(preloaded_list))
      end)
    end

    test "works for maps and binary return value", %{
      tasks: [t0, t1, t2, t3, t4] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Chunk2MapBinTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.chunk_by(tasks, fn {_, task} -> task.created_by.email end)
          end
        end

        assert load(Chunk2MapBinTest.run(%{})) == {:ok, []}

        assert unload(load!(Chunk2MapBinTest.run(%{}))) ==
                 unload(Chunk2MapBinTest.run(%{}))

        assert load(Chunk2MapBinTest.run(to_map(tasks))) ==
                 {:ok, [[{t0.id, t0}], [{t1.id, t1}], [{t2.id, t2}], [{t3.id, t3}, {t4.id, t4}]]}

        assert unload(load!(Chunk2MapBinTest.run(to_map(tasks)))) ==
                 unload(Chunk2MapBinTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "chunk_while/4" do
    test "works for empty list", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      task: task,
      preloaded_task: preloaded_task,
      user: user
    } do
      refute_stderr(fn ->
        defmodule ChunkWhile4EmptyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.chunk_while(tasks, task, &{:cont, &1, &2}, fn acc ->
              {:cont, [acc.created_by.email], acc}
            end)
          end
        end

        assert load(ChunkWhile4EmptyTest.run([], task)) == {:ok, [[user.email]]}

        assert load!(ChunkWhile4EmptyTest.run([], task)) ==
                 ChunkWhile4EmptyTest.run([], preloaded_task)

        assert load!(ChunkWhile4EmptyTest.run(tasks, task)) ==
                 unload(ChunkWhile4EmptyTest.run(preloaded_tasks, preloaded_task))
      end)
    end

    test "loads data in mapper", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("Dx can't load", fn ->
        defmodule ChunkWhile4LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.chunk_while(
              tasks,
              [],
              fn elem, acc ->
                {:cont, [elem.created_by | acc]}
              end,
              fn acc -> {:cont, Enum.reverse(acc), []} end
            )
          end
        end

        assert load(ChunkWhile4LoadTest.run(tasks)) ==
                 {:ok, [Enum.map(preloaded_tasks, &unload(&1.created_by))]}

        assert load!(ChunkWhile4LoadTest.run(tasks)) ==
                 unload(ChunkWhile4LoadTest.run(preloaded_tasks))
      end)
    end
  end

  describe "count/2" do
    test "counts truthy mapped values", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Count2TruthyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.count(tasks, & &1.created_by.email)
          end
        end

        assert load(Count2TruthyTest.run([])) == {:ok, 0}
        assert load!(Count2TruthyTest.run([])) == Count2TruthyTest.run([])

        assert load(Count2TruthyTest.run(tasks)) == {:ok, 5}
        assert load!(Count2TruthyTest.run(tasks)) == Count2TruthyTest.run(preloaded_tasks)
      end)
    end

    test "returns 0 for only counts false mapped values", %{
      list: list,
      preloaded_list: preloaded_list,
      tasks: tasks
    } do
      refute_stderr(fn ->
        defmodule Count2FalseTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            Enum.count(list.tasks, &is_nil(&1.created_by.email))
          end
        end

        assert load(Count2FalseTest.run(list)) == {:ok, 0}
        assert load!(Count2FalseTest.run(list)) == Count2FalseTest.run(preloaded_list)
      end)
    end

    test "counts truthy mapped values in map", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Count2MapTruthyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.count(tasks, fn {_, task} -> task.created_by.email end)
          end
        end

        assert load(Count2MapTruthyTest.run(%{})) == {:ok, 0}
        assert load!(Count2MapTruthyTest.run(%{})) == Count2MapTruthyTest.run(%{})

        assert load(Count2MapTruthyTest.run(to_map(tasks))) == {:ok, 5}

        assert load!(Count2MapTruthyTest.run(to_map(tasks))) ==
                 Count2MapTruthyTest.run(to_map(preloaded_tasks))
      end)
    end
  end

  describe "count_until/3" do
    test "counts truthy mapped values", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule CountUntil3TruthyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.count_until(tasks, & &1.created_by.email, 2)
          end
        end

        assert load(CountUntil3TruthyTest.run([])) == {:ok, 0}

        assert load!(CountUntil3TruthyTest.run([])) ==
                 CountUntil3TruthyTest.run([])

        assert load(CountUntil3TruthyTest.run(tasks)) == {:ok, 2}

        assert load!(CountUntil3TruthyTest.run(tasks)) ==
                 CountUntil3TruthyTest.run(preloaded_tasks)
      end)
    end

    test "returns 0 for only counts false mapped values", %{
      list: list,
      preloaded_list: preloaded_list,
      tasks: tasks
    } do
      refute_stderr(fn ->
        defmodule CountUntil3FalseTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            Enum.count_until(list.tasks, &is_nil(&1.created_by.email), 2)
          end
        end

        assert load(CountUntil3FalseTest.run(list)) == {:ok, 0}
        assert load!(CountUntil3FalseTest.run(list)) == CountUntil3FalseTest.run(preloaded_list)
      end)
    end

    test "counts truthy mapped values in map", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule CountUntil3MapTruthyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.count_until(tasks, fn {_, task} -> task.created_by.email end, 2)
          end
        end

        assert load(CountUntil3MapTruthyTest.run(%{})) == {:ok, 0}

        assert load!(CountUntil3MapTruthyTest.run(%{})) ==
                 CountUntil3MapTruthyTest.run(%{})

        assert load(CountUntil3MapTruthyTest.run(to_map(tasks))) == {:ok, 2}

        assert load!(CountUntil3MapTruthyTest.run(to_map(tasks))) ==
                 CountUntil3MapTruthyTest.run(to_map(preloaded_tasks))
      end)
    end
  end

  describe "dedup_by/2" do
    test "works for different mapped values", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule DedupBy2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.dedup_by(tasks, & &1.created_by.email)
          end
        end

        assert load(DedupBy2LoadTest.run([])) == {:ok, []}
        assert load!(DedupBy2LoadTest.run([])) == DedupBy2LoadTest.run([])

        assert load!(DedupBy2LoadTest.run(tasks)) == unload(DedupBy2LoadTest.run(preloaded_tasks))
      end)
    end

    test "returns first entry on uniformly mapped value", %{
      list: list,
      preloaded_list: preloaded_list,
      tasks: [task | _] = tasks
    } do
      refute_stderr(fn ->
        defmodule DedupBy2LoadUniformTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            Enum.dedup_by(list.tasks, &is_nil(&1.created_by.email))
          end
        end

        assert load(DedupBy2LoadUniformTest.run(list)) == {:ok, [task]}

        assert load!(DedupBy2LoadUniformTest.run(list)) ==
                 unload(DedupBy2LoadUniformTest.run(preloaded_list))
      end)
    end

    test "works for different mapped values in map", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule DedupBy2MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.dedup_by(tasks, fn {_, task} -> task.created_by.email end)
          end
        end

        assert load(DedupBy2MapTest.run(%{})) == {:ok, []}
        assert load!(DedupBy2MapTest.run(%{})) == DedupBy2MapTest.run(%{})

        assert load!(DedupBy2MapTest.run(to_map(tasks))) ==
                 unload(DedupBy2MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "drop_while/2" do
    test "works for different mapped values", %{
      tasks: [_ | other_tasks] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule DropWhile2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.drop_while(tasks, &match?(%{created_at: %{email: "z" <> _}}, &1))
          end
        end

        assert load(DropWhile2LoadTest.run([])) == {:ok, []}

        assert load!(DropWhile2LoadTest.run([])) ==
                 DropWhile2LoadTest.run([])

        assert load!(DropWhile2LoadTest.run(tasks)) ==
                 unload(DropWhile2LoadTest.run(preloaded_tasks))
      end)
    end

    test "returns first entry on uniformly mapped value", %{
      list: list,
      preloaded_list: preloaded_list,
      tasks: [task | _] = tasks
    } do
      refute_stderr(fn ->
        defmodule DropWhile2LoadUniformTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            Enum.drop_while(list.tasks, &is_nil(&1.created_by.email))
          end
        end

        assert load(DropWhile2LoadUniformTest.run(list)) == {:ok, tasks}

        assert load!(DropWhile2LoadUniformTest.run(list)) ==
                 unload(DropWhile2LoadUniformTest.run(preloaded_list))
      end)
    end

    test "works for maps and different mapped values", %{
      tasks: [_ | other_tasks] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule DropWhile2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.drop_while(tasks, fn {_, task} ->
              match?(%{created_at: %{email: "z" <> _}}, task)
            end)
          end
        end

        assert load(DropWhile2MapLoadTest.run(%{})) == {:ok, []}

        assert load!(DropWhile2MapLoadTest.run(%{})) ==
                 DropWhile2MapLoadTest.run(%{})

        assert load!(DropWhile2MapLoadTest.run(to_map(tasks))) ==
                 unload(DropWhile2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "each/2" do
    test "works for empty list" do
      assert_stderr("Side effects can be repeated", fn ->
        defmodule Each2EmptyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.each(tasks, fn _ -> true end)
          end
        end

        assert load(Each2EmptyTest.run([])) == {:ok, :ok}
        assert load(Each2EmptyTest.run(%{})) == {:ok, :ok}
      end)
    end
  end

  describe "filter/2" do
    test "works for different mapped values", %{
      tasks: [_ | other_tasks] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Filter2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.filter(tasks, &match?(%{created_at: %{email: "z" <> _}}, &1))
          end
        end

        assert load(Filter2LoadTest.run([])) == {:ok, []}
        assert load!(Filter2LoadTest.run([])) == Filter2LoadTest.run([])

        assert load!(Filter2LoadTest.run(tasks)) == unload(Filter2LoadTest.run(preloaded_tasks))
      end)
    end

    test "returns 0 results on uniformly mapped value", %{
      tasks: [task | _] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Filter2LoadUniformTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.filter(tasks, &is_nil(&1.created_by.email))
          end
        end

        assert load(Filter2LoadUniformTest.run(tasks)) == {:ok, []}

        assert load!(Filter2LoadUniformTest.run(tasks)) ==
                 unload(Filter2LoadUniformTest.run(preloaded_tasks))
      end)
    end

    test "returns input list on uniformly truthy mapped value", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Filter2LoadTruthyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.filter(tasks, & &1.created_by.email)
          end
        end

        assert load(Filter2LoadTruthyTest.run(tasks)) == {:ok, tasks}

        assert load!(Filter2LoadTruthyTest.run(tasks)) ==
                 unload(Filter2LoadTruthyTest.run(preloaded_tasks))
      end)
    end

    test "works for maps and different mapped values", %{
      tasks: [_ | other_tasks] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Filter2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.filter(tasks, fn {_, task} -> match?(%{created_at: %{email: "z" <> _}}, task) end)
          end
        end

        assert load(Filter2MapLoadTest.run(%{})) == {:ok, []}
        assert load!(Filter2MapLoadTest.run(%{})) == Filter2MapLoadTest.run(%{})

        assert load!(Filter2MapLoadTest.run(to_map(tasks))) ==
                 unload(Filter2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "filter_map/3" do
    test "works for different mapped values", %{
      tasks: [_ | other_tasks] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule FilterMap3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.filter_map(
              tasks,
              &match?(%{created_at: %{email: "z" <> _}}, &1),
              & &1.created_by
            )
          end
        end

        assert load(FilterMap3LoadTest.run([])) == {:ok, []}

        assert load!(FilterMap3LoadTest.run([])) ==
                 unload(FilterMap3LoadTest.run([]))

        assert load!(FilterMap3LoadTest.run(tasks)) ==
                 unload(FilterMap3LoadTest.run(preloaded_tasks))
      end)
    end

    test "returns 0 results on uniformly mapped value", %{
      list: list,
      preloaded_list: preloaded_list,
      tasks: [task | _] = tasks
    } do
      refute_stderr(fn ->
        defmodule FilterMap3LoadUniformTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            Enum.filter_map(list.tasks, &is_nil(&1.created_by.email), & &1.created_by)
          end
        end

        assert load(FilterMap3LoadUniformTest.run(list)) == {:ok, []}

        assert load!(FilterMap3LoadUniformTest.run(list)) ==
                 unload(FilterMap3LoadUniformTest.run(preloaded_list))
      end)
    end

    test "returns mapped input list on uniformly truthy mapped value", %{
      list: list,
      preloaded_list: preloaded_list
    } do
      refute_stderr(fn ->
        defmodule FilterMap3LoadTruthyTest do
          import Dx.Defd

          @dx def: :original
          defd run(list) do
            Enum.filter_map(list.tasks, & &1.created_by.email, & &1.created_by)
          end
        end

        assert load!(FilterMap3LoadTruthyTest.run(list)) ==
                 unload(FilterMap3LoadTruthyTest.run(preloaded_list))
      end)
    end

    test "works for maps and different mapped values", %{
      tasks: [_ | other_tasks] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule FilterMap3MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.filter_map(
              tasks,
              fn {_, task} -> match?(%{created_at: %{email: "z" <> _}}, task) end,
              & &1.created_by
            )
          end
        end

        assert load(FilterMap3MapLoadTest.run(%{})) == {:ok, []}

        assert load!(FilterMap3MapLoadTest.run(%{})) ==
                 unload(FilterMap3MapLoadTest.run(%{}))

        assert load!(FilterMap3MapLoadTest.run(to_map(tasks))) ==
                 unload(FilterMap3MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "find/2" do
    test "works finding no element" do
      refute_stderr(fn ->
        defmodule Find2MissTest do
          import Dx.Defd

          @dx def: :original
          defd run(entries) do
            Enum.find(entries, fn _ -> false end)
          end
        end

        assert load(Find2MissTest.run([])) == {:ok, nil}
        assert load(Find2MissTest.run([:a])) == {:ok, nil}
      end)
    end

    test "works finding an element" do
      refute_stderr(fn ->
        defmodule Find2HitTest do
          import Dx.Defd

          @dx def: :original
          defd run(entries) do
            Enum.find(entries, fn _ -> true end)
          end
        end

        assert load(Find2HitTest.run([])) == {:ok, nil}
        assert load(Find2HitTest.run([:a])) == {:ok, :a}
      end)
    end

    test "works with loading data", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule Find2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find(tasks, &match?("c" <> _, &1.created_by.email))
          end
        end

        assert load(Find2LoadTest.run([])) == {:ok, nil}
        assert load!(Find2LoadTest.run([])) == Find2LoadTest.run([])

        assert load(Find2LoadTest.run(tasks)) == {:ok, task2}

        assert load!(Find2LoadTest.run(tasks)) ==
                 unload(Find2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps with loading data", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule Find2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find(tasks, fn {_, task} -> match?("c" <> _, task.created_by.email) end)
          end
        end

        assert load(Find2MapLoadTest.run(%{})) == {:ok, nil}
        assert load!(Find2MapLoadTest.run(%{})) == Find2MapLoadTest.run(%{})

        assert load(Find2MapLoadTest.run(to_map(tasks))) == {:ok, {task2.id, task2}}

        assert load!(Find2MapLoadTest.run(to_map(tasks))) ==
                 unload(Find2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "find/3" do
    test "works for empty list" do
      refute_stderr(fn ->
        defmodule Find3EmptyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find(tasks, :none, fn _ -> true end)
          end
        end

        assert load(Find3EmptyTest.run([])) == {:ok, :none}
        assert load(Find3EmptyTest.run([:a])) == {:ok, :a}
      end)
    end

    test "works finding no element" do
      refute_stderr(fn ->
        defmodule Find3MissTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find(tasks, :none, fn _ -> false end)
          end
        end

        assert load(Find3MissTest.run([])) == {:ok, :none}
        assert load(Find3MissTest.run([:a])) == {:ok, :none}
      end)
    end
  end

  describe "find_index/2" do
    test "works finding an element" do
      refute_stderr(fn ->
        defmodule FindIndex2HitTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find_index(tasks, fn _ -> true end)
          end
        end

        assert load(FindIndex2HitTest.run([])) == {:ok, nil}
        assert load(FindIndex2HitTest.run([:a])) == {:ok, 0}
      end)
    end

    test "works finding no element" do
      refute_stderr(fn ->
        defmodule FindIndex2MissTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find_index(tasks, fn _ -> false end)
          end
        end

        assert load(FindIndex2MissTest.run([])) == {:ok, nil}
        assert load(FindIndex2MissTest.run([:a])) == {:ok, nil}
      end)
    end

    test "works with loading data", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule FindIndex2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find_index(tasks, &match?("c" <> _, &1.created_by.email))
          end
        end

        assert load(FindIndex2LoadTest.run(tasks)) == {:ok, 1}

        assert load!(FindIndex2LoadTest.run(tasks)) ==
                 unload(FindIndex2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps and loading data", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule FindIndex2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find_index(tasks, fn {_, task} -> match?("c" <> _, task.created_by.email) end)
          end
        end

        assert load(FindIndex2MapLoadTest.run(%{})) == {:ok, nil}
        assert load(FindIndex2MapLoadTest.run(to_map(tasks))) == {:ok, 1}

        assert load!(FindIndex2MapLoadTest.run(to_map(tasks))) ==
                 unload(FindIndex2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "find_value/2" do
    test "works finding an element" do
      refute_stderr(fn ->
        defmodule FindValue2HitTest do
          import Dx.Defd

          @dx def: :original
          defd run(entries) do
            Enum.find_value(entries, fn _ -> :val end)
          end
        end

        assert load(FindValue2HitTest.run([])) == {:ok, nil}
        assert load(FindValue2HitTest.run([:a])) == {:ok, :val}
      end)
    end

    test "works finding no element" do
      refute_stderr(fn ->
        defmodule FindValue2MissTest do
          import Dx.Defd

          @dx def: :original
          defd run(entries) do
            Enum.find_value(entries, fn _ -> false end)
          end
        end

        assert load(FindValue2MissTest.run([])) == {:ok, nil}
        assert load(FindValue2MissTest.run([:a])) == {:ok, nil}
      end)
    end

    test "works with loading data", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule FindValue2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find_value(tasks, &match?("c" <> _, &1.created_by.email))
          end
        end

        assert load(FindValue2LoadTest.run(tasks)) == {:ok, true}

        assert load!(FindValue2LoadTest.run(tasks)) ==
                 unload(FindValue2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps and loading data", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule FindValue2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.find_value(tasks, fn {_, task} -> match?("c" <> _, task.created_by.email) end)
          end
        end

        assert load(FindValue2MapLoadTest.run(%{})) == {:ok, nil}

        assert load(FindValue2MapLoadTest.run(to_map(tasks))) == {:ok, true}

        assert load!(FindValue2MapLoadTest.run(to_map(tasks))) ==
                 unload(FindValue2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "find_value/3" do
    test "returns given default when no value found" do
      refute_stderr(fn ->
        defmodule FindValue3MissTest do
          import Dx.Defd

          @dx def: :original
          defd run(entries) do
            Enum.find_value(entries, :none, fn _ -> false end)
          end
        end

        assert load(FindValue3MissTest.run([])) == {:ok, :none}
        assert load(FindValue3MissTest.run([:a])) == {:ok, :none}
      end)
    end
  end

  describe "flat_map/2" do
    test "works with loading data", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule FlatMap2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.flat_map(tasks, &[&1.id, &1.created_by.email])
          end
        end

        assert load(FlatMap2LoadTest.run([])) == {:ok, []}
        assert load!(FlatMap2LoadTest.run([])) == FlatMap2LoadTest.run([])

        assert load!(FlatMap2LoadTest.run(tasks)) == unload(FlatMap2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule FlatMap2MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.flat_map(map, fn {id, task} -> [id, task.created_by.email] end)
          end
        end

        assert load(FlatMap2MapTest.run(%{})) == {:ok, []}

        assert load!(FlatMap2MapTest.run(to_map(tasks))) ==
                 unload(FlatMap2MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "flat_map_reduce/3" do
    test "works with loading data", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule FlatMapReduce3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.flat_map_reduce(tasks, [], &{&2, [&1.id, &1.created_by.email | &2]})
          end

          @dx def: :original
          defd halt(tasks) do
            Enum.flat_map_reduce(tasks, [], fn task, _ -> {:halt, task.created_by.email} end)
          end
        end

        assert load(FlatMapReduce3LoadTest.run([])) == {:ok, {[], []}}

        assert load!(FlatMapReduce3LoadTest.run(tasks)) ==
                 unload(FlatMapReduce3LoadTest.run(preloaded_tasks))

        assert load(FlatMapReduce3LoadTest.halt(tasks)) == {:ok, {[], user.email}}

        assert load!(FlatMapReduce3LoadTest.halt(tasks)) ==
                 FlatMapReduce3LoadTest.halt(preloaded_tasks)
      end)
    end

    test "works for maps", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      task: task,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule FlatMapReduce3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.flat_map_reduce(map, [], fn {id, task}, acc ->
              {acc, [id, task.created_by.email | acc]}
            end)
          end

          @dx def: :original
          defd halt(map) do
            Enum.flat_map_reduce(map, [], fn {id, task}, acc ->
              {:halt, [id, task.created_by.email | acc]}
            end)
          end
        end

        assert load(FlatMapReduce3MapTest.run(%{})) == {:ok, {[], []}}

        assert load!(FlatMapReduce3MapTest.run(to_map(tasks))) ==
                 unload(FlatMapReduce3MapTest.run(to_map(preloaded_tasks)))

        assert load(FlatMapReduce3MapTest.halt(to_map(tasks))) ==
                 {:ok, {[], [task.id, user.email]}}

        assert load!(FlatMapReduce3MapTest.halt(to_map(tasks))) ==
                 unload(FlatMapReduce3MapTest.halt(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "frequencies_by/2" do
    test "works for lists", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule FrequenciesBy2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.frequencies_by(tasks, & &1.created_by.email)
          end
        end

        assert load(FrequenciesBy2LoadTest.run([])) == {:ok, %{}}

        assert load!(FrequenciesBy2LoadTest.run(tasks)) ==
                 unload(FrequenciesBy2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule FrequenciesBy2MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.frequencies_by(map, fn {_id, task} -> task.created_by.email end)
          end
        end

        assert load(FrequenciesBy2MapTest.run(%{})) == {:ok, %{}}

        assert load!(FrequenciesBy2MapTest.run(to_map(tasks))) ==
                 unload(FrequenciesBy2MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "group_by/2" do
    test "works for lists", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule GroupBy2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.group_by(tasks, & &1.created_by.email)
          end
        end

        assert load(GroupBy2LoadTest.run([])) == {:ok, %{}}

        assert load!(GroupBy2LoadTest.run(tasks)) ==
                 unload(GroupBy2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule GroupBy2MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.group_by(map, fn {_id, task} -> task.created_by.email end)
          end
        end

        assert load(GroupBy2MapTest.run(%{})) == {:ok, %{}}

        assert load!(GroupBy2MapTest.run(to_map(tasks))) ==
                 unload(GroupBy2MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "group_by/3" do
    test "works for lists", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule GroupBy3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.group_by(tasks, & &1.created_by.email, & &1.id)
          end
        end

        assert load(GroupBy3LoadTest.run([])) == {:ok, %{}}

        assert load!(GroupBy3LoadTest.run(tasks)) ==
                 unload(GroupBy3LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule GroupBy3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.group_by(map, fn {_id, task} -> task.created_by.email end, fn {id, _task} ->
              id
            end)
          end
        end

        assert load(GroupBy3MapTest.run(%{})) == {:ok, %{}}

        assert load!(GroupBy3MapTest.run(to_map(tasks))) ==
                 unload(GroupBy3MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "into/3" do
    test "works for lists", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule Into3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.into(tasks, call(MapSet.new()), & &1.created_by.email)
          end

          defp call(arg), do: arg
        end

        assert load(Into3LoadTest.run([])) == {:ok, MapSet.new()}
        assert load!(Into3LoadTest.run(tasks)) == Into3LoadTest.run(preloaded_tasks)
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule Into3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.into(map, call(MapSet.new()), fn {_id, task} -> task.created_by.email end)
          end

          defp call(arg), do: arg
        end

        assert load(Into3MapTest.run(%{})) == {:ok, MapSet.new()}

        assert load!(Into3MapTest.run(to_map(tasks))) == Into3MapTest.run(to_map(preloaded_tasks))
      end)
    end
  end

  describe "map/2" do
    test "works for identity function", %{list: list, tasks: tasks} do
      refute_stderr(fn ->
        defmodule MapIdentityTest do
          import Dx.Defd

          defd run(list) do
            Enum.map(list.tasks, fn task -> task end)
          end
        end

        assert load(MapIdentityTest.run(list)) == {:ok, tasks}
      end)
    end

    test "function calling other defd function", %{list: list, task_user_emails: task_user_emails} do
      refute_stderr(fn ->
        defmodule MapInlineFunTest do
          import Dx.Defd

          defd run(list) do
            Enum.map(list.tasks, fn task -> email(task) end)
          end

          defd email(task) do
            task.created_by.email
          end
        end

        assert load(MapInlineFunTest.run(list)) == {:ok, task_user_emails}
      end)
    end

    test "function calling non-defd function", %{list: list, task_user_ids: task_user_ids} do
      refute_stderr(fn ->
        defmodule MapInlineExternalFunTest do
          import Dx.Defd

          defd run(list) do
            Enum.map(list.tasks, fn task -> call(email(task)) end)
          end

          def email(task) do
            task.created_by_id
          end
        end

        assert load(MapInlineExternalFunTest.run(list)) == {:ok, task_user_ids}
      end)
    end

    test "works", %{list: list, tasks: tasks} do
      refute_stderr(fn ->
        defmodule Map2Test do
          import Dx.Defd

          defd run(list) do
            Enum.map(list.tasks, & &1.title)
          end
        end

        assert load(Map2Test.run(list)) == {:ok, Enum.map(tasks, & &1.title)}
      end)
    end

    test "loads association", %{list: list, task: task, task_user_emails: task_user_emails} do
      refute_stderr(fn ->
        defmodule MapAssocTest do
          import Dx.Defd

          defd run(list) do
            Enum.map(list.tasks, & &1.created_by.email)
          end
        end

        assert load(MapAssocTest.run(list)) == {:ok, task_user_emails}
      end)
    end

    test "Enum in fn", %{list: list, task: task, task_user_emails: task_user_emails} do
      refute_stderr(fn ->
        defmodule EnumInFnTest do
          import Dx.Defd

          defd run(list) do
            Enum.map([list], fn list ->
              Enum.map(list.tasks, & &1.created_by.email)
            end)
          end
        end

        assert load(EnumInFnTest.run(list)) == {:ok, [task_user_emails]}
      end)
    end
  end

  describe "map_every/3" do
    test "works for lists", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule MapEvery3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.map_every(tasks, 2, & &1.created_by.email)
          end
        end

        assert load(MapEvery3LoadTest.run([])) == {:ok, []}

        assert load!(MapEvery3LoadTest.run(tasks)) ==
                 unload(MapEvery3LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule MapEvery3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.map_every(map, 2, fn {_id, task} -> task.created_by.email end)
          end
        end

        assert load(MapEvery3MapTest.run(%{})) == {:ok, []}

        assert load!(MapEvery3MapTest.run(to_map(tasks))) ==
                 unload(MapEvery3MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "map_intersperse/3" do
    test "works for lists", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule MapIntersperse3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.map_intersperse(tasks, :bcc, & &1.created_by.email)
          end
        end

        assert load(MapIntersperse3LoadTest.run([])) == {:ok, []}

        assert load!(MapIntersperse3LoadTest.run(tasks)) ==
                 unload(MapIntersperse3LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule MapIntersperse3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.map_intersperse(map, :bcc, fn {_id, task} -> task.created_by.email end)
          end
        end

        assert load(MapIntersperse3MapTest.run(%{})) == {:ok, []}

        assert load!(MapIntersperse3MapTest.run(to_map(tasks))) ==
                 unload(MapIntersperse3MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "map_join/3" do
    test "works for lists", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule MapJoin3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.map_join(tasks, ", ", & &1.created_by.email)
          end
        end

        assert load(MapJoin3LoadTest.run([])) == {:ok, ""}

        assert load!(MapJoin3LoadTest.run(tasks)) ==
                 unload(MapJoin3LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for non-string entries", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule MapJoin3NonStringTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.map_join(tasks, ", ", & &1.created_by.id)
          end
        end

        assert load(MapJoin3NonStringTest.run([])) == {:ok, ""}

        assert load!(MapJoin3NonStringTest.run(tasks)) ==
                 unload(MapJoin3NonStringTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule MapJoin3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.map_join(map, ", ", fn {_id, task} -> task.created_by.email end)
          end
        end

        assert load(MapJoin3MapTest.run(%{})) == {:ok, ""}

        assert load!(MapJoin3MapTest.run(to_map(tasks))) ==
                 unload(MapJoin3MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "map_reduce/3" do
    test "works with loading data", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule MapReduce3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.map_reduce(tasks, [], &{&2, [&1.id, &1.created_by.email | &2]})
          end
        end

        assert load(MapReduce3LoadTest.run([])) == {:ok, {[], []}}

        assert load!(MapReduce3LoadTest.run(tasks)) ==
                 unload(MapReduce3LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule MapReduce3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.map_reduce(map, [], fn {id, task}, acc ->
              {acc, [id, task.created_by.email | acc]}
            end)
          end
        end

        assert load(MapReduce3MapTest.run(%{})) == {:ok, {[], []}}

        assert load!(MapReduce3MapTest.run(to_map(tasks))) ==
                 unload(MapReduce3MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "max/1" do
    test "compares DateTime structs", %{preloaded_users: preloaded_users, user: user} do
      refute_stderr(fn ->
        defmodule Max1StructTest do
          import Dx.Defd

          @dx def: :original
          defd run(datetimes) do
            Enum.max(datetimes)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Max1StructTest.run([]))
        end

        assert load(Max1StructTest.run(Enum.map(preloaded_users, & &1.verified_at))) ==
                 {:ok, user.verified_at}
      end)
    end
  end

  describe "max/2 with sorter" do
    test "works with loading data", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Please use max_by/3", fn ->
        defmodule Max2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.max(tasks, &(&1.created_by.email >= &2.created_by.email))
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Max2LoadTest.run([]))
        end

        assert load(Max2LoadTest.run(tasks)) == {:ok, task}
        assert load!(Max2LoadTest.run(tasks)) == unload(Max2LoadTest.run(preloaded_tasks))
      end)
    end

    test "compares DateTime structs", %{preloaded_users: preloaded_users, user2: user2} do
      refute_stderr(fn ->
        defmodule Max2StructTest do
          import Dx.Defd

          @dx def: :original
          defd run(datetimes) do
            Enum.max(datetimes, DateTime)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Max2StructTest.run([]))
        end

        assert load(Max2StructTest.run(Enum.map(preloaded_users, & &1.verified_at))) ==
                 {:ok, user2.verified_at}
      end)
    end

    test "works for maps and loading data", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Please use max_by/3", fn ->
        defmodule Max2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.max(tasks, fn {_, task1}, {_, task2} ->
              task1.created_by.email >= task2.created_by.email
            end)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Max2MapLoadTest.run(%{}))
        end

        assert load(Max2MapLoadTest.run(to_map(tasks))) == {:ok, {task.id, task}}

        assert load!(Max2MapLoadTest.run(to_map(tasks))) ==
                 unload(Max2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "max/2 with empty_fallback" do
    test "loads data in empty_fallback", %{
      task: task,
      preloaded_task: preloaded_task,
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule Max2EmptyFallbackLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.max(tasks, fn -> task.created_by.email end)
          end
        end

        assert load(Max2EmptyFallbackLoadTest.run([], task)) == {:ok, user.email}

        assert load!(Max2EmptyFallbackLoadTest.run([], task)) ==
                 Max2EmptyFallbackLoadTest.run([], preloaded_task)

        assert load!(Max2EmptyFallbackLoadTest.run(tasks, task)) ==
                 Max2EmptyFallbackLoadTest.run(tasks, preloaded_task)
      end)
    end
  end

  describe "max/3" do
    test "loads data in empty_fallback", %{
      task: task,
      preloaded_task: preloaded_task,
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Please use max_by/3", fn ->
        defmodule Max3EmptyLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.max(tasks, &(&1.created_by.email >= &2.created_by.email), fn ->
              task.created_by.email
            end)
          end
        end

        assert load(Max3EmptyLoadTest.run([], task)) == {:ok, user.email}

        assert load!(Max3EmptyLoadTest.run([], task)) ==
                 Max3EmptyLoadTest.run([], preloaded_task)

        assert load!(Max3EmptyLoadTest.run(tasks, task)) ==
                 unload(Max3EmptyLoadTest.run(preloaded_tasks, preloaded_task))
      end)
    end

    test "works for maps", %{
      task: task,
      preloaded_task: preloaded_task,
      task2: task2,
      preloaded_task2: preloaded_task2,
      user: user
    } do
      assert_stderr("Please use max_by/3", fn ->
        defmodule Max3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.max(map, &sorter/2)
          end

          @dx def: :original
          defd sorter(left, right) do
            left >= right
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Max3MapTest.run(%{}))
        end

        assert load!(Max3MapTest.run(%{a: task, b: task2})) ==
                 unload(Max3MapTest.run(%{a: preloaded_task, b: preloaded_task2}))
      end)
    end
  end

  describe "max_by/2" do
    test "loads data in mapper", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MaxBy2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.max_by(tasks, & &1.created_by.email)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(MaxBy2LoadTest.run([]))
        end

        assert load(MaxBy2LoadTest.run(tasks)) == {:ok, task}
        assert load!(MaxBy2LoadTest.run(tasks)) == unload(MaxBy2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps and loading data in mapper", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MaxBy2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.max_by(tasks, fn {_, task} -> task.created_by.email end)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(MaxBy2MapLoadTest.run(%{}))
        end

        assert load(MaxBy2MapLoadTest.run(to_map(tasks))) == {:ok, {task.id, task}}

        assert load!(MaxBy2MapLoadTest.run(to_map(tasks))) ==
                 unload(MaxBy2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "max_by/3 with sorter" do
    test "works for empty list and default args" do
      refute_stderr(fn ->
        defmodule MaxBy3EmptyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.max_by(tasks, & &1.created_by.email, &>=/2)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(MaxBy3EmptyTest.run([]))
        end
      end)
    end

    test "works for empty list and default empty_fallback" do
      assert_stderr("Dx can't load", fn ->
        defmodule MaxBy3EmptyTest2 do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.max_by(tasks, & &1.created_by.email, &sorter/2)
          end

          @dx def: :original
          defd sorter(a, b) do
            a >= b
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(MaxBy3EmptyTest2.run([]))
        end
      end)
    end

    test "loads data in sorter", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule MaxBy3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.max_by(tasks, & &1, &(&1.created_by.email >= &2.created_by.email))
          end
        end

        assert load(MaxBy3LoadTest.run(tasks)) == {:ok, task}
        assert load!(MaxBy3LoadTest.run(tasks)) == unload(MaxBy3LoadTest.run(preloaded_tasks))
      end)
    end

    test "loads and compares DateTime structs", %{tasks: tasks, task2: task2} do
      refute_stderr(fn ->
        defmodule MaxBy3LoadStructTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.max_by(tasks, & &1.created_by.verified_at, DateTime)
          end
        end

        assert load(MaxBy3LoadStructTest.run(tasks)) == {:ok, task2}
      end)
    end

    test "works for maps", %{
      task: task,
      preloaded_task: preloaded_task,
      task2: task2,
      preloaded_task2: preloaded_task2,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MaxBy3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.max_by(
              map,
              fn {_, task} -> task.created_by.email end,
              &call(simple(&1) >= simple(&2))
            )
          end

          def simple(arg) do
            arg
          end

          defp call(arg), do: arg
        end

        assert_raise Enum.EmptyError, fn ->
          load(MaxBy3MapTest.run(%{}))
        end

        assert load(MaxBy3MapTest.run(%{a: task, b: task2})) == {:ok, {:a, task}}

        assert load!(MaxBy3MapTest.run(%{a: task, b: task2})) ==
                 unload(MaxBy3MapTest.run(%{a: preloaded_task, b: preloaded_task2}))
      end)
    end
  end

  describe "max_by/3 with empty_fallback" do
    test "loads data in empty_fallback", %{task: task, preloaded_task: preloaded_task, user: user} do
      refute_stderr(fn ->
        defmodule MaxBy3EmptyFallbackLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.max_by(tasks, & &1.created_by.email, fn -> task.created_by.email end)
          end
        end

        assert load(MaxBy3EmptyFallbackLoadTest.run([], task)) == {:ok, user.email}

        assert load!(MaxBy3EmptyFallbackLoadTest.run([], task)) ==
                 MaxBy3EmptyFallbackLoadTest.run([], preloaded_task)
      end)
    end
  end

  describe "max_by/4" do
    test "loads data in sorter or empty_fallback", %{
      task: task,
      preloaded_task: preloaded_task,
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule MaxBy4LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.max_by(tasks, & &1, &(&1.created_by.email >= &2.created_by.email), fn ->
              task.created_by.email
            end)
          end
        end

        assert load(MaxBy4LoadTest.run([], task)) == {:ok, user.email}

        assert load!(MaxBy4LoadTest.run([], task)) ==
                 MaxBy4LoadTest.run([], preloaded_task)

        assert load!(MaxBy4LoadTest.run(tasks, task)) ==
                 unload(MaxBy4LoadTest.run(preloaded_tasks, preloaded_task))
      end)
    end

    test "works for maps and loads data in sorter or empty_fallback", %{
      task: task,
      preloaded_task: preloaded_task,
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule MaxBy4MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.max_by(tasks, &elem(&1, 1), &(&1.created_by.email >= &2.created_by.email), fn ->
              task.created_by.email
            end)
          end
        end

        assert load(MaxBy4MapLoadTest.run(%{}, task)) == {:ok, user.email}

        assert load!(MaxBy4MapLoadTest.run(%{}, task)) ==
                 MaxBy4MapLoadTest.run(%{}, preloaded_task)

        assert load!(MaxBy4MapLoadTest.run(to_map(tasks), task)) ==
                 unload(MaxBy4MapLoadTest.run(to_map(preloaded_tasks), preloaded_task))
      end)
    end
  end

  describe "min/1" do
    test "works for empty list and default args" do
      refute_stderr(fn ->
        defmodule Min1EmptyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min(tasks)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Min1EmptyTest.run([]))
        end
      end)
    end

    test "raises correct error" do
      assert_stderr("variable \"tasks\" does not exist", fn ->
        assert_raise CompileError, ~r/undefined function tasks\/0/, fn ->
          defmodule Min1ErrorTest do
            import Dx.Defd

            @dx def: :original
            defd run() do
              Enum.min(tasks)
            end
          end
        end
      end)
    end
  end

  describe "min/2 with sorter" do
    test "works for empty list and default args" do
      refute_stderr(fn ->
        defmodule Min2EmptyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min(tasks, &<=/2)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Min2EmptyTest.run([]))
        end
      end)
    end

    test "loads data in sorter", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule Min2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min(tasks, &(&1.created_by.email <= &2.created_by.email))
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Min2LoadTest.run([]))
        end

        assert load(Min2LoadTest.run(tasks)) == {:ok, task2}
        assert load!(Min2LoadTest.run(tasks)) == unload(Min2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{
      task: task,
      preloaded_task: preloaded_task,
      task2: task2,
      preloaded_task2: preloaded_task2,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule Min3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.min(map, fn {_, left}, {_, right} ->
              left.created_by.email <= right.created_by.email
            end)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Min3MapTest.run(%{}))
        end

        assert load!(Min3MapTest.run(%{a: task, b: task2})) ==
                 unload(Min3MapTest.run(%{a: preloaded_task, b: preloaded_task2}))
      end)
    end
  end

  describe "min/2 with empty_fallback" do
    test "loads data in empty_fallback", %{task: task, preloaded_task: preloaded_task, user: user} do
      refute_stderr(fn ->
        defmodule Min2EmptyFallbackLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.min(tasks, fn -> task.created_by.email end)
          end
        end

        assert load(Min2EmptyFallbackLoadTest.run([], task)) == {:ok, user.email}

        assert load!(Min2EmptyFallbackLoadTest.run([], task)) ==
                 Min2EmptyFallbackLoadTest.run([], preloaded_task)
      end)
    end
  end

  describe "min/3" do
    test "loads data in empty_fallback", %{task: task, preloaded_task: preloaded_task, user: user} do
      assert_stderr("Please use min_by/3", fn ->
        defmodule Min3EmptyLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.min(tasks, &(&1.created_by.email <= &2.created_by.email), fn ->
              task.created_by.email
            end)
          end
        end

        assert load(Min3EmptyLoadTest.run([], task)) == {:ok, user.email}

        assert load!(Min3EmptyLoadTest.run([], task)) ==
                 Min3EmptyLoadTest.run([], preloaded_task)
      end)
    end
  end

  describe "min_by/2" do
    test "works for lists", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MinBy2Test do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min_by(tasks, & &1.created_by.email)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(MinBy2Test.run([]))
        end

        assert load(MinBy2Test.run(tasks)) == {:ok, task2}
        assert load!(MinBy2Test.run(tasks)) == unload(MinBy2Test.run(preloaded_tasks))
      end)
    end
  end

  describe "min_by/3 with sorter" do
    test "works for empty list and default args", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule MinBy3MapperTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min_by(tasks, & &1.created_by.email, &<=/2)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(MinBy3MapperTest.run([]))
        end

        assert load(MinBy3MapperTest.run(tasks)) == {:ok, task2}
        assert load!(MinBy3MapperTest.run(tasks)) == unload(MinBy3MapperTest.run(preloaded_tasks))
      end)
    end

    test "works with loading data", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule MinBy3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min_by(tasks, & &1, &(&1.created_by.email <= &2.created_by.email))
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(MinBy3LoadTest.run([]))
        end

        assert load(MinBy3LoadTest.run(tasks)) == {:ok, task2}
        assert load!(MinBy3LoadTest.run(tasks)) == unload(MinBy3LoadTest.run(preloaded_tasks))
      end)
    end

    test "loads and compares DateTime structs", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      task: task
    } do
      refute_stderr(fn ->
        defmodule MinBy3LoadStructTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min_by(tasks, & &1.created_by.verified_at, DateTime)
          end
        end

        assert load(MinBy3LoadStructTest.run(tasks)) == {:ok, task}

        assert load!(MinBy3LoadStructTest.run(tasks)) ==
                 unload(MinBy3LoadStructTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{
      task: task,
      preloaded_task: preloaded_task,
      task2: task2,
      preloaded_task2: preloaded_task2,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MinBy3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.min_by(
              map,
              fn {_, task} -> task.created_by.email end,
              &call(simple(&1) <= simple(&2))
            )
          end

          def simple(arg) do
            arg
          end

          defp call(arg), do: arg
        end

        assert_raise Enum.EmptyError, fn ->
          load(MinBy3MapTest.run(%{}))
        end

        assert load(MinBy3MapTest.run(%{a: task, b: task2})) == {:ok, {:b, task2}}

        assert load!(MinBy3MapTest.run(%{a: task, b: task2})) ==
                 unload(MinBy3MapTest.run(%{a: preloaded_task, b: preloaded_task2}))
      end)
    end
  end

  describe "min_by/3 with empty_fallback" do
    test "loads data in empty_fallback", %{
      task: task,
      preloaded_task: preloaded_task,
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MinBy3EmptyFallbackLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.min_by(tasks, & &1.created_by.email, fn -> task.created_by.email end)
          end
        end

        assert load(MinBy3EmptyFallbackLoadTest.run([], task)) == {:ok, user.email}

        assert load!(MinBy3EmptyFallbackLoadTest.run([], task)) ==
                 MinBy3EmptyFallbackLoadTest.run([], preloaded_task)

        assert load!(MinBy3EmptyFallbackLoadTest.run(tasks, task)) ==
                 unload(MinBy3EmptyFallbackLoadTest.run(preloaded_tasks, preloaded_task))
      end)
    end
  end

  describe "min_by/4" do
    test "loads data in sorter or empty_fallback", %{
      task: task,
      preloaded_task: preloaded_task,
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule MinBy4LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.min_by(tasks, & &1, &(&1.created_by.email <= &2.created_by.email), fn ->
              task.created_by.email
            end)
          end
        end

        assert load(MinBy4LoadTest.run([], task)) == {:ok, user.email}

        assert load!(MinBy4LoadTest.run([], task)) ==
                 MinBy4LoadTest.run([], preloaded_task)

        assert load!(MinBy4LoadTest.run(tasks, task)) ==
                 unload(MinBy4LoadTest.run(preloaded_tasks, preloaded_task))
      end)
    end
  end

  describe "min_max/2" do
    test "loads data in empty_fallback", %{task: task, preloaded_task: preloaded_task, user: user} do
      refute_stderr(fn ->
        defmodule MinMax2EmptyLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.min_max(tasks, fn -> task.created_by.email end)
          end
        end

        assert load(MinMax2EmptyLoadTest.run([], task)) == {:ok, user.email}

        assert load!(MinMax2EmptyLoadTest.run([], task)) ==
                 MinMax2EmptyLoadTest.run([], preloaded_task)
      end)
    end
  end

  describe "min_max_by/2" do
    test "loads data in mapper function", %{
      tasks: tasks,
      task: task,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MinMaxBy2Test do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min_max_by(tasks, & &1.created_by.email)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(MinMaxBy2Test.run([]))
        end

        assert load(MinMaxBy2Test.run(tasks)) == {:ok, {task2, task}}

        assert load!(MinMaxBy2Test.run(tasks)) ==
                 unload(MinMaxBy2Test.run(preloaded_tasks))
      end)
    end
  end

  describe "min_max_by/3 with sorter" do
    test "loads data in sorter", %{
      task: task,
      preloaded_task: preloaded_task,
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule MinMaxBy3EmptyLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.min_max_by(tasks, & &1.created_by.email, &(simple(&1) <= simple(&2)), fn ->
              task.created_by.email
            end)
          end

          defd simple(arg) do
            arg
          end
        end

        assert load(MinMaxBy3EmptyLoadTest.run([], task)) == {:ok, user.email}

        assert load!(MinMaxBy3EmptyLoadTest.run([], task)) ==
                 MinMaxBy3EmptyLoadTest.run([], preloaded_task)

        assert load!(MinMaxBy3EmptyLoadTest.run(tasks, task)) ==
                 unload(MinMaxBy3EmptyLoadTest.run(preloaded_tasks, preloaded_task))
      end)
    end

    test "loads and compares DateTime structs", %{tasks: tasks, task: task, task2: task2} do
      refute_stderr(fn ->
        defmodule MinMaxBy3LoadStructTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min_max_by(tasks, & &1.created_by.verified_at, DateTime)
          end
        end

        assert load(MinMaxBy3LoadStructTest.run(tasks)) == {:ok, {task, task2}}
      end)
    end

    test "works for maps", %{
      task: task,
      preloaded_task: preloaded_task,
      task2: task2,
      preloaded_task2: preloaded_task2,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MinMaxBy3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.min_max_by(
              map,
              fn {_, task} -> task.created_by.email end,
              &call(simple(&1) <= simple(&2))
            )
          end

          def simple(arg) do
            arg
          end

          defp call(arg), do: arg
        end

        assert load(MinMaxBy3MapTest.run(%{a: task, b: task2})) ==
                 {:ok, {{:b, task2}, {:a, task}}}

        assert load!(MinMaxBy3MapTest.run(%{a: task, b: task2})) ==
                 unload(MinMaxBy3MapTest.run(%{a: preloaded_task, b: preloaded_task2}))
      end)
    end

    test "works for empty maps", %{
      task: task,
      preloaded_task: preloaded_task,
      task2: task2,
      preloaded_task2: preloaded_task2,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule MinMaxBy3EmptyMapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.min_max_by(
              map,
              fn {_, task} -> task.created_by.email end,
              &(simple(&1) <= simple(&2))
            )
          end

          defd simple(arg) do
            arg
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(MinMaxBy3EmptyMapTest.run(%{}))
        end
      end)
    end
  end

  describe "min_max_by/3 with empty_fallback" do
    test "loads data in empty_fallback", %{
      task: task,
      preloaded_task: preloaded_task,
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MinMaxBy3EmptyFallbackLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.min_max_by(tasks, & &1.id, fn -> task.created_by.email end)
          end
        end

        assert load(MinMaxBy3EmptyFallbackLoadTest.run([], task)) == {:ok, user.email}

        assert load!(MinMaxBy3EmptyFallbackLoadTest.run([], task)) ==
                 MinMaxBy3EmptyFallbackLoadTest.run([], preloaded_task)

        assert load!(MinMaxBy3EmptyFallbackLoadTest.run(tasks, task)) ==
                 unload(MinMaxBy3EmptyFallbackLoadTest.run(preloaded_tasks, preloaded_task))
      end)
    end
  end

  describe "min_max_by/4" do
    test "loads data in empty_fallback", %{task: task, preloaded_task: preloaded_task, user: user} do
      assert_stderr("load all needed data in the mapping function", fn ->
        defmodule MinMaxBy4LoadEmptyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, task) do
            Enum.min_max_by(tasks, & &1.id, &sorter/2, fn -> task.created_by.email end)
          end

          @dx def: :original
          defd sorter(a, b) do
            a < b
          end
        end

        assert load(MinMaxBy4LoadEmptyTest.run([], task)) == {:ok, user.email}

        assert load!(MinMaxBy4LoadEmptyTest.run([], task)) ==
                 MinMaxBy4LoadEmptyTest.run([], preloaded_task)
      end)
    end

    test "loads data in sorter", %{
      tasks: tasks,
      task: task,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("load all needed data in the mapping function", fn ->
        defmodule MinMaxBy4SorterLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min_max_by(
              tasks,
              & &1,
              &(&1.created_by.email < &2.created_by.email),
              fn ->
                :empty
              end
            )
          end
        end

        assert load(MinMaxBy4SorterLoadTest.run(tasks)) == {:ok, {task2, task}}

        assert load!(MinMaxBy4SorterLoadTest.run(tasks)) ==
                 unload(MinMaxBy4SorterLoadTest.run(preloaded_tasks))
      end)
    end

    test "loads and compares DateTime structs", %{tasks: tasks, task: task, task2: task2} do
      refute_stderr(fn ->
        defmodule MinMaxBy4LoadStructTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.min_max_by(tasks, & &1.created_by.verified_at, DateTime, fn -> :empty end)
          end
        end

        assert load(MinMaxBy4LoadStructTest.run(tasks)) == {:ok, {task, task2}}
      end)
    end

    test "works for maps", %{
      task: task,
      preloaded_task: preloaded_task,
      task2: task2,
      preloaded_task2: preloaded_task2,
      user: user
    } do
      refute_stderr(fn ->
        defmodule MinMaxBy4MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.min_max_by(
              map,
              fn {_, task} -> task.created_by.email end,
              &call(simple(&1) <= simple(&2)),
              fn -> :empty end
            )
          end

          def simple(arg) do
            arg
          end

          defp call(arg), do: arg
        end

        assert load(MinMaxBy4MapTest.run(%{})) == {:ok, :empty}

        assert load(MinMaxBy4MapTest.run(%{a: task, b: task2})) ==
                 {:ok, {{:b, task2}, {:a, task}}}

        assert load!(MinMaxBy4MapTest.run(%{a: task, b: task2})) ==
                 unload(MinMaxBy4MapTest.run(%{a: preloaded_task, b: preloaded_task2}))
      end)
    end
  end

  describe "reduce/2" do
    test "works with loading data", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule Reduce2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.reduce(tasks, &(&1.created_by.email > &2))
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Reduce2LoadTest.run([]))
        end

        assert load!(Reduce2LoadTest.run(tasks)) ==
                 unload(Reduce2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule Reduce2MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.reduce(map, fn {id, task}, acc ->
              task.created_by.email > acc
            end)
          end
        end

        assert_raise Enum.EmptyError, fn ->
          load(Reduce2MapTest.run(%{}))
        end

        assert load!(Reduce2MapTest.run(to_map(tasks))) ==
                 unload(Reduce2MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "reduce/3" do
    test "works with loading data", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule Reduce3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.reduce(tasks, [], &[&1.id, &1.created_by.email | &2])
          end
        end

        assert load(Reduce3LoadTest.run([])) == {:ok, []}

        assert load!(Reduce3LoadTest.run(tasks)) ==
                 unload(Reduce3LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule Reduce3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.reduce(map, [], fn {id, task}, acc ->
              [id, task.created_by.email | acc]
            end)
          end
        end

        assert load(Reduce3MapTest.run(%{})) == {:ok, []}

        assert load!(Reduce3MapTest.run(to_map(tasks))) ==
                 unload(Reduce3MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "reduce_while/3" do
    test "works with loading data", %{
      tasks: tasks,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule ReduceWhile3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd cont(tasks) do
            Enum.reduce_while(tasks, [], &{:cont, [&1.id, &1.created_by.email | &2]})
          end

          @dx def: :original
          defd halt(tasks) do
            Enum.reduce_while(tasks, [], &{:halt, [&1.id, &1.created_by.email | &2]})
          end
        end

        assert load(ReduceWhile3LoadTest.cont([])) == {:ok, []}

        assert load!(ReduceWhile3LoadTest.cont(tasks)) ==
                 unload(ReduceWhile3LoadTest.cont(preloaded_tasks))

        assert load!(ReduceWhile3LoadTest.halt(tasks)) ==
                 unload(ReduceWhile3LoadTest.halt(preloaded_tasks))
      end)
    end

    test "works for maps", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule ReduceWhile3MapTest do
          import Dx.Defd

          @dx def: :original
          defd cont(map) do
            Enum.reduce_while(map, [], fn {id, task}, acc ->
              {:cont, [id, task.created_by.email | acc]}
            end)
          end

          @dx def: :original
          defd halt(map) do
            Enum.reduce_while(map, [], fn {id, task}, acc ->
              {:halt, [id, task.created_by.email | acc]}
            end)
          end
        end

        assert load(ReduceWhile3MapTest.cont(%{})) == {:ok, []}

        assert load!(ReduceWhile3MapTest.cont(to_map(tasks))) ==
                 unload(ReduceWhile3MapTest.cont(to_map(preloaded_tasks)))

        assert load!(ReduceWhile3MapTest.halt(to_map(tasks))) ==
                 unload(ReduceWhile3MapTest.halt(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "reject/2" do
    test "works for different mapped values", %{
      tasks: [_ | other_tasks] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Reject2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.reject(tasks, &match?(%{created_at: %{email: "z" <> _}}, &1))
          end
        end

        assert load(Reject2LoadTest.run([])) == {:ok, []}
        assert load!(Reject2LoadTest.run([])) == Reject2LoadTest.run([])

        assert load!(Reject2LoadTest.run(tasks)) == unload(Reject2LoadTest.run(preloaded_tasks))
      end)
    end

    test "returns 0 results on uniformly truthy mapped value", %{
      tasks: [task | _] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Reject2LoadUniformTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.reject(tasks, & &1.created_by.email)
          end
        end

        assert load(Reject2LoadUniformTest.run(tasks)) == {:ok, []}

        assert load!(Reject2LoadUniformTest.run(tasks)) ==
                 unload(Reject2LoadUniformTest.run(preloaded_tasks))
      end)
    end

    test "returns input list on uniformly mapped value", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Reject2LoadTruthyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.reject(tasks, &is_nil(&1.created_by.email))
          end
        end

        assert load(Reject2LoadTruthyTest.run(tasks)) == {:ok, tasks}

        assert load!(Reject2LoadTruthyTest.run(tasks)) ==
                 unload(Reject2LoadTruthyTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{
      tasks: [_ | other_tasks] = tasks,
      preloaded_tasks: preloaded_tasks
    } do
      refute_stderr(fn ->
        defmodule Reject2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.reject(tasks, fn {_, task} -> match?(%{created_at: %{email: "z" <> _}}, task) end)
          end
        end

        assert load(Reject2MapLoadTest.run(%{})) == {:ok, []}
        assert load!(Reject2MapLoadTest.run(%{})) == Reject2MapLoadTest.run(%{})

        assert load!(Reject2MapLoadTest.run(to_map(tasks))) ==
                 unload(Reject2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "scan/2" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("Dx can't load", fn ->
        defmodule Scan2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.scan(tasks, &[&1.created_by.email, &2])
          end
        end

        assert load(Scan2LoadTest.run([])) == {:ok, []}

        assert load!(Scan2LoadTest.run(tasks)) == unload(Scan2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("Dx can't load", fn ->
        defmodule Scan2MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.scan(tasks, fn {_, task}, acc -> [task.created_by.email, acc] end)
          end
        end

        assert load(Scan2MapTest.run(%{})) == {:ok, []}

        assert load!(Scan2MapTest.run(to_map(tasks))) ==
                 unload(Scan2MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "scan/3" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("Dx can't load", fn ->
        defmodule Scan3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.scan(tasks, nil, &[&1.created_by.email, &2])
          end
        end

        assert load(Scan3LoadTest.run([])) == {:ok, []}

        assert load!(Scan3LoadTest.run(tasks)) == unload(Scan3LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("Dx can't load", fn ->
        defmodule Scan3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.scan(tasks, nil, fn {_, task}, acc -> [task.created_by.email, acc] end)
          end
        end

        assert load(Scan3MapTest.run(%{})) == {:ok, []}

        assert load!(Scan3MapTest.run(to_map(tasks))) ==
                 unload(Scan3MapTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "sort/2" do
    test "loads data in sorter", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("use sort_by/2", fn ->
        defmodule Sort2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort(tasks, &(&1.created_by.email >= &2.created_by.email))
          end
        end

        assert load(Sort2LoadTest.run([])) == {:ok, []}

        assert load!(Sort2LoadTest.run(tasks)) ==
                 unload(Sort2LoadTest.run(preloaded_tasks))
      end)
    end

    property "works for different sort orders", %{list: list} do
      assert_stderr("use sort_by/2", fn ->
        defmodule Sort2PropertyLoadTest do
          import Dx.Defd

          @dx def: :original
          defd asc(tasks) do
            Enum.sort(tasks, &(&1.created_by.email >= &2.created_by.email))
          end

          @dx def: :original
          defd desc(tasks) do
            Enum.sort(tasks, &(&1.created_by.email <= &2.created_by.email))
          end

          @dx def: :original
          defd asc_datetime(tasks) do
            Enum.sort(
              tasks,
              &call(DateTime.compare(&1.created_by.verified_at, &2.created_by.verified_at) != :gt)
            )
          end

          @dx def: :original
          defd desc_datetime(tasks) do
            Enum.sort(
              tasks,
              &call(DateTime.compare(&1.created_by.verified_at, &2.created_by.verified_at) != :lt)
            )
          end

          defp call(arg), do: arg
        end

        check all(
                task_attrs <- list_of(generator(:task, list), length: 10),
                sorter <- one_of([:asc, :desc, :asc_datetime, :desc_datetime])
              ) do
          preloaded_tasks = insert(task_attrs)
          tasks = unload(preloaded_tasks)

          case sorter do
            :asc ->
              assert load!(Sort2PropertyLoadTest.asc(tasks)) ==
                       unload(Sort2PropertyLoadTest.asc(preloaded_tasks))

            :desc ->
              assert load!(Sort2PropertyLoadTest.desc(tasks)) ==
                       unload(Sort2PropertyLoadTest.desc(preloaded_tasks))

            :asc_datetime ->
              assert load!(Sort2PropertyLoadTest.asc_datetime(tasks)) ==
                       unload(Sort2PropertyLoadTest.asc_datetime(preloaded_tasks))

            :desc_datetime ->
              assert load!(Sort2PropertyLoadTest.desc_datetime(tasks)) ==
                       unload(Sort2PropertyLoadTest.desc_datetime(preloaded_tasks))
          end
        end
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("use sort_by/2", fn ->
        defmodule Sort2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort(tasks, fn {_, task}, {_, task2} ->
              task.created_by.email >= task2.created_by.email
            end)
          end
        end

        assert load(Sort2MapLoadTest.run(%{})) == {:ok, []}

        assert load!(Sort2MapLoadTest.run(to_map(tasks))) ==
                 unload(Sort2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "sort_by/2" do
    test "loads data in mapper function", %{
      tasks: tasks,
      task: task,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule SortBy2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort_by(tasks, & &1.created_by.email)
          end
        end

        assert load(SortBy2LoadTest.run([])) == {:ok, []}

        assert load!(SortBy2LoadTest.run(tasks)) ==
                 unload(SortBy2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{
      tasks: tasks,
      task: task,
      task2: task2,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      refute_stderr(fn ->
        defmodule SortBy2MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort_by(tasks, fn {_, task} -> task.created_by.email end)
          end
        end

        assert load(SortBy2MapTest.run(%{})) == {:ok, []}

        assert load!(SortBy2MapTest.run(to_map(tasks))) ==
                 unload(SortBy2MapTest.run(to_map(preloaded_tasks)))
      end)
    end

    property "always works", %{list: list} do
      refute_stderr(fn ->
        defmodule SortBy2PropertyLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort_by(tasks, & &1.created_by.email)
          end
        end

        check all(task_attrs <- list_of(generator(:task, list), length: 10)) do
          preloaded_tasks = insert(task_attrs)
          tasks = unload(preloaded_tasks)

          assert load!(SortBy2PropertyLoadTest.run(tasks)) ==
                   unload(SortBy2PropertyLoadTest.run(preloaded_tasks))
        end
      end)
    end
  end

  describe "sort_by/3" do
    test "works for empty list and default args" do
      refute_stderr(fn ->
        defmodule SortBy3EmptyTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort_by(tasks, & &1.created_by.email, &>=/2)
          end
        end

        assert load(SortBy3EmptyTest.run([])) == {:ok, []}
      end)
    end

    test "works for empty list and :desc order" do
      refute_stderr(fn ->
        defmodule SortBy3DescTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort_by(tasks, & &1.created_by.email, :desc)
          end
        end

        assert load(SortBy3DescTest.run([])) == {:ok, []}
      end)
    end

    test "works for empty list and default empty_fallback" do
      assert_stderr("Dx can't load", fn ->
        defmodule SortBy3EmptyTest2 do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort_by(tasks, & &1.created_by.email, &sorter/2)
          end

          @dx def: :original
          defd sorter(a, b) do
            a >= b
          end
        end

        assert load(SortBy3EmptyTest2.run([])) == {:ok, []}
      end)
    end

    test "loads data in sorter", %{
      tasks: tasks,
      task: task,
      preloaded_tasks: preloaded_tasks,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule SortBy3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort_by(tasks, & &1, &(&1.created_by.email >= &2.created_by.email))
          end
        end

        assert load!(SortBy3LoadTest.run(tasks)) == unload(SortBy3LoadTest.run(preloaded_tasks))
      end)
    end

    test "loads and compares DateTime structs", %{
      tasks: tasks,
      preloaded_tasks: preloaded_tasks,
      task2: task2
    } do
      refute_stderr(fn ->
        defmodule SortBy3LoadStructTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort_by(tasks, & &1.created_by.verified_at, DateTime)
          end
        end

        assert load!(SortBy3LoadStructTest.run(tasks)) ==
                 unload(SortBy3LoadStructTest.run(preloaded_tasks))
      end)
    end

    test "loads data in empty_fallback", %{task: task, preloaded_task: preloaded_task, user: user} do
      assert_stderr("Dx can't load", fn ->
        defmodule SortBy3EmptyLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.sort_by(tasks, & &1.created_by.email, &(simple(&1) >= simple(&2)))
          end

          defd simple(arg) do
            arg
          end
        end

        assert load(SortBy3EmptyLoadTest.run([])) == {:ok, []}

        assert load!(SortBy3EmptyLoadTest.run([])) == SortBy3EmptyLoadTest.run([])
      end)
    end

    property "works for different sort orders", %{list: list} do
      refute_stderr(fn ->
        defmodule SortBy3PropertyLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, sorter) do
            Enum.sort_by(tasks, & &1.created_by.email, sorter)
          end
        end

        check all(
                task_attrs <- list_of(generator(:task, list), length: 10),
                sorter <- one_of([:asc, :desc])
              ) do
          preloaded_tasks = insert(task_attrs)
          tasks = unload(preloaded_tasks)

          assert load!(SortBy3PropertyLoadTest.run(tasks, sorter)) ==
                   unload(SortBy3PropertyLoadTest.run(preloaded_tasks, sorter))
        end
      end)
    end

    property "works for structs with different sort orders", %{list: list} do
      refute_stderr(fn ->
        defmodule SortBy3PropertyStructLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks, sorter) do
            Enum.sort_by(tasks, & &1.created_by.verified_at, sorter)
          end
        end

        check all(
                task_attrs <- list_of(generator(:task, list), length: 10),
                sorter <- one_of([DateTime, {:asc, DateTime}, {:desc, DateTime}])
              ) do
          preloaded_tasks = insert(task_attrs)
          tasks = unload(preloaded_tasks)

          assert load!(SortBy3PropertyStructLoadTest.run(tasks, sorter)) ==
                   unload(SortBy3PropertyStructLoadTest.run(preloaded_tasks, sorter))
        end
      end)
    end

    test "works for maps", %{
      task: task,
      preloaded_task: preloaded_task,
      task2: task2,
      preloaded_task2: preloaded_task2,
      user: user
    } do
      refute_stderr(fn ->
        defmodule SortBy3MapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.sort_by(
              map,
              fn {_, task} -> task.created_by.email end,
              &call(simple(&1) >= simple(&2))
            )
          end

          def simple(arg) do
            arg
          end

          defp call(arg), do: arg
        end

        assert load!(SortBy3MapTest.run(%{a: task, b: task2})) ==
                 unload(SortBy3MapTest.run(%{a: preloaded_task, b: preloaded_task2}))
      end)
    end

    test "works for empty maps", %{
      task: task,
      preloaded_task: preloaded_task,
      task2: task2,
      preloaded_task2: preloaded_task2,
      user: user
    } do
      assert_stderr("Dx can't load", fn ->
        defmodule SortBy3EmptyMapTest do
          import Dx.Defd

          @dx def: :original
          defd run(map) do
            Enum.sort_by(
              map,
              fn {_, task} -> task.created_by.email end,
              &(simple(&1) >= simple(&2))
            )
          end

          defd simple(arg) do
            arg
          end
        end

        assert load(SortBy3EmptyMapTest.run(%{})) == {:ok, []}
      end)
    end
  end

  describe "split_while/2" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule SplitWhile2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.split_while(tasks, & &1.created_by.email)
          end
        end

        assert load(SplitWhile2LoadTest.run([])) == {:ok, {[], []}}

        assert load!(SplitWhile2LoadTest.run(tasks)) ==
                 unload(SplitWhile2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for maps", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule SplitWhile2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.split_while(tasks, fn {_k, task} -> task.created_by.email end)
          end
        end

        assert load(SplitWhile2MapLoadTest.run(%{})) == {:ok, {[], []}}

        assert load!(SplitWhile2MapLoadTest.run(to_map(tasks))) ==
                 unload(SplitWhile2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "split_with/2" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule SplitWith2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.split_with(tasks, & &1.created_by.email)
          end
        end

        assert load(SplitWith2LoadTest.run([])) == {:ok, {[], []}}

        assert load!(SplitWith2LoadTest.run(tasks)) ==
                 unload(SplitWith2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for map", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule SplitWith2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.split_with(tasks, fn {_k, task} -> task.created_by.email end)
          end
        end

        assert load(SplitWith2MapLoadTest.run(%{})) == {:ok, {[], []}}

        assert load!(SplitWith2MapLoadTest.run(to_map(tasks))) ==
                 unload(SplitWith2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "take_while/2" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule TakeWhile2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.take_while(tasks, & &1.created_by.email)
          end
        end

        assert load(TakeWhile2LoadTest.run([])) == {:ok, []}

        assert load!(TakeWhile2LoadTest.run(tasks)) ==
                 unload(TakeWhile2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for map", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule TakeWhile2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.take_while(tasks, fn {_k, task} -> task.created_by.email end)
          end
        end

        assert load(TakeWhile2MapLoadTest.run(%{})) == {:ok, []}

        assert load!(TakeWhile2MapLoadTest.run(to_map(tasks))) ==
                 unload(TakeWhile2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "uniq_by/2" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule UniqBy2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.uniq_by(tasks, & &1.created_by.email)
          end
        end

        assert load(UniqBy2LoadTest.run([])) == {:ok, []}

        assert load!(UniqBy2LoadTest.run(tasks)) ==
                 unload(UniqBy2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for map", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule UniqBy2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.uniq_by(tasks, fn {_k, task} -> task.created_by.email end)
          end
        end

        assert load(UniqBy2MapLoadTest.run(%{})) == {:ok, []}

        assert load!(UniqBy2MapLoadTest.run(to_map(tasks))) ==
                 unload(UniqBy2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "with_index/2" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule WithIndex2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.with_index(tasks, &[&1.created_by.email, &2])
          end
        end

        assert load(WithIndex2LoadTest.run([])) == {:ok, []}

        assert load!(WithIndex2LoadTest.run(tasks)) ==
                 unload(WithIndex2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for map", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule WithIndex2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.with_index(tasks, fn {_k, task}, i -> [task.created_by.email, i] end)
          end
        end

        assert load(WithIndex2MapLoadTest.run(%{})) == {:ok, []}

        assert load!(WithIndex2MapLoadTest.run(to_map(tasks))) ==
                 unload(WithIndex2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "zip_reduce/3" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("Dx can't load", fn ->
        defmodule ZipReduce3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.zip_reduce([tasks, tasks], [], fn [task, task2], acc ->
              [task.created_by.email, task2.created_by.email | acc]
            end)
          end
        end

        assert load(ZipReduce3LoadTest.run([])) == {:ok, []}

        assert load!(ZipReduce3LoadTest.run(tasks)) ==
                 unload(ZipReduce3LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for map", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("Dx can't load", fn ->
        defmodule ZipReduce3MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.zip_reduce([tasks, tasks], [], fn [{_, task}, {_, task2}], acc ->
              [task.created_by.email, task2.created_by.email | acc]
            end)
          end
        end

        assert load(ZipReduce3MapLoadTest.run(%{})) == {:ok, []}

        assert load!(ZipReduce3MapLoadTest.run(to_map(tasks))) ==
                 unload(ZipReduce3MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "zip_reduce/4" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("Dx can't load", fn ->
        defmodule ZipReduce4LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.zip_reduce(tasks, tasks, [], fn task, task2, acc ->
              [task.created_by.email, task2.created_by.email | acc]
            end)
          end
        end

        assert load(ZipReduce4LoadTest.run([])) == {:ok, []}

        assert load!(ZipReduce4LoadTest.run(tasks)) ==
                 unload(ZipReduce4LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for map", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      assert_stderr("Dx can't load", fn ->
        defmodule ZipReduce4MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.zip_reduce(tasks, tasks, [], fn {_, task}, {_, task2}, acc ->
              [task.created_by.email, task2.created_by.email | acc]
            end)
          end
        end

        assert load(ZipReduce4MapLoadTest.run(%{})) == {:ok, []}

        assert load!(ZipReduce4MapLoadTest.run(to_map(tasks))) ==
                 unload(ZipReduce4MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "zip_with/2" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule ZipWith2LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.zip_with([tasks, tasks], fn [task, task2] ->
              [task.created_by.email, task2.created_by.email]
            end)
          end
        end

        assert load(ZipWith2LoadTest.run([])) == {:ok, []}

        assert load!(ZipWith2LoadTest.run(tasks)) ==
                 unload(ZipWith2LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for map", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule ZipWith2MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.zip_with([tasks, tasks], fn [{_, task}, {_, task2}] ->
              [task.created_by.email, task2.created_by.email]
            end)
          end
        end

        assert load(ZipWith2MapLoadTest.run(%{})) == {:ok, []}

        assert load!(ZipWith2MapLoadTest.run(to_map(tasks))) ==
                 unload(ZipWith2MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  describe "zip_with/3" do
    test "loads data in mapping function", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule ZipWith3LoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.zip_with(tasks, tasks, fn task, task2 ->
              [task.created_by.email, task2.created_by.email]
            end)
          end
        end

        assert load(ZipWith3LoadTest.run([])) == {:ok, []}

        assert load!(ZipWith3LoadTest.run(tasks)) ==
                 unload(ZipWith3LoadTest.run(preloaded_tasks))
      end)
    end

    test "works for map", %{tasks: tasks, preloaded_tasks: preloaded_tasks} do
      refute_stderr(fn ->
        defmodule ZipWith3MapLoadTest do
          import Dx.Defd

          @dx def: :original
          defd run(tasks) do
            Enum.zip_with(tasks, tasks, fn {_, task}, {_, task2} ->
              [task.created_by.email, task2.created_by.email]
            end)
          end
        end

        assert load(ZipWith3MapLoadTest.run(%{})) == {:ok, []}

        assert load!(ZipWith3MapLoadTest.run(to_map(tasks))) ==
                 unload(ZipWith3MapLoadTest.run(to_map(preloaded_tasks)))
      end)
    end
  end

  ### Generators

  defp generator(:user) do
    gen all(
          email <- generator(:email),
          verified_at <- generator(:narrow_date_time)
        ) do
      %User{email: email, verified_at: verified_at}
    end
  end

  defp generator(:email) do
    gen all(
          local <- string(:alphanumeric, min_length: 1),
          domain <- string(:alphanumeric, min_length: 1)
        ) do
      local <> to_string(System.unique_integer()) <> "@" <> domain
    end
  end

  defp generator(:narrow_date_time) do
    gen all(month <- StreamData.integer(1..12)) do
      DateTime.new!(Date.new!(2020, month, 20), Time.new!(20, 20, 20))
    end
  end

  defp generator(:task, list) do
    gen all(
          title <- string(:alphanumeric, min_length: 10),
          user <- generator(:user)
        ) do
      %Task{title: title, list: list, created_by: user}
    end
  end

  ### Helpers

  defp to_map(records) do
    Map.new(records, &{&1.id, &1})
  end

  defp insert(structs) do
    Enum.map(structs, &Dx.Test.Repo.insert!/1)
  end
end
