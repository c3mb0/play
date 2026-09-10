defmodule PtyLabEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :pty_lab_ex,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: [{:pty_lab, path: "../../erlang/pty_lab", manager: :rebar3}]
    ]
  end

  def application, do: [extra_applications: [:crypto, :pty_lab]]
end
