defmodule Dx.Defd.Compiler do
  alias Dx.Defd.Ast
  alias Dx.Defd.Util

  import Ast.Guards

  @rewriters %{
    Enum => Dx.Enum,
    :erlang => Dx.Defd.Kernel,
    Kernel => Dx.Defd.Kernel
  }

  @doc false
  def __compile__(%Macro.Env{module: module, file: file, line: line}, exports, eval_var) do
    defds = compile_prepare_arities(exports)

    state = %{
      module: module,
      file: file,
      line: line,
      function: nil,
      defds: defds,
      args: %{},
      eval_var: eval_var,
      in_call?: false,
      in_external?: false,
      in_fn?: false,
      is_loader?: false,
      data_reqs: %{},
      rewrite_underscore?: false
    }

    quoted = Enum.map(exports, &compile_each_defd(&1, state))

    {:__block__, [], quoted}
  end

  defp compile_prepare_arities(definitions) do
    for {{name, arity}, %{defaults: defaults}} <- definitions,
        arity <- (arity - map_size(defaults))..arity,
        into: MapSet.new(),
        do: {name, arity}
  end

  defp compile_each_defd({{name, arity} = def, def_meta}, state) do
    %{defaults: defaults, opts: opts} = def_meta

    all_args = Macro.generate_arguments(arity, __MODULE__)
    state = Map.put(state, :all_args, all_args)

    {{kind, meta, args, ast}, state} = get_and_normalize_defd(def, state)

    defd_name = Util.defd_name(name)

    defd_args =
      Enum.with_index(args, fn arg, i ->
        case defaults do
          %{^i => {meta, default}} -> {:\\, meta, [arg, default]}
          %{} -> arg
        end
      end) ++ [state.eval_var]

    entrypoint =
      case Keyword.get(opts, :def, :warn) do
        :warn ->
          Module.delete_definition(state.module, def)

          quote line: state.line do
            Kernel.unquote(kind)(unquote(name)(unquote_splicing(all_args))) do
              IO.warn("""
              Use Dx.load as entrypoint.
              """)

              Dx.Defd.load!(unquote(name)(unquote_splicing(all_args)))
            end
          end
          |> strip_definition_context()

        :no_warn ->
          Module.delete_definition(state.module, def)

          quote line: state.line do
            Kernel.unquote(kind)(unquote(name)(unquote_splicing(all_args))) do
              Dx.Defd.load!(unquote(name)(unquote_splicing(all_args)))
            end
          end
          |> strip_definition_context()

        :original ->
          quote do
          end

        invalid ->
          compile_error!(meta, state, "Invalid option @dx def: #{inspect(invalid)}")
      end

    impl =
      quote line: state.line do
        Kernel.unquote(kind)(unquote(defd_name)(unquote_splicing(defd_args))) do
          unquote(ast)
        end
      end

    {entrypoint, impl}
  end

  # If the definition has a context, we don't warn when it goes unused,
  # so we remove the context as we want to keep the original semantics.
  defp strip_definition_context({kind, meta, [signature, block]}) do
    {kind, meta, [Macro.update_meta(signature, &Keyword.delete(&1, :context)), block]}
  end

  defp get_and_normalize_defd({name, arity} = def, state) do
    {:v1, kind, meta, clauses} = Module.get_definition(state.module, def)

    state = %{state | function: def, line: meta[:line] || state.line, rewrite_underscore?: true}

    type_str = if kind == :def, do: "defd", else: "defdp"

    case clauses do
      [] ->
        compile_error!(meta, state, "cannot have #{type_str} #{name}/#{arity} without clauses")

      [{meta, args, [], ast}] ->
        # {args, state} = normalize_args(args, meta, state)
        {ast, state} =
          Ast.with_args(args, state, fn state ->
            normalize(ast, %{state | rewrite_underscore?: false})
          end)

        if not Enum.empty?(state.data_reqs) do
          compile_error!(meta, state, """
          Remaining state.data_reqs at function root level:

          #{inspect(state.data_reqs, pretty: true)}
          """)
        end

        {{kind, meta, args, ast}, state}

      [{meta, _args, _, _} | _] = clauses ->
        case_clauses =
          Enum.map(clauses, fn {meta, args, [], ast} ->
            {:->, meta, [[Ast.wrap_args(args)], ast]}
          end)

        line = meta[:line] || state.line
        case_ast = {:case, [line: line], [Ast.wrap_args(state.all_args), [do: case_clauses]]}

        {ast, state} = Dx.Defd.Case.normalize(case_ast, state)

        {{kind, meta, state.all_args, ast}, state}
    end
  end

  def normalize(ast, state) when is_simple(ast) do
    ast = {:ok, ast}
    {ast, state}
  end

  # []
  def normalize([], state) do
    {{:ok, []}, state}
  end

  # [...]
  def normalize(ast, state) when is_list(ast) do
    {ast, state} = Enum.map_reduce(ast, state, &normalize/2)

    ast =
      case Dx.Defd.Result.collect_ok(ast) do
        {:ok, ast} ->
          # unwrapped at compile-time
          {:ok, ast}

        :error ->
          # unwrap at runtime
          line =
            case ast do
              [{_, meta, _} | _] -> meta[:line] || state.line
              _other -> state.line
            end

          quote line: line do
            Dx.Defd.Result.collect(unquote(ast))
          end
      end

    {ast, state}
  end

  # {_, _}
  def normalize({elem_0, elem_1}, state) do
    ast = [elem_0, elem_1]
    {ast, state} = Enum.map_reduce(ast, state, &normalize/2)

    ast =
      case Dx.Defd.Result.collect_ok(ast) do
        {:ok, [elem_0, elem_1]} ->
          # unwrapped at compile-time
          {:ok, {elem_0, elem_1}}

        :error ->
          # unwrap at runtime
          quote do
            Dx.Defd.Result.collect(unquote(ast))
            |> Dx.Defd.Result.transform(fn [e0, e1] -> {e0, e1} end)
          end
      end

    {ast, state}
  end

  # {...}
  def normalize({:{}, meta, elems}, state) do
    {ast, state} = Enum.map_reduce(elems, state, &normalize/2)

    ast =
      case Dx.Defd.Result.collect_ok(ast) do
        {:ok, list} ->
          # unwrapped at compile-time
          {:ok, {:{}, meta, list}}

        :error ->
          # unwrap at runtime
          line = meta[:line] || state.line

          quote line: line do
            Dx.Defd.Result.collect(unquote(ast))
            |> Dx.Defd.Result.transform(&List.to_tuple/1)
          end
      end

    {ast, state}
  end

  def normalize(var, state) when is_var(var) do
    if state.in_external? and state.in_fn? do
      {var, state}
    else
      {{:ok, var}, state}
    end
  end

  def normalize({:call, _meta, [ast]}, state) do
    {ast, new_state} = normalize(ast, %{state | in_call?: true})
    {ast, %{new_state | in_call?: state.in_call?}}
  end

  def normalize({:fn, meta, [{:->, meta2, [args, body]}]}, state) do
    {body, new_state} =
      Ast.with_args(args, %{state | in_fn?: true}, fn state ->
        normalize(body, state)
      end)

    ast = {:ok, {:fn, meta, [{:->, meta2, [args, body]}]}}
    {ast, %{new_state | in_fn?: state.in_fn?}}
  end

  # fun.()
  def normalize({{:., meta, [module]}, meta2, args}, state) do
    {module, state} = normalize(module, state)
    module = Ast.unwrap(module)

    {ast, new_state} =
      normalize_call_args(args, %{state | in_external?: true}, fn args ->
        {{:., meta, [module]}, meta2, args}
      end)
      |> Ast.ok()

    {ast, %{new_state | in_external?: state.in_external?}}
  end

  def normalize({:case, _meta, _args} = ast, state) do
    Dx.Defd.Case.normalize(ast, state)
  end

  def normalize({fun_name, meta, args} = fun, state)
      when is_atom(fun_name) and is_list(args) do
    arity = length(args)

    cond do
      {fun_name, arity} in state.defds ->
        defd_name = Util.defd_name(fun_name)

        normalize_call_args(args, state, fn args ->
          {defd_name, meta, args ++ [state.eval_var]}
        end)

      Util.has_function?(state.module, fun_name, arity) ->
        if not state.in_call? do
          warn(meta, state, """
          #{fun_name}/#{arity} is not defined with defd.

          Either define it using defd (preferred) or wrap the call in the call/1 function:

              call(#{fun_name}(...))
          """)
        end

        {ast, new_state} =
          normalize_call_args(args, %{state | in_external?: true}, fn args ->
            {fun_name, meta, args}
          end)
          |> Ast.ok()

        {ast, %{new_state | in_external?: state.in_external?}}

      true ->
        {fun, state}
    end
  end

  def normalize({{:., meta, [module, fun_name]}, meta2, args} = fun, state)
      when is_atom(fun_name) and is_list(args) do
    arity = length(args)

    cond do
      # Access.get/2
      meta2[:no_parens] ->
        case maybe_capture_loader(fun, state) do
          {:ok, loader_ast, state} ->
            state =
              Map.update!(state, :data_reqs, fn data_reqs ->
                Map.put_new(data_reqs, loader_ast, Macro.unique_var(:data, __MODULE__))
              end)

            var = state.data_reqs[loader_ast]
            ast = if state.in_external? and state.in_fn?, do: var, else: {:ok, var}

            {ast, state}

          :error ->
            {module, state} = normalize(module, state)

            fun =
              if state.in_fn? do
                {{:., meta, [module, fun_name]}, meta2, []}
              else
                Ast.fetch(module, fun_name, state.eval_var, meta[:line] || state.line)
              end

            {fun, state}
        end

      # function call on dynamically computed module
      not is_atom(module) ->
        normalize_call_args(args, state, fn args ->
          quote do
            Dx.Defd.Util.maybe_call_defd(
              unquote(module),
              unquote(fun_name),
              unquote(args),
              unquote(state.eval_var)
            )
          end
        end)

      rewriter = @rewriters[module] ->
        rewriter.rewrite(fun, state)

      Util.is_defd?(module, fun_name, arity) ->
        defd_name = Util.defd_name(fun_name)

        normalize_call_args(args, state, fn args ->
          {{:., meta, [module, defd_name]}, meta2, args ++ [state.eval_var]}
        end)

      Util.has_function?(module, fun_name, arity) ->
        if not state.in_call? do
          warn(meta2, state, """
          #{inspect(module)}.#{fun_name}/#{arity} is not defined with defd.

          Either define it using defd (preferred) or wrap the call in the call/1 function:

              call(#{inspect(module)}.#{fun_name}(...))
          """)
        end

        {ast, new_state} =
          normalize_call_args(args, %{state | in_external?: true}, fn args ->
            {{:., meta, [module, fun_name]}, meta2, args}
          end)
          |> Ast.ok()

        {ast, %{new_state | in_external?: state.in_external?}}

      Code.ensure_loaded?(module) ->
        compile_error!(
          meta,
          state,
          "undefined function #{fun_name}/#{arity} (expected #{inspect(module)} to define such a function, but none are available)"
        )

        {fun, state}

      true ->
        compile_error!(
          meta,
          state,
          "undefined function #{fun_name}/#{arity} (module #{inspect(module)} does not exist)"
        )

        {fun, state}
    end
  end

  def normalize({_, meta, _} = ast, state) do
    compile_error!(meta, state, """
    This syntax is not supported yet:

    #{Macro.to_string(ast)}
    """)
  end

  # Access.get/2
  def maybe_capture_loader({{:., meta, [ast, fun_name]}, meta2, []}, state)
      when is_atom(fun_name) do
    if meta2[:no_parens] do
      case maybe_capture_loader(ast, state) do
        {:ok, ast, state} ->
          fun = Ast.fetch(ast, fun_name, state.eval_var, meta[:line] || state.line)
          {:ok, fun, state}

        :error ->
          :error
      end
    else
      :error
    end
  end

  def maybe_capture_loader(var, state) when is_var(var) do
    if Map.has_key?(state.args, Ast.var_id(var)) do
      {:ok, {:ok, var}, state}
    else
      :error
    end
  end

  def maybe_capture_loader(_ast, _state) do
    :error
  end

  def normalize_call_args(args, state = %{in_external?: true, in_fn?: true}, fun) do
    {args, state} = Enum.map_reduce(args, state, &normalize/2)
    call_args = args |> fun.()

    {call_args, state}
  end

  def normalize_call_args(args, state, fun) do
    {args, state} = Enum.map_reduce(args, state, &normalize/2)

    {args, defd_reqs} =
      Enum.map_reduce(args, %{}, fn
        {:ok, ast}, reqs ->
          {ast, reqs}

        loader, reqs ->
          reqs = Map.put_new(reqs, loader, Macro.unique_var(:data, __MODULE__))
          var = reqs[loader]
          {var, reqs}
      end)

    call_args = args |> fun.()
    ast = Ast.ensure_loaded(call_args, defd_reqs)

    {ast, state}
  end

  ## Helpers

  def compile_error!(meta, state, description) do
    line = meta[:line] || state.line
    raise CompileError, line: line, file: state.file, description: description
  end

  def warn(meta, state, message) do
    line = meta[:line] || state.line
    {name, arity} = state.function
    entry = {state.module, name, arity, [file: String.to_charlist(state.file), line: line]}
    IO.warn(message, [entry])
  end
end
