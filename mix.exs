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
      aliases: aliases(),
      dialyzer: dialyzer(),
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

  # The CI aliases and `mix integration` run in the test environment: `mix test`
  # refuses to run from inside another Mix command while the environment is not
  # `:test`, and the compile/format/credo steps behave identically either way.
  def cli do
    [preferred_envs: [ci: :test, "ci.fast": :test, integration: :test]]
  end

  # `mix ci.fast` is the inner loop: fast enough to run on every save. `mix ci`
  # adds the slow static analysis and is what CI runs.
  defp aliases do
    [
      "ci.fast": [
        "cmd mix compile --all-warnings --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test --warnings-as-errors"
      ],
      ci: [
        "cmd mix compile --all-warnings --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "deps.unlock --check-unused",
        "cmd mix hex.audit",
        "xref graph --label compile-connected --fail-above 5",
        "dialyzer",
        "ex_dna",
        "reach.check --dead-code --smells",
        "test --warnings-as-errors"
      ],
      integration: &integration/1
    ]
  end

  # A plain alias would run `test --only integration` with every check skipped
  # when AMAP_KEY is unset and exit 0 — a green run that proves nothing. The
  # function makes that a loud failure before the tests start.
  defp integration(args) do
    if System.get_env("AMAP_KEY") in [nil, ""] do
      Mix.raise("""
      AMAP_KEY is not set, so the integration tests have no key to call Amap with.

      They hit the live service and spend real quota. Set the variable and rerun:

          AMAP_KEY=… mix integration

      Without a key every check would skip, and the run would exit green.
      """)
    end

    Mix.Task.run("test", ["--only", "integration" | args])
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # `test/support` is compiled into the app in the test environment, and Dialyzer
  # checks it there along with `lib`. Its ExUnit calls only resolve if `ex_unit`
  # is in the PLT, which it is not by default: it is part of Elixir, not a
  # dependency. Without this, dialyzer reports three unknown_function errors in
  # the test HTTP server.
  defp dialyzer do
    [plt_add_apps: [:ex_unit]]
  end

  defp deps do
    [
      {:finch, "~> 0.19"},
      {:telemetry, "~> 1.0"},

      # Quality only. None of these ship with the library: they are dev/test
      # scoped and `runtime: false`, so a consumer's dependency tree never sees
      # them.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [{"README.md", title: "README"}, "CHANGELOG.md"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
