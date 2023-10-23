defmodule V3VisualizerWeb.PageController do
  use V3VisualizerWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
