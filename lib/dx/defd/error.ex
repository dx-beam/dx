defmodule Dx.Defd.Error do
  def filter_and_reraise(exception, stacktrace) do
    exception = replace_defd_refs(exception)

    stacktrace =
      stacktrace
      |> Enum.flat_map(fn
        {Dx, _, _, _} ->
          []

        {mod, fun_name, arity, meta} when is_integer(arity) ->
          defd_name = replace_defd_refs(fun_name)

          arity =
            if defd_name != fun_name do
              arity - 1
            else
              arity
            end

          [{mod, defd_name, arity, meta}]

        {mod, fun_name, args, meta} when is_list(args) ->
          defd_name = replace_defd_refs(fun_name)

          args =
            if defd_name != fun_name do
              # delete last arg (`eval`)
              args |> Enum.reverse() |> List.delete_at(0) |> Enum.reverse()
            else
              args
            end

          [{mod, defd_name, args, meta}]

        entry ->
          [entry]
      end)

    reraise exception, stacktrace
  end

  defp replace_defd_refs(%type{} = struct) do
    struct |> Map.from_struct() |> replace_defd_refs() |> then(&struct(type, &1))
  end

  defp replace_defd_refs(%{function: fun_name, arity: arity} = map) do
    defd_name = replace_defd_refs(fun_name)

    arity =
      if defd_name != fun_name do
        arity - 1
      else
        arity
      end

    %{map | function: defd_name, arity: arity}
    |> replace_defd_refs_in_map()
  end

  defp replace_defd_refs(map) when is_map(map) do
    replace_defd_refs_in_map(map)
  end

  defp replace_defd_refs(atom) when is_atom(atom) do
    case Atom.to_string(atom) do
      "__defd:" <> suffix ->
        suffix
        |> String.trim_trailing("__")
        |> String.to_existing_atom()

      _ ->
        atom
    end
  end

  defp replace_defd_refs(other) do
    other
  end

  defp replace_defd_refs_in_map(map) do
    Map.new(map, fn {k, v} -> {k, replace_defd_refs(v)} end)
  end
end
