defmodule Dx.RefBranchingTest do
  use Dx.Test.DataCase, async: true

  setup do
    list = create(List, %{created_by: %{}})

    tasks =
      for i <- 1..3,
          do:
            create(Task, %{
              list_id: list.id,
              title: "Todo #{i}",
              due_on: today(i),
              created_by: %{last_name: "User #{i}"}
            })

    [list: list, tasks: tasks]
  end

  test "Ref on list returns a list of values", %{list: list, tasks: tasks} do
    assert Dx.load!(list, {:ref, :tasks}) == unload(tasks)
  end

  test "Ref on field within a list returns a list of the field's values", %{
    list: list,
    tasks: tasks
  } do
    assert Dx.load!(list, {:ref, [:tasks, :title]}) == Enum.map(tasks, & &1.title)
  end

  test "Ref on field within a nested list returns a nested list of the field's values", %{
    list: list,
    tasks: tasks
  } do
    assert Dx.load!([list], {:ref, [:tasks, :title]}) == [Enum.map(tasks, & &1.title)]
  end

  test "Ref on fields within list returns a nested list of these fields' values", %{
    list: list,
    tasks: tasks
  } do
    assert Dx.load!(list, {:ref, [:tasks, [:title, :due_on]]}) ==
             Enum.map(tasks, &Map.take(&1, [:title, :due_on]))
  end

  test "Ref on fields map within list returns a nested list of these fields' values", %{
    list: list,
    tasks: tasks
  } do
    assert Dx.load!(list, {:ref, [:tasks, %{title: :title, due_on: :due_on}]}) ==
             Enum.map(tasks, &Map.take(&1, [:title, :due_on]))
  end

  test "Ref on nested fields map within list returns a nested list of these fields' values", %{
    list: list,
    tasks: tasks
  } do
    ref_path = [
      :tasks,
      %{title: :title, due_on: :due_on, created_by_last_name: [:created_by, :last_name]}
    ]

    expected =
      Enum.map(
        tasks,
        &%{title: &1.title, due_on: &1.due_on, created_by_last_name: &1.created_by.last_name}
      )

    assert Dx.load!(list, {:ref, ref_path}) == expected
  end
end
