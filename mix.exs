defmodule Amap.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/gilbertwong96/amap"

  def project do
    [
      app: :amap,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "Amap",
      description: "Amap (高德地图) Web API client, including Falcon track service",
      source_url: @source_url,
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Amap.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:finch, "~> 0.19"},
      {:telemetry, "~> 1.0"},
      {:bypass, "~> 2.1", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [main: "Amap", source_ref: "v#{@version}", source_url: @source_url]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end
end
