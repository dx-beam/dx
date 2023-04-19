defmodule Dx.SchemaTest do
  use Dx.Test.DataCase

  doctest Dx.Schema, import: true

  describe "expand_mapping" do
    defmodule TaskRules do
      use Dx.Rules, for: Task

      infer completed?: false, when: %{completed_at: nil}
      infer completed?: true

      infer prev_dates:
              {&Date.range/2,
               [
                 {&Date.add/2, [{:ref, :due_on}, -1]},
                 {&Date.add/2, [{:ref, :due_on}, -7]}
               ], type: {:array, Date}}

      infer prev_tasks_1:
              {:map, :prev_dates, :due_on,
               {:query_one, Task,
                due_on: {:bound, :due_on}, created_by_id: {:ref, :created_by_id}}}

      infer prev_tasks_2:
              {:map, :prev_dates, {:bind, :due_on},
               {:query_one, Task,
                due_on: {:bound, :due_on}, created_by_id: {:ref, :created_by_id}}}

      infer prev_tasks_3:
              {:map, :prev_dates, {:bind, :due_on, %{}},
               {:query_one, Task,
                due_on: {:bound, :due_on}, created_by_id: {:ref, :created_by_id}}}
    end

    defmodule Rules do
      use Dx.Rules, for: List

      import_rules TaskRules

      infer archived?: true, when: %{archived_at: {:not, nil}}
      infer archived?: false

      infer state: :archived, when: %{archived?: true}
      infer state: :in_progress, when: %{tasks: %{completed?: true}}
      infer state: :ready, when: %{tasks: %{}}
      infer state: :empty
    end

    test "produces correct plan" do
      {expanded, type} = expand_result({:ref, :state}, List, extra_rules: Rules)

      assert expanded ==
               {:ref,
                [
                  {:predicate, %{name: :state},
                   [
                     archived: {
                       {:predicate, %{name: :archived?},
                        [
                          {true, {{:field, :archived_at}, {:not, nil}}},
                          {false, {:all, []}}
                        ]},
                       true
                     },
                     in_progress: {
                       {:assoc, :many, Task,
                        %{
                          name: :tasks,
                          ordered: false,
                          unique: true,
                          owner_key: :id,
                          related_key: :list_id
                        }},
                       {
                         {:predicate, %{name: :completed?},
                          [
                            {false, {{:field, :completed_at}, nil}},
                            {true, {:all, []}}
                          ]},
                         true
                       }
                     },
                     ready: {
                       {:assoc, :many, Task,
                        %{
                          name: :tasks,
                          ordered: false,
                          unique: true,
                          owner_key: :id,
                          related_key: :list_id
                        }},
                       {:all, []}
                     },
                     empty: {:all, []}
                   ]}
                ]}

      assert type == {:atom, [:archived, :in_progress, :ready, :empty]}
    end

    test "combines booleans" do
      {_expanded, type} = expand_result({:ref, :archived?}, List, extra_rules: Rules)

      assert type == :boolean
    end

    test "has_many type" do
      {_expanded, type} = expand_result({:ref, :tasks}, List, extra_rules: Rules)

      assert type == {:array, Task}
    end

    test "belongs_to type" do
      {_expanded, type} = expand_mapping(:list, Task, extra_rules: Rules)

      assert type == [List, nil]
    end

    test "map primitive" do
      {expanded, type} = expand_mapping(:prev_tasks_1, Task, extra_rules: Rules)

      assert expanded ==
               {:predicate, %{name: :prev_tasks_1},
                [
                  {{:map,
                    {:predicate, %{name: :prev_dates},
                     [
                       {{&Date.range/2,
                         [
                           {&Date.add/2, [{:ref, [{:field, :due_on}]}, -1]},
                           {&Date.add/2, [{:ref, [{:field, :due_on}]}, -7]}
                         ]}, {:all, []}}
                     ]}, :due_on,
                    {:query_one, Task,
                     [
                       {{:field, :due_on}, {:bound, :due_on}},
                       {{:field, :created_by_id}, {:ref, [{:field, :created_by_id}]}}
                     ]}}, {:all, []}}
                ]}

      assert type == [Task, nil]
    end
  end
end
