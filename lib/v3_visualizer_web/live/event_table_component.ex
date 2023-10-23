defmodule V3VisualizerWeb.EventTableComponent do
  use V3VisualizerWeb, :live_component

  def render(assigns) do
    IO.inspect(assigns)
    ~L"""
    <table>

    </table>
    """
  end

  def mount(_params, _session, socket) do
    events = Redix.command!(:redix, ["XRANGE", "LYXE_WETH_3000:StateStream", "-", "+"])
    |> Enum.map(fn e -> Enum.at(e,0) end)
    IO.inspect(events)


    {:ok, assign(socket, events: events)}
  end

  # def handle_event("select_state", params, socket) do
  #   #selected_state = %{selected_state: event}
  #   IO.inspect(params)
  #   IO.inspect(socket.assigns)
  #   #socket = assign(socket, selected_state: selected_state)

  #   {:noreply, socket}
  # end

  def update(params, socket) do
    # %{options: options, form: form, id: id} = params
    # socket =
    #   socket
    #   |> assign(:id, id)
    #   |> assign(:selectable_options, options)
    #   |> assign(:form, form)
    #   |> assign(:selected_options, filter_selected_options(options))

    {:ok, socket}
  end
end
