locals_without_parens = [
  field_group: 1,
  import_rules: 1,
  infer: 1,
  infer: 2,
  infer_alias: 1,
  predicate_group: 1
]

[
  inputs: [
    "*.{ex,exs}",
    "lib/**/*.{ex,exs}",
    "test/{dx,support}/**/*.{ex,exs}",
    "test/*.{ex,exs}"
  ],
  import_deps: [:ecto, :stream_data],
  subdirectories: ["test/schema/migrations"],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
