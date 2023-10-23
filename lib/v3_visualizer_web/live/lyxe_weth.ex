defmodule V3VisualizerWeb.LyxeWethLive do
  use Phoenix.LiveView
  use Phoenix.HTML
  import Bitwise
  import V3VisualizerWeb.Shared
  alias V3Visualizer.Utils
  alias V3Visualizer.Pool.{Contract, Gql}
  alias Contex.{BarChart, Plot, Dataset}

  def render(assigns) do
    ~L"""
      <div class="container">
        <div class="row">
          <div class="column column-25">
            <div class="row">
              <div class="column column-50">
                <%= for {col, i} <- Enum.with_index(Enum.reverse(@events)) do %>
                  <div phx-click="select_state"
                      phx-value-event="<%= col %>">
                    <%= col %>
                  </div>
                <% end %>
              </div>
              <div class="column column-50">
                <%= for {col, i} <- Enum.with_index(Enum.reverse(@swaps)) do %>
                  <div phx-click="select_swap"
                      phx-value-event="<%= col %>">
                    <%= col %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
          <div class="column column-75">
            <%= basic_plot(@test_data, @chart_options, @selected_bar) %>
            <button phx-click="zoom_out">-</button>
            <button phx-click="zoom_in">+</button>
            <form phx-change="tick_range_changed">
              <label for="title">high_tick: <%= @high_tick %></label>
              <label for="title">low_tick: <%= @low_tick %></label>
            </form>
            <form phx-change="chart_options_changed">
              <label for="type">Type</label>
              <%= raw_select("type", "type", chart_type_options(), Atom.to_string(@chart_options.type)) %>
              <label for="orientation">Orientation</label>
              <%= raw_select("orientation", "orientation", chart_orientation_options(), Atom.to_string(@chart_options.orientation)) %>
            </form>
          </div>
        </div>
      </div>
    """

  end

  def mount(_params, _session, socket) do
    #Phoenix.PubSub.subscribe(V3Visualizer.PubSub, "block")
    pool_address = "0x80c7770b4399ae22149db17e97f9fc8a10ca5100"

    socket =
      socket
      |> assign(chart_options: %{
            categories: 10,
            series: 3,
            type: :stacked,
            orientation: :horizontal,
            show_data_labels: "no",
            show_selected: "no",
            show_axislabels: "no",
            custom_value_scale: "no",
            title: nil,
            subtitle: nil,
            colour_scheme: "themed",
            legend_setting: "legend_none"
        })
      |> assign(
        bar_clicked: "Click a bar. Any bar",
        selected_bar: nil,
        selected_event: nil,
        low_tick: -60000,
        high_tick: -40000,
        tick_spacing: Contract.get_tick_spacing(pool_address),
        pool_address: pool_address,
        pool_symbol: :LYXE_WETH_3000,
        key: "LYXE_WETH_3000:"
      )
      |> make_test_data()
      |> make_event_data()

    {:ok, socket}
  end

  def handle_info({:block, block}, socket) do
    IO.inspect(block.number)
    {:noreply, assign(
      socket,
      block_number: block.number,
      base_fee: block.base_fee
    )}
  end

  def handle_event("chart1_bar_clicked", %{"category" => category, "series" => series, "value" => value}=_params, socket) do
    bar_clicked = "You clicked: #{category} / #{series} with value #{value}"
    selected_bar = %{category: category, series: series}

    socket = assign(socket, bar_clicked: bar_clicked, selected_bar: selected_bar)

    {:noreply, socket}
  end

  def handle_event("select_state", %{"event" => event} = params, socket) do
    selected_event = %{selected_event: event}

    pool_address = socket.assigns.pool_address
    key = socket.assigns.key
    tick_spacing = socket.assigns.tick_spacing
    high_tick = socket.assigns.high_tick
    low_tick = socket.assigns.low_tick

    ticks =
      Poison.decode!(
        Redix.command!(:redix, ["XRANGE", "#{key}StateStream", event, event])
        |> Enum.at(0)
        |> Enum.at(1)
        |> Enum.at(1)
      )
      |> Enum.map(fn t -> [String.to_integer(t["tick"]), t["liquidityNet"]] end)

    tick_range = ticks |> Enum.map(fn [t, l] -> t end)

    options = socket.assigns.chart_options

    min_tick = Enum.min(tick_range)#-85200
    max_tick = Enum.max(tick_range)#0

    {liq, data} =
      min_tick..max_tick
      |> Enum.take_every(tick_spacing)
      |> Enum.reduce({0, []}, fn t, {liquidity, data} ->
        tickRange =
          if Enum.member?(tick_range, t) do
            ticks
            |> Enum.find(fn [tk, l] -> tk == t end)
            |> Enum.at(1)
          else
            0
          end

        liquidity = liquidity + tickRange

        new_data = data |> Enum.concat([[t, liquidity]])

        {liquidity, new_data}
      end)

    series_cols = for i <- ["liquidity"] do
      "Series #{i}"
    end

    trim_data =
      data
      |> Enum.filter(fn [t, l] -> t < high_tick end)
      |> Enum.filter(fn [t, l] -> t > low_tick end)
      |> Dataset.new(["Category" | series_cols])

    options = Map.put(options, :series_columns, series_cols)

    socket = assign(socket, test_data: trim_data, chart_options: options, selected_event: selected_event)

    {:noreply, socket}
  end

  def handle_event("select_swap", %{"event" => swap} = params, socket) do
    selected_swap = %{selected_swap: swap}

    pool_address = "0x80c7770b4399ae22149db17e97f9fc8a10ca5100"
    pool_symbol = :LYXE_WETH_3000
    key = "LYXE_WETH_3000:"

    block = swap |> String.split("-") |> Enum.at(0)
    tx_idx = swap |> String.split("-") |> Enum.at(1) |> Utils.zero_pad()

    tick = Redix.command!(:redix, ["HGET", "#{key}Swap:#{block}-#{tx_idx}", "tick"])

    IO.inspect({socket.assigns.selected_event}, label: "swap")

    # series_cols = for i <- ["liquidity"] do
    #   "Series #{i}"
    # end

    # test_data = Dataset.new(data, ["Category" | series_cols])

    # options = Map.put(options, :series_columns, series_cols)

    #socket = assign(socket, test_data: test_data, chart_options: options, selected_swap: selected_swap)

    {:noreply, socket}
  end

  def basic_plot(test_data, chart_options, selected_bar) do
    selected_item = case chart_options.show_selected do
      "yes" -> selected_bar
      _ -> nil
    end

    custom_value_scale = make_custom_value_scale(chart_options)

    options = [
      mapping: %{category_col: "Category", value_cols: chart_options.series_columns},
      type: chart_options.type,
      data_labels: (chart_options.show_data_labels == "yes"),
      orientation: chart_options.orientation,
      phx_event_handler: "chart1_bar_clicked",
      custom_value_scale: custom_value_scale,
      colour_palette: ["b3cde3", "ccebc5"],
      select_item: selected_item,
      padding: 0
    ]

    plot_options = case chart_options.legend_setting do
      "legend_right" -> %{legend_setting: :legend_right}
      "legend_top" -> %{legend_setting: :legend_top}
      "legend_bottom" -> %{legend_setting: :legend_bottom}
      _ -> %{}
    end

    {x_label, y_label} = case chart_options.show_axislabels do
      "yes" -> {"x-axis", "y-axis"}
      _ -> {nil, nil}
    end

    plot =
      Plot.new(test_data, BarChart, 800, 800, options)
      |> Plot.titles(chart_options.title, chart_options.subtitle)
      |> Plot.axis_labels(x_label, y_label)
      |> Plot.plot_options(plot_options)

    Plot.to_svg(plot)
  end

  defp make_event_data(socket) do
    liq_events = Redix.command!(:redix, ["XRANGE", "LYXE_WETH_3000:StateStream", "-", "+"])
    |> Enum.map(fn e -> Enum.at(e,0) end)
    #IO.inspect(events)
    swaps = Redix.command!(:redix, ["XRANGE", "LYXE_WETH_3000:SwapStream", "-", "+"])
    |> Enum.map(fn e -> Enum.at(e,0) end)

    assign(socket, events: liq_events, swaps: swaps)
  end

  defp make_test_data(socket) do
    options = socket.assigns.chart_options
    high_tick = socket.assigns.high_tick
    low_tick = socket.assigns.low_tick
    tick_spacing = socket.assigns.tick_spacing
    pool_address = socket.assigns.pool_address
    key = socket.assigns.key


    last_swap =
      Redix.command!(:redix, ["XREVRANGE", "#{key}SwapStream", "+", "-", "COUNT", 1])
      |> Enum.at(0)
      |> Enum.at(1)

    IO.inspect last_swap
    tick_at_last_swap = -53706
      # last_swap
      # |> Enum.at(1)
      # |> IO.inspect
      #|> String.to_integer()

    sqrt_price_x96 = 0
      # last_swap
      # |> Enum.at(5)
      # |> String.to_integer()

    #{sqrtPriceX96, current_tick} = Contract.get_slot0(pool_address) #TODO: change this to init at last swap

    latest_ticks =
      Redix.command!(:redix, ["XREVRANGE", "#{key}StateStream", "+", "-", "COUNT", 1])
      |> Enum.at(0)
      |> Enum.at(1)
      |> Enum.at(1)
      |> Poison.decode!()

    tick_range =
      latest_ticks
      |> Enum.map(& String.to_integer(&1["tick"]))

    sqrtPriceCurrent = sqrt_price_x96 / (1 <<< 96)
    priceCurrent = sqrtPriceCurrent ** 2
    decimal_diff = 0 #TODO: do this programatically

    min_tick = tick_range |> Enum.at(0)
    max_tick = tick_range |> Enum.take(-1) |> Enum.at(0)

    {liq, data} =
      min_tick..max_tick
      |> Enum.take_every(tick_spacing)
      |> Enum.reduce({0, []}, fn t, {liquidity, data} ->
        tick_liq =
          if Enum.member?(tick_range, t) do
            tick_idx = tick_range |> Enum.find_index(& &1 == t)
            liquid_tick = latest_ticks |> Enum.at(tick_idx)

            liquid_tick["liquidityNet"]
          else
            0
          end

        liquidity = liquidity + tick_liq

        sqrtPriceLow = 1.0001 ** (t / 2)
        sqrtPriceHigh = 1.0001 ** ((t + tick_spacing) / 2)

        amount0 = Utils.calculate_token0_amount(liquidity, sqrtPriceCurrent, sqrtPriceLow, sqrtPriceHigh)
        amount1 = Utils.calculate_token1_amount(liquidity, sqrtPriceCurrent, sqrtPriceLow, sqrtPriceHigh)

        tick_diff = tick_at_last_swap - t
        a0_liq = tick_diff / tick_spacing * liquidity
        a1_liq = (tick_spacing - tick_diff) / tick_spacing * liquidity

        {a0, a1} =
          cond do
            amount0 == 0.0 -> {0, liquidity}
            amount1 == 0.0 -> {liquidity, 0}
            tick_at_last_swap < t + tick_spacing -> {a0_liq, a1_liq}
          end

        new_data = data |> Enum.concat([[t, a0, a1]])

        {liquidity, new_data}
      end)

    series_cols = for i <- ["token0", "token1"] do
      "Series #{i}"
    end

    trim_data =
      data
      |> Enum.filter(fn [t, a0, a1] -> t < high_tick end)
      |> Enum.filter(fn [t, a0, a1] -> t > low_tick end)
      |> Dataset.new(["Category" | series_cols])

    options = Map.put(options, :series_columns, series_cols)

    assign(socket, test_data: trim_data, liquidity_data: data, chart_options: options)
  end

  defp make_test_data2(socket, high_tick, low_tick) do
    current_data = socket.assigns.liquidity_data

    IO.inspect({high_tick, low_tick})

    series_cols = for i <- ["token0", "token1"] do
      "Series #{i}"
    end

    trim_data =
      current_data
      |> Enum.filter(fn [t, a0, a1] -> t < high_tick end)
      |> Enum.filter(fn [t, a0, a1] -> t > low_tick end)


    assign(socket, :test_data, Dataset.new(trim_data, ["Category" | series_cols]))
  end

  def handle_event("chart_options_changed", %{}=params, socket) do
    socket =
      socket
      |> update_chart_options_from_params(params)
      |> make_test_data()

    {:noreply, socket}
  end

  def handle_event("tick_range_changed", %{}=params, socket) do
    # IO.inspect({params["high_tick"], params["low_tick"]})
    # socket =
    #   socket
    #   |> assign(socket, high_tick: String.to_integer(params["high_tick"]), low_tick:  String.to_integer(params["low_tick"]))
    #   |> make_test_data2(String.to_integer(params["high_tick"]), String.to_integer(params["low_tick"]))

    {:noreply, socket}
  end

  def handle_event("zoom_in", _params, socket) do
    high_tick = socket.assigns.high_tick
    low_tick = socket.assigns.low_tick

    socket =
      socket
      |> assign(high_tick: high_tick - 3000, low_tick: low_tick + 3000)
      |> make_test_data2(high_tick - 3000, low_tick + 3000)

    {:noreply, socket}
  end

  def handle_event("zoom_out", _params, socket) do
    high_tick = socket.assigns.high_tick
    low_tick = socket.assigns.low_tick

    socket =
      socket
      |> assign(high_tick: high_tick + 3000, low_tick: low_tick - 3000)
      |> make_test_data2(high_tick + 3000, low_tick - 3000)

    {:noreply, socket}
  end

  defp random_within_range(min, max) do
    diff = max - min
    (:rand.uniform() * diff) + min
  end

  defp make_custom_value_scale(%{custom_value_scale: x}=_chart_options) when x != "yes", do: nil
  defp make_custom_value_scale(_chart_options) do
    Contex.ContinuousLinearScale.new()
    |> Contex.ContinuousLinearScale.domain(0, 500)
    |> Contex.ContinuousLinearScale.interval_count(25)
  end
end
