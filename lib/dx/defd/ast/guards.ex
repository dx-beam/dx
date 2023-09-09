defmodule Dx.Defd.Ast.Guards do
  defguard is_var(var)
           when is_tuple(var) and tuple_size(var) == 3 and is_atom(elem(var, 0)) and
                  is_atom(elem(var, 2))

  defguard is_simple(val)
           when is_integer(val) or is_float(val) or is_atom(val) or is_binary(val) or
                  is_boolean(val) or is_nil(val) or is_struct(val)
end
