defmodule Dx.Util.Keyword do
  def deep_merge(left, right) do
    Keyword.merge(left, right, &deep_resolve/3)
  end

  # Key exists in both lists, and both values are lists as well.
  # These can be merged recursively.
  defp deep_resolve(_key, left = [{_, _} | _], right = [{_, _} | _]) do
    deep_merge(left, right)
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a list. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end
end
