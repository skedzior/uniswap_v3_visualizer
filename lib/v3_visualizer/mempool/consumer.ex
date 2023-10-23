defmodule V3Visualizer.Mempool.Consumer do
  use GenServer

  alias Ethereumex.HttpClient
  alias V3Visualizer.Utils

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [:hello])
  end

  def init(_opts) do
    Phoenix.PubSub.subscribe(V3Visualizer.PubSub, "new_pending_universal_router_tx")
    # Redix.Stream.Consumer.start_link(:redix, "new_pending_tx", fn stream, id, values -> Logger.info("Got message #{inspect values} from stream #{stream}") end)
    {:ok, ""}
  end

  def handle_info(pending_tx, state) do

    input = String.slice(pending_tx.input, 2..-1)
    {method_id, raw_data} = String.split_at(input, 8)

    [commands, inputs, deadline] =
      raw_data
      |> Base.decode16!(case: :lower)
      |> ABI.TypeDecoder.decode(%ABI.FunctionSelector{
        types: [
          :bytes,
          {:array, :bytes},
          {:uint, 256}
        ]
      })

    decoded_commands =
      Enum.zip([:binary.bin_to_list(commands), inputs])
      |> Enum.map(fn {c, input} ->
        case c do
          0 -> {:V3_SWAP_EXACT_IN,  Utils.decode_v3_swap(input)}
          1 -> {:V3_SWAP_EXACT_OUT, Utils.decode_v3_swap(input)}
          8 -> {:V2_SWAP_EXACT_IN,  Utils.decode_v2_swap(input)}
          9 -> {:V2_SWAP_EXACT_OUT, Utils.decode_v2_swap(input)}
          _ -> {:SKIP, nil}
        end
      end)

    IO.inspect(decoded_commands, label: "universal router call")

    {:noreply, state}
  end
end
# V3Visualizer.Mempool.start_link
