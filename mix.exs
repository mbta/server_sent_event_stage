defmodule ServerSentEventStage.MixProject do
  use Mix.Project

  def project do
    [
      app: :server_sent_event_stage,
      version: "0.4.1",
      elixir: "~> 1.6",
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
      {:gen_stage, "~> 0.13"},
      {:httpoison, "~> 1.1"},
      {:bypass, "~> 0.8", only: :test, optional: true},
      {:excoveralls, "~> 0.8", only: :test, optional: true},
      {:ex_doc, "~> 0.18", optional: true}
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
