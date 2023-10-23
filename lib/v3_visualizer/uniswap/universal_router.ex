defmodule V3Visualizer.Uniswap.UniversalRouter do
  require Logger
  import V3Visualizer.Uniswap.Utils
  alias V3Visualizer.Uniswap.{V2, V3, Utils}

  defmodule Pair do
    defstruct [
      # :dex,
      # :key,
      # :symbol,
      :token0,
      :token1,
      :reserve0,
      :reserve1,
      :price0,
      :price1,
      :address,
      :fee
    ]

    def is_zero_or_one(%Pair{token0: t0, token1: t1} = pair, token) do
      if String.downcase(token) == t0, do: 0, else: 1
    end

    def get_price0(reserve0, reserve1), do: reserve1 / reserve0
    def get_price0(%Pair{} = pair), do: get_price0(pair.reserve0, pair.reserve1)

    def get_price1(reserve0, reserve1), do: reserve0 / reserve1
    def get_price1(%Pair{} = pair), do: get_price0(pair.reserve0, pair.reserve1)
  end

  defmodule Pool do
    defstruct [
      # :dex,
      # :key,
      # :symbol,
      :token0,
      :token1,
      :tick_state,
      :tick_spacing,
      :tick_list,
      :sqrtp_x96,
      :address,
      :fee
    ]

    def is_zero_or_one(%Pool{token0: t0, token1: t1} = pool, token) do
      if String.downcase(token) == t0, do: 0, else: 1
    end
  end

  def decode_router_tx(pending_tx) do
    input = String.slice(pending_tx.input, 2..-1)
    {method_id, raw_data} = String.split_at(input, 8)

    [commands, inputs, deadline] =
      raw_data
      |> Base.decode16!(case: :lower)
      |> ABI.TypeDecoder.decode([
        :bytes,
        {:array, :bytes},
        {:uint, 256}
      ])

    decoded_swaps =
      Enum.zip([:binary.bin_to_list(commands), inputs])
      |> Enum.map(fn {c, input} ->
        case c do
          0 -> decode_swap({:V3_exact_in, input})
          1 -> decode_swap({:V3_exact_out, input})
          8 -> decode_swap({:V2_exact_in, input})
          9 -> decode_swap({:V2_exact_out, input})
          _ -> nil #{:SKIP, nil}
        end
      end)
      |> Enum.filter(fn s -> s != nil end)
      Logger.info("decoded_swaps: #{inspect(decoded_swaps)}")
    # TODO: add func to take swaps and blocknumber to add prices, reserves, and ticks
  end

  def decode_inputs({:V3_exact_in, input}) do
    [_address, amount_in, amount_out, path, _bool] =
      ABI.TypeDecoder.decode(input, [
        :address,
        {:uint, 256},
        {:uint, 256},
        :bytes,
        :bool
      ])
  end

  def decode_inputs({:V2_exact_in, input}) do
    ABI.TypeDecoder.decode(input, [
      :address,
      {:uint, 256},
      {:uint, 256},
      {:array, :address},
      :bool
    ])
  end

  def decode_swap({:V2_exact_in, input}) do
    path =
      decode_inputs({:V2_exact_in, input})
      |> Enum.at(3)
      |> Enum.map(&("0x" <> Base.encode16(&1)))
      |> Enum.map(&String.downcase(&1))

    pairs = create_pairs_from_path(path)

    {:V2, %{path: path, pairs: pairs}}
  end

  def decode_swap({:V3_exact_in, input}) do
    decoded_inputs = decode_inputs({:V3_exact_in, input})

    amount_in = Enum.at(decoded_inputs, 1)
    amount_out_min = Enum.at(decoded_inputs, 2)

    path =
      Enum.at(decoded_inputs, 3)
      |> Base.encode16()
      |> V3.decode_path()

    pools = create_pools_from_path(path)

    # vic_swap = %Swap{
    #   amount_in: amount_in,
    #   amount_min_max: amount_out_min,
    #   path: path
    #   # pools: pools,
    #   # zero_for_one: is_zero_for_one(p0, p1)
    #   # flagged:  add logic to check if token in path is target token
    #   #           and how to flag a single target pool if count > 1
    # }

    {:V3, %{path: path, pools: pools}}
  end

  def decode_swap(_) do
    IO.inspect("skip")
  end

  def create_pools_from_path(path) do
    num_pools = ((Enum.count(path) - 1) / 2) |> round()
    # TODO: should this be converted to reduce_while with slice instead of mathing length?
    Enum.reduce(1..num_pools, {[], path}, fn x, {pool_list, path_pntr} ->
      token0 = Enum.at(path_pntr, 0)
      fee = Enum.at(path_pntr, 1)
      token1 = Enum.at(path_pntr, 2)

      pool = create_pool(token0, token1, fee)

      {[pool | pool_list], Enum.slice(path_pntr, 2..-1)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def create_pool(token0, token1, fee) do
    {t0, t1} = sort_tokens(token0, token1)
    # get ticks and sqrtp
    # add block
    # create pool key: LYXE_ETH_3000
    %Pool{
      # key: ,
      address: V3.calculate_pool_address(token0, token1, fee),
      token0: t0,
      token1: t1,
      # path: [token0, token1],
      # sqrtp_x96: 5829218124412853326439738033,
      # tick_state: tick_state,
      # tick_list: tick_list,
      fee: fee,
      tick_spacing: round(fee / 50)
    }
  end

  def create_pairs_from_path(path) do
    num_pairs = Enum.count(path) - 1

    Enum.reduce(1..num_pairs, {[], path}, fn x, {pair_list, path_pntr} ->
      token0 = Enum.at(path_pntr, 0)
      token1 = Enum.at(path_pntr, 1)

      pair = create_pair(token0, token1)

      {[pair | pair_list], Enum.slice(path_pntr, 1..-1)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def create_pair(token0, token1) do
    {t0, t1} = sort_tokens(token0, token1)
    # get reserves
    # add block
    # create key: LYXE_ETH
    %Pair{
      # key: ,
      address: V2.calculate_pair_address(token0, token1),
      token0: t0,
      token1: t1,
      # reserve0: r0,
      # reserve1: r1,
      fee: 30
    }
  end
end
