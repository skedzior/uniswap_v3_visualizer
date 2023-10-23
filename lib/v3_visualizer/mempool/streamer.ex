defmodule V3Visualizer.Mempool.Streamer do
  use WebSockex

  require Logger
  alias Ethereumex.HttpClient
  alias V3Visualizer.Utils
  alias V3Visualizer.Uniswap.UniversalRouter

  def start_link() do
    WebSockex.start_link(
      "wss://mainnet.infura.io/ws/v3/#{INSERT_YOUR_KEY}",
      __MODULE__,
      %{
        stream_key: "Chains:Ethereum:Mempool:Alchemy"
      }
    )
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("Connected...")
    send(self(), :subscribe_pending)
    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe_pending, state) do
    subscribe_pending = Jason.encode!(%{
      "id" => 1,
      "method" => "eth_subscribe",
      "params" => ["newPendingTransactions"] # alchemy_pendingTransactions
    })
    Logger.info("subbed with payload: #{inspect(subscribe_pending)}")

    {:reply, {:text, subscribe_pending}, state}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} -> handle_event(event, state)
      {:error, _} -> throw("Unable to parse msg: #{msg}")
    end

    {:ok, state}
  end

  def handle_event(event, state) do
    tx_hash = event["params"]["result"]
    #IO.inspect(tx_hash, label: "tx_hash: ")
    {txStatus, tx} = HttpClient.eth_get_transaction_by_hash(tx_hash)
    #Logger.info("tx_hash: #{inspect(tx_hash)}")
    with %{} <- tx do
      #Logger.info("tx: #{inspect(tx)}")
      handle_tx(tx, state)
    end

    # {receiptStatus, receipt} = HttpClient.eth_get_transaction_receipt(tx_hash)
    # #IO.inspect(receipt, label: "receipt: ")
    # with %{} <- receipt do
    #   Logger.info("receipt: #{inspect(receipt)}")
    # end
  end

  def handle_tx(tx, state) do
    pending_tx = %{
      :block_hash => tx["blockHash"],
      :block_number => tx["blockNumber"],
      :from => tx["from"],
      :gas => tx["gas"],
      :gas_price => tx["gasPrice"],
      :hash => tx["hash"],
      :input => tx["input"],
      :nonce => tx["nonce"],
      :r => tx["r"],
      :s => tx["s"],
      :to => tx["to"],
      :transaction_index => tx["transactionIndex"],
      :type => tx["type"],
      :v => tx["v"],
      :value => tx["value"]
    }

    if pending_tx.to != nil && pending_tx.input != nil do
      to_address = String.downcase(pending_tx.to)

      resp =
        case to_address do
          "0xef1c6e67703c7bd7107eed8303fbe6ec2554bf6b" -> UniversalRouter.decode_router_tx(pending_tx)
          "0x3fc91a3afd70395cd496c647d5a6cc9d4b2b7fad" -> UniversalRouter.decode_router_tx(pending_tx)
          _ -> nil
        end
    end
    add_to_stream(state.stream_key, pending_tx)
 end

  def add_to_stream(stream_key, tx) do
    Redix.command(:redix, ["XADD", stream_key, "*"] ++ format_data_for_redis_stream(tx))
  end

  defp format_data_for_redis_stream(tx) do
    [
      "block_number", tx.block_number,
      "block_hash", tx.block_hash,
      "value", tx.value
    ]
  end
end
