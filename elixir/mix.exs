defmodule ChatApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :chat_app,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      releases: releases(),
      deps: deps()
    ]
  end

  # Release used by the benchmark scripts
  # (built into _build/<env>/rel/chat_app/bin/chat_app).
  defp releases do
    [
      chat_app: [
        include_executables_for: [:unix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {ChatApp, []},
      extra_applications: [:logger, :observer, :wx]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 4.0"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.11"},
      {:libcluster, "~> 3.3"}
    ]
  end
end
