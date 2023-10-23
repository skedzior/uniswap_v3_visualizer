defmodule V3Visualizer.Mempool.Classifier do
  use GenServer

  alias Ethereumex.HttpClient
  alias V3Visualizer.Utils

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [:hello])
  end

  def init(_opts) do
    Phoenix.PubSub.subscribe(V3Visualizer.PubSub, "new_pending_tx")
    # Redix.Stream.Consumer.start_link(:redix, "new_pending_tx", fn stream, id, values -> Logger.info("Got message #{inspect values} from stream #{stream}") end)
    {:ok, ""}
  end

  def handle_info(pending_tx, state) do
    if pending_tx.to != nil &&
      String.downcase(pending_tx.to) == "0xef1c6e67703c7bd7107eed8303fbe6ec2554bf6b" ||
      String.downcase(pending_tx.to) == "0x3fc91a3afd70395cd496c647d5a6cc9d4b2b7fad"
    do
      Phoenix.PubSub.broadcast(V3Visualizer.PubSub, "new_pending_universal_router_tx", pending_tx)
    # else
    #   Phoenix.PubSub.broadcast(V3Visualizer.PubSub, "new_pending_tx", pending_tx)
    end
    {:noreply, state}
  end
end
