defmodule ServerSentEventStage.MixProject do
  use Mix.Project

  def project do
    [
      app: :server_sent_event_stage,
      version: "1.0.0",
      elixir: "~> 1.6 or ~> 1.7 or ~> 1.8 or ~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ServerSentEventStage",
      description: "GenStage producer for ServerSentEvent endpoints",
      source_url: "https://github.com/mbta/server_sent_event_stage",
      docs: [main: "readme", extras: ["README.md"]],
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.html": :test, "coveralls.json": :test]
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
      {:gen_stage, "~> 0.14"},
      {:mint, "~> 1.0"},
      {:castore, "~> 0.1", optional: true},
      {:bypass, "~> 1.0", only: :test, optional: true},
      {:excoveralls, "~> 0.12", only: :test, optional: true},
      {:ex_doc, "~> 0.21", optional: true}
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
