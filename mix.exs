defmodule ServerSentEventStage.MixProject do
  use Mix.Project

  def project do
    [
      app: :server_sent_event_stage,
      version: "1.2.0",
      elixir: ">= 1.11.4 and < 2.0.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ServerSentEventStage",
      description: "GenStage producer for ServerSentEvent endpoints",
      source_url: "https://github.com/mbta/server_sent_event_stage",
      docs: [main: "readme", extras: ["README.md", "LICENSE"]],
      package: package(),
      dialyzer: [
        plt_add_deps: :app_tree
      ],
      test_coverage: [tool: LcovEx]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gen_stage, "~> 1.1"},
      {:mint, "~> 1.4"},
      {:castore, "~> 0.1", optional: true},
      {:bypass, "~> 2.1", only: :test, optional: true},
      {:lcov_ex, "~> 0.2", only: :test, optional: true},
      {:credo, "~> 1.6", only: :dev, optional: true},
      {:dialyxir, "~> 1.1", only: :dev, optional: true},
      {:ex_doc, "~> 0.22", optional: true}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Paul Swartz <pswartz@mbta.com>"],
      links: %{
        "Github" => "https://github.com/mbta/server_sent_event_stage"
      },
      files: ~w(lib/**/*.ex mix.exs README.md LICENSE)
    ]
  end
end
