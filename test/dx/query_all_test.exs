defmodule Dx.QueryAllTest do
  use Dx.Test.DataLoadingCase

  defmodule Rules do
    use Dx.Rules, for: Task

    infer prev_two_tasks:
            {:query_all, Task,
             [
               created_by_id: {:ref, :created_by_id},
               due_on:
                 {&Enum.to_list/1,
                  {&Date.range/2,
                   [{&Date.add/2, [{:ref, :due_on}, -20]}, {&Date.add/2, [{:ref, :due_on}, -1]}]}}
             ], order_by: [desc: :due_on], limit: 2}
  end

  setup do
    user = create(User)
    list = create(List, %{created_by_id: user.id})

    tasks =
      for date_offset <- 0..3 do
        create(Task, %{due_on: today(date_offset), list_id: list.id, created_by_id: user.id})
      end

    [tasks: tasks]
  end

  test "returns 2 prev_two_tasks for newest task", %{tasks: tasks} do
    task = tasks |> Enum.max_by(& &1.due_on, Date)

    expected =
      tasks
      |> Enum.filter(&Timex.between?(&1.due_on, Date.add(task.due_on, -21), task.due_on))
      |> Enum.sort_by(& &1.due_on, {:desc, Date})
      |> Enum.take(2)

    assert Dx.load!(task, :prev_two_tasks, extra_rules: Rules) == expected

    assert_received {:ecto_query, %{source: nil, result: {:ok, %{num_rows: 2}}}}
    refute_received {:ecto_query, %{source: nil}}
    refute_received {:ecto_query, %{source: "tasks"}}
  end

  test "returns 2 prev_two_tasks for second-newest task", %{tasks: tasks} do
    [_, task | _] = tasks |> Enum.sort_by(& &1.due_on, {:desc, Date})

    expected =
      tasks
      |> Enum.filter(&Timex.between?(&1.due_on, Date.add(task.due_on, -21), task.due_on))
      |> Enum.sort_by(& &1.due_on, {:desc, Date})
      |> Enum.take(2)

    assert Dx.load!(task, :prev_two_tasks, extra_rules: Rules) == expected

    assert_received {:ecto_query, %{source: nil, result: {:ok, %{num_rows: 2}}}}
    refute_received {:ecto_query, %{source: nil}}
    refute_received {:ecto_query, %{source: "tasks"}}
  end

  test "returns 1 prev_two_tasks for third-newest task", %{tasks: tasks} do
    [_, _, task | _] = tasks |> Enum.sort_by(& &1.due_on, {:desc, Date})

    expected =
      tasks
      |> Enum.filter(&Timex.between?(&1.due_on, Date.add(task.due_on, -21), task.due_on))
      |> Enum.sort_by(& &1.due_on, {:desc, Date})
      |> Enum.take(2)

    assert Dx.load!(task, :prev_two_tasks, extra_rules: Rules) == expected

    assert_received {:ecto_query, %{source: nil, result: {:ok, %{num_rows: 1}}}}
    refute_received {:ecto_query, %{source: nil}}
    refute_received {:ecto_query, %{source: "tasks"}}
  end
end
