defmodule V3Visualizer.Pool.Orderbook do
  use GenServer
  # , only: [fun: 1]
  import Ex2ms
  import Bitwise

  alias V3Visualizer.{Pool, Utils}

  def start_link do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    :ets.new(:v3asks, [:ordered_set, :public, :named_table])
    :ets.new(:v3bids, [:ordered_set, :public, :named_table])
    {:ok, :ready}
  end

  def insert(side, tuple), do: :ets.insert(side, tuple)
  def lookup(side, key), do: :ets.lookup(side, key)
  def delete(side, key), do: :ets.delete(side, key)
  def delete_all_objects(side), do: :ets.delete_all_objects(String.to_atom(side))

  def set_orderbook(depth \\ true) do
    pool_data = Gql.get_pool_data("0x31AD100cEf4CbdBA0522A751541810d122d92120")

    {sqrtPriceX96, tick} = Contract.get_slot0("0x31AD100cEf4CbdBA0522A751541810d122d92120")

    sqrtPriceCurrent = sqrtPriceX96 / (1 <<< 96)
    priceCurrent = sqrtPriceCurrent ** 2
    decimal_diff = 18 - 6
    token1_price = 10 ** decimal_diff / priceCurrent
    token0_price = priceCurrent / 10 ** decimal_diff

    min_tick = 246_000
    max_tick = 259_800 - 1
    # TODO: method to map ticks
    tick_spacing = 200
    # token0 USDC token1 lyxe
    table_header = [["tick", "token0PriceLow", "token1PriceLow", "amount0", "amount1", "amounts0"]]

    {_, _, a1s, data} =
      min_tick..max_tick
      |> Enum.take_every(tick_spacing)
      |> Enum.reduce({0, 0, [], table_header}, fn t, {liquidity, amounts0, amounts1, data} ->
        tickRange = Web3x.Contract.call(:symbol, :ticks, [t]) |> Tuple.to_list()
        liquidity = liquidity + Enum.at(tickRange, 2)
        sqrtPriceLow = 1.0001 ** (t / 2)
        sqrtPriceHigh = 1.0001 ** ((t + tick_spacing) / 2)

        token1PriceLow = 10 ** decimal_diff / sqrtPriceLow ** 2
        token0PriceLow = sqrtPriceLow ** 2 / 10 ** decimal_diff

        amount0 =
          Utils.calculate_token0_amount(liquidity, sqrtPriceCurrent, sqrtPriceLow, sqrtPriceHigh)

        amount1 =
          Utils.calculate_token1_amount(liquidity, sqrtPriceCurrent, sqrtPriceLow, sqrtPriceHigh)

        amounts0 = amounts0 + amount0
        amounts1 = [amount1 | amounts1]

        new_data =
          data |> Enum.concat([[t, token0PriceLow, token1PriceLow, amount0, amount1, amounts0]])

        {liquidity, amounts0, amounts1, new_data}
      end)

    # BOTH TOKEN_PRICELOW VALUES ARE USED PER TICK ON V3 UI
    Table.format(data, padding: 2) |> IO.puts()

    {_, asks} =
      a1s
      |> Enum.filter(fn a -> a > 0 end)
      |> Enum.reduce({0, [["amount1", "amounts1"]]}, fn a, {amounts1, asks} ->
        amounts1 = a + amounts1
        new_data = asks |> Enum.concat([[a, amounts1]])
        {amounts1, new_data}
      end)
  end

  def set_orderbook(side, book) do
    side_atom = String.to_atom(side)
    :ets.delete_all_objects(side_atom)

    Enum.map(book[side], fn [p, q] ->
      price = Utils.parse_left(p)
      quan = Utils.parse_left(q)

      :ets.insert(side_atom, {price, quan, price * quan})
    end)
  end

  def calc_depth(side, book) do
    side_atom = String.to_atom(side)
    :ets.delete_all_objects(side_atom)

    side_cum_quote =
      Enum.reduce(book[side], {0, 0}, fn [p, q], {cum_quote, cum_base} ->
        price = Utils.parse_left(p)
        quan = Utils.parse_left(q)
        total_quote = price * quan
        cum_quote = cum_quote + total_quote
        cum_base = cum_base + quan
        :ets.insert(side_atom, {price, quan, total_quote, cum_base, cum_quote})
        {cum_quote, cum_base}
      end)
  end
end
