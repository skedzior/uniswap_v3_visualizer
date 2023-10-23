defmodule V3Visualizer.Pool.Contract do
  alias V3Visualizer.Pool.Gql
  alias V3Visualizer.{Utils, Chain}

  @endpoint "https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3"
  @headers [{"Content-type", "application/json"}]

  @chunk_size 5000

  @pools [
    {:UniswapV3Pool, "0x11b815efb8f581194ae79006d24e0d814b7697f6", :ETH_USDT_500},
    {:UniswapV3Pool, "0x4e68ccd3e89f51c3074ca5072bbac773960dfa36", :ETH_USDT_3000},
    {:UniswapV3Pool, "0x11950d141ecb863f01007add7d1a342041227b58", :PEPE_WETH_3000}, # block_deplyed: 17083569
    {:UniswapV3Pool, "0x31ad100cef4cbdba0522a751541810d122d92120", :LYXE_USDC_10000}, # block_deplyed: 12939853
    {:UniswapV3Pool, "0x2418c488bc4b0c3cf1edfc7f6b572847f12ed24f", :LYXE_WETH_10000}, # block_deplyed: 16553174
    {:UniswapV3Pool, "0x80c7770b4399ae22149db17e97f9fc8a10ca5100", :LYXE_WETH_3000} # block_deplyed: 12369811
  ]

  @factory {:UniswapV3Factory, "0x1F98431c8aD98523631AE4a59f267346ea31F984", :V3_FACTORY}

  def list_all, do: @pools

  defp base_path, do: "abis/"

  def register_all do
    for contract_data <- @pools do
      register(contract_data)
    end
    register(@factory)
  end

  defp contract_path({contract_name, _contract_address, _symbol} = contract_data),
    do: base_path() <> Atom.to_string(contract_name) <> ".json"

  defp contract_path(contract_name),
    do: base_path() <> Atom.to_string(contract_name) <> ".json"

  #  Decodes contract json so we can access individual keys
  defp decode_contract(contract_name),
    do: contract_name |> contract_path() |> File.read!() |> Jason.decode!()

  def register({contract_name, contract_address, symbol} = contract_data) do
    contract_abi = contract_name |> contract_path() |> Web3x.Abi.load_abi()
    # Register the already deployed contract with Web3x
    Web3x.Contract.register(symbol, abi: contract_abi)
    # Tell Web3x where the contract was deployed on the chain
    Web3x.Contract.at(symbol, contract_address)
  end

  def contract_symbol_by_address(contract_address) do
    {_name, _address, symbol} =
      Enum.find(list_all(), fn {_name, address, _symbol} ->
        String.downcase(address) == contract_address or address == contract_address
      end)

    symbol
  end

  def contract_address_by_symbol(contract_symbol) do
    {_name, address, _symbol} =
      Enum.find(list_all(), fn {_name, _address, symbol} ->
        symbol == contract_symbol
      end)

      address
  end

  def get_slot0(address) do
    {
      :ok,
      sqrtPriceX96,
      tick,
      observationIndex,
      observationCardinality,
      observationCardinalityNext,
      feeProtocol,
      unlocked
    } = Web3x.Contract.call(contract_symbol_by_address(address), :slot0)

    # TODO: get on pool init?
    {sqrtPriceX96, tick}
  end

  def get_tick_spacing(address) do
    {:ok, tick_spacing} = Web3x.Contract.call(contract_symbol_by_address(address), :tickSpacing)

    tick_spacing
  end

  def get_liquidity(address) do
    {:ok, liquidity} = Web3x.Contract.call(contract_symbol_by_address(address), :liquidity)

    liquidity
  end

  def get_token0(address) do
    {:ok, bytes} = Web3x.Contract.call!(contract_symbol_by_address(address), :token0)

    Web3x.Utils.to_address(bytes)
  end

  def get_token1(address) do
    {:ok, bytes} = Web3x.Contract.call(contract_symbol_by_address(address), :token1)

    Web3x.Utils.to_address(bytes)
  end

  def get_pool_tokens(address) do
    {:ok, t0} = Web3x.Contract.call(contract_symbol_by_address(address), :token0)
    {:ok, t1} = Web3x.Contract.call(contract_symbol_by_address(address), :token1)

    {Web3x.Utils.to_address(t0), Web3x.Utils.to_address(t1)}
  end

  def get_pool_fee(address) do
    {:ok, fee} = Web3x.Contract.call(contract_symbol_by_address(address), :fee)

    fee
  end

  def get_pool_init(address) do
    block_deployed = 16553174

    {:ok, filter_id} =
        Web3x.Contract.filter(
          contract_symbol_by_address(address),
          "Initialized",
          %{
            fromBlock: block_deployed,
            toBlock: block_deployed
          }
        )

    {:ok, events} =
      Web3x.Client.call_client(
        :eth_get_filter_logs,
        [filter_id]
      )

    pool_init =
      events
      |> Enum.filter(fn e ->
          e["topics"] |> Enum.at(0) |> String.downcase() == String.downcase("0x98636036cb66a9c19a37435efc1e90142190214e8abeb821bdba3f2990dd4c95")
        end)
      |> Enum.at(0)

    [sqrtPriceX96, tick] =
      pool_init["data"]
      |> String.slice(2..-1)
      |> Base.decode16!(case: :lower)
      |> ABI.TypeDecoder.decode(
          %ABI.FunctionSelector{
            types: [
              {:uint, 160},
              {:int, 24}
            ]
          }
        )

    IO.inspect(sqrtPriceX96, label: "sqrtPriceX96")
    IO.inspect(tick, label: "tick")
  end

  def get_pool_creation(address) do
    block_deployed = 16553174
    {contract_name, contract_address, symbol} = @factory

    {:ok, filter_id} =
        Web3x.Contract.filter(
          :V3_FACTORY,
          "PoolCreated",
          %{
            fromBlock: block_deployed,
            toBlock: block_deployed
          }
        )

    {:ok, events} =
      Web3x.Client.call_client(
        :eth_get_filter_logs,
        [filter_id]
      )

    pool_init =
      events
      |> Enum.filter(fn e ->
          String.downcase("0x" <> String.slice(e["data"], -40..-1)) == String.downcase(address)
        end)

    IO.inspect(pool_init)
  end

  def process_events(contract_symbol, event, filter) do
    current_block = Chain.get_current_block_number()

    if filter.fromBlock < current_block do
      filter_and_call(contract_symbol, event, filter)

      IO.inspect(filter.fromBlock + @chunk_size)

      process_events(
        contract_symbol,
        event,
        %{
          fromBlock: filter.fromBlock + @chunk_size,
          toBlock: filter.toBlock + @chunk_size
        }
      )
    end
  end

  def decode_events(contract_symbol, event, events) do
    address = contract_address_by_symbol(contract_symbol)

    decoded_events =
      events
      |> Enum.map(& Gql.get_events_from_hash(:v3, address, &1["transactionHash"]))
      |> Enum.filter(& !is_nil(&1))

    case event do
      "Mint" ->
        decoded_events
        |> Enum.map(& &1["mints"])
        |> List.flatten()
        |> Enum.map(&
          Redix.command(:redix, [
            "HSET", generate_key(contract_symbol, event, &1["transaction"]["blockNumber"], &1["logIndex"]),
            "id", &1["id"],
            "amount", &1["amount"],
            "amount0", &1["amount0"],
            "amount1", &1["amount1"],
            "amountUSD", &1["amountUSD"],
            "timestamp", &1["timestamp"],
            "tickLower", &1["tickLower"],
            "tickUpper", &1["tickUpper"]
          ])
        )
      "Burn" ->
        decoded_events
        |> Enum.map(& &1["burns"])
        |> List.flatten()
        |> Enum.map(&
          Redix.command(:redix, [
            "HSET", generate_key(contract_symbol, event, &1["transaction"]["blockNumber"], &1["logIndex"]),
            "id", &1["id"],
            "amount", &1["amount"],
            "amount0", &1["amount0"],
            "amount1", &1["amount1"],
            "amountUSD", &1["amountUSD"],
            "timestamp", &1["timestamp"],
            "tickLower", &1["tickLower"],
            "tickUpper", &1["tickUpper"]
          ])
        )
      "Swap" ->
        decoded_events
        |> Enum.map(& &1["swaps"])
        |> List.flatten()
        |> Enum.map(&
          Redix.command(:redix, [
            "HSET", generate_key(contract_symbol, event, &1["transaction"]["blockNumber"], &1["logIndex"]),
            "id", &1["id"],
            "sender", &1["sender"],
            "recipient", &1["recipient"],
            "sqrtPriceX96", &1["sqrtPriceX96"],
            "origin", &1["origin"],
            "amount0", &1["amount0"],
            "amount1", &1["amount1"],
            "amountUSD", &1["amountUSD"],
            "timestamp", &1["timestamp"],
            "tick", &1["tick"]
          ])
        )
    end

  end

  def filter_and_call(contract_symbol, event, filter) do
    filter_resp = Web3x.Contract.filter(contract_symbol, event, filter)
    #IO.inspect(filter_resp, label: "filter_resp")

    case filter_resp do
      {:ok, {:error, _}} -> filter_and_call(contract_symbol, event, filter)
      {:ok, filter_id} -> filter_and_call(contract_symbol, event, filter, filter_id)
      _ -> filter_and_call(contract_symbol, event, filter)
    end
  end

  def filter_and_call(contract_symbol, event, filter, filter_id) do
    events_resp = Web3x.Client.call_client(:eth_get_filter_logs, [filter_id])
    IO.inspect("filter_and_call with id")
    case events_resp do
      {:ok, {:error, _}} -> filter_and_call(contract_symbol, event, filter)
      {:ok, events} -> decode_events(contract_symbol, event, events)
      _ -> filter_and_call(contract_symbol, event, filter)
    end
  end

  def get_all_events(address) do
    register_all()
    block_deployed = 17389000
    filter = %{
      fromBlock: block_deployed,
      toBlock: block_deployed + @chunk_size
    }

    process_events(contract_symbol_by_address(address), "Burn", filter)
    process_events(contract_symbol_by_address(address), "Mint", filter)
    process_events(contract_symbol_by_address(address), "Swap", filter)
  end

  def get_mints(address) do
    block_deployed = 16553174

    process_events(
      contract_symbol_by_address(address),
      "Mint",
      %{
        fromBlock: block_deployed,
        toBlock: block_deployed + @chunk_size
      }
    )
  end

  def get_mints_from(address, start_block) do
    process_events(
      contract_symbol_by_address(address),
      "Mint",
      %{
        fromBlock: start_block,
        toBlock: start_block + @chunk_size
      }
    )
  end

  def get_burns(address) do
    block_deployed = 16553174

    process_events(
      contract_symbol_by_address(address),
      "Burn",
      %{
        fromBlock: block_deployed,
        toBlock: block_deployed + @chunk_size
      }
    )
  end

  def get_burns_from(address, start_block) do
    process_events(
      contract_symbol_by_address(address),
      "Burn",
      %{
        fromBlock: start_block,
        toBlock: start_block + @chunk_size
      }
    )
  end

  def get_swaps(address) do
    block_deployed = 16553174

    process_events(
      contract_symbol_by_address(address),
      "Swap",
      %{
        fromBlock: block_deployed,
        toBlock: block_deployed + @chunk_size
      }
    )
  end

  def get_swaps_from(address, start_block) do
    process_events(
      contract_symbol_by_address(address),
      "Swap",
      %{
        fromBlock: start_block,
        toBlock: start_block + @chunk_size
      }
    )
  end

  def generate_key(contract_symbol, event_type, block_number, log_index),
    do: Atom.to_string(contract_symbol) <> ":" <> event_type <> ":" <> block_number <> "-" <> Utils.zero_pad(log_index)
end

# V3Visualizer.Pool.Contract.get_all_events("0x80c7770b4399ae22149db17e97f9fc8a10ca5100")
# V3Visualizer.Pool.Contract.get_all_events("0x2418c488bc4b0c3cf1edfc7f6b572847f12ed24f")
# V3Visualizer.Pool.Contract.get_swaps_from("0x2418c488bc4b0c3cf1edfc7f6b572847f12ed24f", 17289000)
# V3Visualizer.Pool.Contract.get_swaps_from("0x80c7770b4399ae22149db17e97f9fc8a10ca5100", 17093568)
# V3Visualizer.Pool.Contract.get_burns_from("0x80c7770b4399ae22149db17e97f9fc8a10ca5100", 17276751)
# V3Visualizer.Pool.Contract.get_burns_from("0x2418c488bc4b0c3cf1edfc7f6b572847f12ed24f", 17276751)
