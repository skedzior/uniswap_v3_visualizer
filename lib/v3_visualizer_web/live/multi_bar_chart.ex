defmodule V3VisualizerWeb.MultiBarChart do
  use Phoenix.LiveView
  use Phoenix.HTML

  def render(assigns) do
    IO.inspect(assigns, label: "render")
    ~L"""
    <div class="container">
      <div class="row">
        <input type="text" name="target_block" id="target_block" placeholder="Enter target_block" value=<%= @target_block %>>
        <button phx-click="set-target-block">set target block</button>
        <button phx-click="clear-target-block">clear target block</button>
      </div>
      <section class="row">
        <%= for {pool, i} <- Enum.with_index(@pools) do %>
          <article class="column column-50">
            <%= live_component V3VisualizerWeb.BarChartComponent,
                id: pool,
                pool: pool,
                target_block: @target_block %>
          </article>
        <% end %>
      </section>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    IO.inspect(self(), label: "mount")
    {:ok, assign(socket,
      pools: [
        "0x80c7770b4399ae22149db17e97f9fc8a10ca5100",
        "0x2418c488bc4b0c3cf1edfc7f6b572847f12ed24f"
      ],
      target_block: nil#17121953#17064654
    )}
  end

  def handle_event("set-target-block", params, socket) do
    {:noreply, assign(socket, target_block: 17064654)}
  end

  def handle_event("clear-target-block", _params, socket) do
    {:noreply, assign(socket, target_block: nil)}
  end
end
