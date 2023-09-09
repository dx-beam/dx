defmodule Dx.Defd.KernelTest do
  use Dx.Test.DefdCase, async: false

  setup do
    user = create(User, %{role: %{name: "Assistant"}})
    list = create(List, %{created_by: user, hourly_points: 3.5})
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

  describe "+/2" do
    test "works", %{list: list, task: task} do
      defmodule PlusTest do
        import Dx.Defd

        defd add_one_hourly_point(list) do
          list.hourly_points + 1.0
        end
      end

      assert load(PlusTest.add_one_hourly_point(list)) == {:ok, 4.5}
    end
  end
end
