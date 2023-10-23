defmodule V3Visualizer.Repo do
  use Ecto.Repo,
    otp_app: :v3_visualizer,
    adapter: Ecto.Adapters.Postgres
end
