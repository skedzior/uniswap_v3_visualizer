defmodule V3Visualizer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Redix, host: "localhost", port: 8888, name: :redix},
      # Start the Ecto repository
      # V3Visualizer.Repo,
      # Start the Telemetry supervisor
      V3VisualizerWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: V3Visualizer.PubSub},
      # Start the Endpoint (http/https)
      V3VisualizerWeb.Endpoint
      # Start a worker by calling: V3Visualizer.Worker.start_link(arg)
      # {V3Visualizer.Worker, arg}
    ]

    Web3x.Contract.start_link()
    V3Visualizer.Pool.Contract.register_all()

    #V3Visualizer.Mempool.Streamer.start_link()
    # V3Visualizer.Mempool.Classifier.start_link([])
    # V3Visualizer.Mempool.Consumer.start_link([])
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: V3Visualizer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    V3VisualizerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
