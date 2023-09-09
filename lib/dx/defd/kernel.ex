defmodule Dx.Defd.Kernel do
  alias Dx.Defd.Ast
  alias Dx.Defd.Compiler

  def rewrite({:&, meta, [{:/, [], [{{:., [], [:erlang, fun_name]}, [], []}, arity]}]}, state) do
    ast =
      cond do
        function_exported?(__MODULE__, fun_name, arity) ->
          args = Macro.generate_arguments(arity, __MODULE__)
          line = meta[:line] || state.line

          quote line: line do
            {:ok,
             fn unquote_splicing(args) ->
               unquote(__MODULE__).unquote(fun_name)(unquote_splicing(args))
             end}
          end

        true ->
          args = Macro.generate_arguments(arity, __MODULE__)
          line = meta[:line] || state.line

          quote line: line do
            {:ok,
             fn unquote_splicing(args) ->
               {:ok, unquote(:erlang).unquote(fun_name)(unquote_splicing(args))}
             end}
          end
      end

    {ast, state}
  end

  def rewrite({{:., meta, [:erlang, fun_name]}, meta2, args} = orig, state) do
    arity = length(args)

    {args, state} = Enum.map_reduce(args, state, &Compiler.normalize/2)

    ast =
      cond do
        Enum.all?(args, &Ast.ok?/1) ->
          args = Enum.map(args, &Ast.unwrap_inner/1)

          {:ok, {{:., meta, [:erlang, fun_name]}, meta2, args}}

        function_exported?(:erlang, fun_name, arity) ->
          Compiler.compile_error!(meta, state, """
          #{fun_name}/#{arity} is not supported by Dx yet.

          Please check the issues in the repo, upvote, comment, or create an issue for it.
          """)

        true ->
          orig
      end

    {ast, state}
  end
end
