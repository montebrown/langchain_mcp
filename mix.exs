defmodule LangChainMCP.MixProject do
  use Mix.Project

  @source_url "https://github.com/montebrown/langchain_mcp"
  @version "0.1.0"

  def project do
    [
      app: :langchain_mcp,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: """
      Model Context Protocol (MCP) integration for LangChain Elixir.
      Enables LangChain to use MCP servers as tool providers.
      """,
      dialyzer: [plt_add_apps: [:mix]],
      docs: docs(),
      homepage_url: @source_url,
      name: "LangChain MCP",
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies
      {:langchain, "~> 0.4.0"},
      {:anubis_mcp, "~> 0.16.0"},

      # HTTP server for test server
      {:plug, "~> 1.15", optional: true},
      {:bandit, "~> 1.0", optional: true},

      # Dev/Test dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.10", only: :test}
    ]
  end

  defp package do
    [
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "LangChain" => "https://github.com/brainlid/langchain"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Core: [
          LangChain.MCP.Adapter,
          LangChain.MCP.Config
        ],
        Converters: [
          LangChain.MCP.SchemaConverter,
          LangChain.MCP.ContentMapper
        ],
        Execution: [
          LangChain.MCP.ToolExecutor,
          LangChain.MCP.ErrorHandler
        ]
      ]
    ]
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end
end
