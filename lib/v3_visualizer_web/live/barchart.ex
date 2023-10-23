defmodule V3VisualizerWeb.BarChartLive do
  use Phoenix.LiveView
  use Phoenix.HTML

  import V3VisualizerWeb.Shared
  import V3Visualizer.Pool.Contract

  alias Contex.{BarChart, Plot, Dataset}

  def render(assigns) do
    ~L"""
      <div class="container">
        <div class="row">
          <div class="column column-25">
            <form phx-change="chart_options_changed">
              <label for="title">Plot Title</label>
              <input type="text" name="title" id="title" placeholder="Enter title" value=<%= @chart_options.title %>>
              <label for="title">Sub Title</label>
              <input type="text" name="subtitle" id="subtitle" placeholder="Enter subtitle" value=<%= @chart_options.subtitle %>>
              <label for="type">Type</label>
              <%= raw_select("type", "type", chart_type_options(), Atom.to_string(@chart_options.type)) %>
              <label for="orientation">Orientation</label>
              <%= raw_select("orientation", "orientation", chart_orientation_options(), Atom.to_string(@chart_options.orientation)) %>
              <label for="colour_scheme">Colour Scheme</label>
              <%= raw_select("colour_scheme", "colour_scheme", colour_options(), @chart_options.colour_scheme) %>
              <label for="legend_setting">Legend</label>
              <%= raw_select("legend_setting", "legend_setting", legend_options(), @chart_options.legend_setting) %>
              <label for="show_axislabels">Show Axis Labels</label>
              <%= raw_select("show_axislabels", "show_axislabels", yes_no_options(), @chart_options.show_axislabels) %>
              <label for="show_data_labels">Show Data Labels</label>
              <%= raw_select("show_data_labels", "show_data_labels", yes_no_options(), @chart_options.show_data_labels) %>
              <label for="custom_value_scale">Custom Value Scale</label>
              <%= raw_select("custom_value_scale", "custom_value_scale", yes_no_options(), @chart_options.custom_value_scale) %>
              <label for="show_selected">Show Clicked Bar</label>
              <%= raw_select("show_selected", "show_selected", yes_no_options(), @chart_options.show_selected) %>
            </form>
          </div>
          <div class="column column-75">
            <%= basic_plot(@test_data, @chart_options, @selected_bar) %>
            <p><em><%= @bar_clicked %></em></p>
            <%= list_to_comma_string(@chart_options[:friendly_message]) %>
          </div>
        </div>
      </div>
    """

  end

  def mount(_params, _session, socket) do
    V3Visualizer.Pool.Contract.register_all()

    IO.inspect(V3Visualizer.Pool.Contract.get_slot0("0x31ad100cef4cbdba0522a751541810d122d92120"))

    Phoenix.PubSub.subscribe(V3Visualizer.PubSub, "block")

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
            legend_setting: "legend_none",
        })
      |> assign(bar_clicked: "Click a bar. Any bar", selected_bar: nil)
      |> make_test_data3()

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

  def handle_event("chart_options_changed", %{}=params, socket) do
    socket =
      socket
      |> update_chart_options_from_params(params)
      |> make_test_data()

    {:noreply, socket}
  end

  def handle_event("chart1_bar_clicked", %{"category" => category, "series" => series, "value" => value}=_params, socket) do
    bar_clicked = "You clicked: #{category} / #{series} with value #{value}"
    selected_bar = %{category: category, series: series}

    socket = assign(socket, bar_clicked: bar_clicked, selected_bar: selected_bar)

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

    # barchart = BarChart.new(test_data, colour_palette: ["000000", "ffffff"])

    plot =  # Plot.new(500, 400, barchart)
      Plot.new(test_data, BarChart, 800, 800, options)
      |> Plot.titles(chart_options.title, chart_options.subtitle)
      |> Plot.axis_labels(x_label, y_label)
      |> Plot.plot_options(plot_options)

    Plot.to_svg(plot)
  end

  defp make_test_data(socket) do
    options = socket.assigns.chart_options
    series = 1
    raw_data = [
      [246000, 1021700893270807],
      [246200, 1021700893270807],
      [246400, 1021700893270807],
      [246600, 1021700893270807],
      [246800, 1021700893270807],
      [247000, 1021700893270807],
      [247200, 1021700893270807],
      [247400, 1021700893270807],
      [247600, 1021700893270807],
      [247800, 1021700893270807],
      [248000, 1021700893270807],
      [248200, 1021700893270807],
      [248400, 1021700893270807],
      [248600, 1021700893270807],
      [248800, 1021700893270807],
      [249000, 1021700893270807],
      [249200, 1021700893270807],
      [249400, 1021700893270807],
      [249600, 1021700893270807],
      [249800, 28843669494406812],
      [250000, 28843669494406812],
      [250200, 28843669494406812],
      [250400, 28843669494406812],
      [250600, 28843669494406812],
      [250800, 28843669494406812],
      [251000, 28843669494406812],
      [251200, 28843669494406812],
      [251400, 28843669494406812],
      [251600, 28843669494406812],
      [251800, 28843669494406812],
      [252000, 28843669494406812],
      [252200, 28843669494406812],
      [252400, 28843669494406812],
      [252600, 28843669494406812],
      [252800, 28843669494406812],
      [253000, 28843669494406812],
      [253200, 98289907830585788],
      [253400, 98289907830585788],
      [253600, 98289907830585788],
      [253800, 98289907830585788],
      [254000, 98289907830585788],
      [254200, 98289907830585788],
      [254400, 98289907830585788],
      [254600, 98289907830585788],
      [254800, 98289907830585788],
      [255000, 98289907830585788],
      [255200, 98289907830585788],
      [255400, 98289907830585788],
      [255600, 98289907830585788],
      [255800, 98289907830585788],
      [256000, 98289907830585788],
      [256200, 98289907830585788],
      [256400, 98289907830585788],
      [256600, 98289907830585788],
      [256800, 233536469144605293],
      [257000, 233536469144605293],
      [257200, 164090230808426317],
      [257400, 164090230808426317],
      [257600, 136268262207290312],
      [257800, 136268262207290312],
      [258000, 136268262207290312],
      [258200, 135246561314019505],
      [258400, 135246561314019505],
      [258600, 135246561314019505],
      [258800, 135246561314019505],
      [259000, 135246561314019505],
      [259200, 135246561314019505],
      [259400, 135246561314019505],
      [259600, 135246561314019505]
    ]

    data =
      raw_data
      |> Enum.map(fn [left, right] ->
        [left, right]
      end)

    series_cols = for i <- 1..series do
      "Series #{i}"
    end

    test_data = Dataset.new(data, ["Category" | series_cols])

    options = Map.put(options, :series_columns, series_cols)

    assign(socket, test_data: test_data, chart_options: options)
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
