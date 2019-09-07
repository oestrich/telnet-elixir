defmodule Telnet.MixProject do
  use Mix.Project

  def project() do
    [
      app: :telnet,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/oestrich/telnet-elixir",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application() do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps() do
    [
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:jason, "~> 1.1"}
    ]
  end

  defp description() do
    """
    Telnet parsing library
    """
  end

  defp package() do
    [
      maintainers: ["Eric Oestrich"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/oestrich/telnet-elixir"}
    ]
  end
end
