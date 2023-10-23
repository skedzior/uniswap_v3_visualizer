defmodule V3VisualizerWeb.BarChartComponent do
  use Phoenix.LiveComponent
  use Phoenix.HTML
  import Bitwise
  import V3Visualizer.Pool.Contract
  alias V3Visualizer.Utils
  alias Contex.{BarChart, Plot, Dataset}

  def render(assigns) do
    ~H"""
      <div>
        <div><%= @contract_symbol %> - <%= @pool %></div>
        <div>current tick: <%= @current_tick %></div>
        <div>current price: <%= @current_price %></div>
        <div><%= basic_plot(@dataset, @chart_options, @myself, @selected_bar) %></div>

        <button class="button button-outline" phx-click="clear" phx-target={@myself}>Clear</button>
        <span><em><%= @bar_clicked %></em></span>

        <h3>Liquidity changes in target block</h3>

        <h3>Swaps in target block</h3>
        <div class="row">
          <div class="column column-10">tick</div>
          <div class="column column-20">idx</div>
          <div class="column column-35">amount0</div>
          <div class="column column-35">amount1</div>
        </div>
        <%= for {swap, i} <- Enum.with_index(@target_swaps) do %>
          <div class="row" phx-click="select-target-swap" phx-target={@myself}
            phx-value-idx={swap["idx"]}
            phx-value-tick={swap["tick"]}
            phx-value-price={swap["sqrtPriceX96"]}>
            <div class="column column-10">
              <%= swap["tick"] %>
            </div>
            <div class="column column-20">
              <%= swap["idx"] %>
            </div>
            <div class="column column-35">
              <%= swap["amount0"] %>
            </div>
            <div class="column column-35">
              <%= swap["amount1"] %>
            </div>
          </div>
        <% end %>
      </div>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, chart_options: %{
      type: :stacked,
      orientation: :vertical,
      show_data_labels: "no",
      show_selected: "no",
      show_axislabels: "no",
      title: nil,
      subtitle: nil,
      colour_scheme: "themed",
      legend_setting: "legend_none"
    })}
  end

  def update(assigns, socket) do
    contract_symbol = contract_symbol_by_address(assigns.pool)
    decimal_diff = 0 #TODO: do this programatically

    socket =
      socket
      |> assign(
        pool: assigns.pool,
        tick_spacing: get_tick_spacing(assigns.pool),
        key: Atom.to_string(contract_symbol) <> ":",
        contract_symbol: contract_symbol,
        selected_bar: nil,
        selected_swap: nil,
        bar_clicked: raw("&nbsp"),
        target_block: assigns.target_block,
        target_swaps: [],
        decimal_diff: decimal_diff
      )
      |> make_data()
      #|> make_event_data()

    {:ok, socket}
  end

  def handle_event("bar_clicked", %{"category" => category, "series" => series, "value" => value}=_params, socket) do
    {value, _} = Float.parse(value)
    bar_clicked = "#{category} / #{series} with value #{trunc(value)}"
    selected_bar = %{category: category, series: series}

    socket = assign(socket, bar_clicked: bar_clicked, selected_bar: selected_bar)

    {:noreply, socket}
  end

  def handle_event("clear", _params, socket) do
    socket = assign(socket, bar_clicked: raw("&nbsp"), selected_bar: nil)

    {:noreply, socket}
  end

  def handle_event("select-target-swap", params, socket) do
    selected_swap = %{selected_swap: params["idx"]}
    swap_tick = String.to_integer(params["tick"])
    sqrt_price_x96 = String.to_integer(params["price"])

    decimal_diff = socket.assigns.decimal_diff
    tick_spacing = socket.assigns.tick_spacing
    key = socket.assigns.key
    # trim_data = socket.assigns.dataset.data
    # |> Enum.filter(fn [t, a0, a1] -> t > -51180 end)
    # IO.inspect(trim_data, label: "swap")

    sqrtPriceCurrent = sqrt_price_x96 / (1 <<< 96)
    priceCurrent = sqrtPriceCurrent ** 2

    low_tick = -60001
    high_tick = -39999

    target_ticks =
      Redix.command!(:redix, ["XREVRANGE", "#{key}StateStream", socket.assigns.target_block, "-", "COUNT", 1])
      |> Enum.at(0)
      |> Enum.at(1)
      |> Enum.at(1)
      |> Poison.decode!()

    tick_range =
      target_ticks
      |> Enum.map(& String.to_integer(&1["tick"]))

    min_tick = tick_range |> Enum.at(0)
    max_tick = tick_range |> Enum.take(-1) |> Enum.at(0)

    {liq, data} =
      min_tick..max_tick
      |> Enum.take_every(tick_spacing)
      |> Enum.reduce({0, []}, fn t, {liquidity, data} ->
        tick_liq =
          if Enum.member?(tick_range, t) do
            tick_idx = tick_range |> Enum.find_index(& &1 == t)
            liquid_tick = target_ticks |> Enum.at(tick_idx)

            liquid_tick["liquidityNet"]
          else
            0
          end

        liquidity = liquidity + tick_liq

        sqrtPriceLow = 1.0001 ** (t / 2)
        sqrtPriceHigh = 1.0001 ** ((t + tick_spacing) / 2)

        amount0 = Utils.calculate_token0_amount(liquidity, sqrtPriceCurrent, sqrtPriceLow, sqrtPriceHigh)
        amount1 = Utils.calculate_token1_amount(liquidity, sqrtPriceCurrent, sqrtPriceLow, sqrtPriceHigh)

        tick_diff = swap_tick - t
        a0_liq = tick_diff / tick_spacing * liquidity
        a1_liq = (tick_spacing - tick_diff) / tick_spacing * liquidity

        {a0, a1} =
          cond do
            amount0 == 0.0 -> {0, liquidity}
            amount1 == 0.0 -> {liquidity, 0}
            swap_tick < t + tick_spacing -> {a0_liq, a1_liq}
          end

        new_data = data |> Enum.concat([[t, a0, a1]])
        #TODO: add token amounts and liquidity to above - Enum.concat([[t, a0, a1, liquidity, amount0, amount1]])
        #maybe -> Enum.concat([[t, a0, liquidity, amount0, amount1, max0, max1, p0, p1]])

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

    {:noreply, assign(socket,
      current_price: priceCurrent,
      current_tick: swap_tick,
      dataset: trim_data,
      selected_swap: selected_swap)}
  end

  defp make_data(socket) do
    pool_address = socket.assigns.pool
    tick_spacing = socket.assigns.tick_spacing
    key = socket.assigns.key
    target_block = socket.assigns.target_block
    decimal_diff = socket.assigns.decimal_diff

    if target_block == nil do
      last_swap =
        Redix.command!(:redix, ["XREVRANGE", "#{key}SwapStream", "+", "-", "COUNT", 1])
        |> Enum.at(0)
        |> Enum.at(1)

      tick_at_last_swap =
        last_swap
        |> Enum.at(1)
        |> String.to_integer()

      sqrt_price_x96 =
        last_swap
        |> Enum.at(5)
        |> String.to_integer()

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
      low_tick = -60001
      high_tick = -39999

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

      options = Map.put(socket.assigns.chart_options, :series_columns, series_cols)

      assign(socket, target_swaps: [], current_price: priceCurrent, current_tick: tick_at_last_swap, dataset: trim_data, liquidity_data: data, chart_options: options)
    else
      target_swaps =
        Redix.command!(:redix, ["XREVRANGE", "#{key}SwapStream", target_block, target_block])
        |> Enum.map(fn [idx, swap] ->
          swap
          |> Utils.list_to_map()
          |> Map.put("idx", idx)
        end)

      target_ticks =
        Redix.command!(:redix, ["XREVRANGE", "#{key}StateStream", target_block, "-", "COUNT", 1])
        |> Enum.at(0)
        |> Enum.at(1)
        |> Enum.at(1)
        |> Poison.decode!()

      last_swap =
        Redix.command!(:redix, ["XREVRANGE", "#{key}SwapStream", target_block, "-", "COUNT", 1])
        |> Enum.at(0)
        |> Enum.at(1)

      tick_at_last_swap =
        last_swap
        |> Enum.at(1)
        |> String.to_integer()

      sqrt_price_x96 =
        last_swap
        |> Enum.at(5)
        |> String.to_integer()

      tick_range =
        target_ticks
        |> Enum.map(& String.to_integer(&1["tick"]))

      sqrtPriceCurrent = sqrt_price_x96 / (1 <<< 96)
      priceCurrent = sqrtPriceCurrent ** 2

      min_tick = tick_range |> Enum.at(0)
      max_tick = tick_range |> Enum.take(-1) |> Enum.at(0)
      low_tick = -60001
      high_tick = -39999

      {liq, data} =
        min_tick..max_tick
        |> Enum.take_every(tick_spacing)
        |> Enum.reduce({0, []}, fn t, {liquidity, data} ->
          tick_liq =
            if Enum.member?(tick_range, t) do
              tick_idx = tick_range |> Enum.find_index(& &1 == t)
              liquid_tick = target_ticks |> Enum.at(tick_idx)

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

      options = Map.put(socket.assigns.chart_options, :series_columns, series_cols)

      assign(socket,
        current_price: priceCurrent,
        current_tick: tick_at_last_swap,
        dataset: trim_data,
        liquidity_data: data,
        target_swaps: target_swaps,
        chart_options: options)
    end
  end

  defp basic_plot(data, chart_options, target_id, selected_item) do
    IO.inspect(target_id, label: "target_id")
    selected_item = case chart_options.show_selected do
      "yes" -> selected_item
      _ -> nil
    end

    options = [
      mapping: %{category_col: "Category", value_cols: chart_options.series_columns},
      orientation: :horizontal,
      #colour_palette: ["ff9838", "fdae53", "fbc26f", "fad48e", "fbe5af", "fff5d1"],
      phx_event_handler: "bar_clicked",
      phx_event_target: inspect(target_id),
      select_item: selected_item,
      type: :stacked,
      show_data_labels: "no",
      data_labels: (chart_options.show_data_labels == "yes"),
      show_selected: "no",
      show_axislabels: "no",
      colour_palette: ["b3cde3", "ccebc5"],
      select_item: selected_item,
      padding: 0,
      colour_scheme: "themed",
      legend_setting: "legend_none"
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
      Plot.new(data, BarChart, 800, 800, options)
      |> Plot.titles(chart_options.title, chart_options.subtitle)
      |> Plot.axis_labels(x_label, y_label)
      |> Plot.plot_options(plot_options)

    Plot.to_svg(plot)
  end
end
