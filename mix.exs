defmodule Dx.MixProject do
  use Mix.Project

  @source_url "https://github.com/dx-beam/dx"
  @version "0.3.0"

  def project do
    [
      app: :dx,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      aliases: aliases(),
      deps: deps(),
      docs: docs()
    ]
  end

  defp package do
    [
      description: "Inference engine written in Elixir",
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Arno Dirlam"],
      licenses: ["MIT"],
      links: %{
        Changelog: @source_url <> "/blob/main/CHANGELOG.md",
        GitHub: @source_url
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger] ++ test_apps(Mix.env())
    ]
  end

  defp test_apps(:test) do
    [:ecto_sql, :postgrex]
  end

  defp test_apps(_), do: []

  defp deps do
    [
      # util
      {:typed_struct, ">= 0.0.0"},
      {:dataloader, "~> 1.0.0"},

      # adapters
      {:ecto, ">= 3.4.3 and < 4.0.0", optional: true},
      {:ecto_sql, "~> 3.0", optional: true},

      # dev & test
      {:postgrex, "~> 0.14", only: :test, runtime: false},
      {:timex, "~> 3.6", only: :test, runtime: false},
      {:refinery, "~> 0.1.0", github: "dx-beam/refinery", only: :test},
      {:stream_data, "~> 0.6", only: [:dev, :test]},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end

  def docs do
    [
      extra_section: "Guides",
      api_reference: false,
      extras: Path.wildcard("docs/**/*.md"),
      groups_for_extras: [
        Basics: Path.wildcard("docs/basics/*.md")
      ],
      main: "welcome",
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.reset", "test"]
    ]
  end
end
