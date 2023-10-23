defmodule V3Visualizer.Uniswap.Utils do
  import Bitwise
  alias Decimal, as: D
  D.Context.set(%D.Context{D.Context.get() | precision: 80})

  def stringify(number, decimals \\ 18) do
    D.new(number)
    |> D.div(10 ** decimals)
    |> D.to_string()
  end

  def decimalize(number, decimals \\ 18) do
    D.new(number)
    |> D.mult(10 ** decimals)
    |> D.to_integer()
  end

  def to_rounded_integer(%D{} = number, rounding_option \\ :floor) do
    number
    |> D.round(0, rounding_option)
    |> D.to_integer()
  end

  def sort_tokens(token0, token1) do
    t0 = String.downcase(token0)
    t1 = String.downcase(token1)

    if t0 > t1 do
      {t1, t0}
    else
      {t0, t1}
    end
  end

  def sort_tokens([token0, token1] = path), do: sort_tokens(token0, token1)

  def is_zero_for_one(p0, p1) do
    {t0, t1} = sort_tokens(p0, p1)

    if p0 == t0 do
      true
    else
      false
    end
  end

  def is_zero_for_one([p0, p1] = path), do: is_zero_for_one(p0, p1)

  def decode_hex(value) do
    value
    |> String.slice(2..-1)
    |> String.downcase()
    |> Base.decode16!(case: :lower)
  end

  def hex_to_int(hex) do
    hex
    |> Integer.parse(16)
    |> elem(0)
  end

  def is_map(v) do
    case v do
      is_map -> [Poison.encode!(v, [])]
      is_list -> [Poison.encode!(v, [])]
      _ -> [v]
    end
  end

  def parse_quan(quan) do
    quan
    |> String.split(":")
    |> Enum.at(1)
    |> Float.parse()
    |> elem(0)
  end

  def parse_left(val) do
    val
    |> String.split(":")
    |> Enum.at(0)
    |> Float.parse()
    |> elem(0)
  end

  def parse_right(val) do
    val
    |> String.split(":")
    |> Enum.at(1)
    |> Float.parse()
    |> elem(0)
  end

  def parse_string(value) do
    Float.parse(value) |> elem(0)
  end

  def normalize_integer(integer) do
    integer
    |> :erlang.float_to_binary(decimals: 0)
    |> String.to_integer()
  end

  def check_map(v) do
    case v do
      is_map -> [Poison.encode!(v, [])]
      is_list -> [Poison.encode!(v, [])]
      _ -> [v]
    end
  end

  def list_to_map(list) do
    list
    |> Enum.chunk_every(2)
    |> Map.new(fn [k, v] -> {k, v} end)
  end

  # REDIX FUNCTIONS #
  def zrem_zadd(side, price, quan) do
    Redix.command!(:redix, [
      "ZREMRANGEBYSCORE",
      "CEX:Kucoin:pair:LYXE-USDT:book:#{side}",
      price,
      price
    ])

    Redix.command!(:redix, [
      "ZADD",
      "CEX:Kucoin:pair:LYXE-USDT:book:#{side}",
      price,
      "#{quan}"
    ])
  end

  def zrem_zadd_total(side, price, quan) do
    total = parse_string(price) * parse_string(quan)

    Redix.command!(:redix, [
      "ZREMRANGEBYSCORE",
      "CEX:Kucoin:pair:LYXE-USDT:book:#{side}",
      price,
      price
    ])

    Redix.command!(:redix, [
      "ZADD",
      "CEX:Kucoin:pair:LYXE-USDT:book:#{side}",
      price,
      "#{quan}:#{total}"
    ])
  end

  def process_upper_tick(key, event_type, liquidity, tick) do
    tick_exists = Redix.command!(:redix, ["ZRANGEBYSCORE", "#{key}Ticks", tick, tick])

    if tick_exists == [] do
      Redix.command!(:redix, [
        "ZADD",
        "#{key}Ticks",
        tick,
        Poison.encode!(%{liquidityGross: liquidity, liquidityNet: -liquidity})
      ])
    else
      Redix.command!(:redix, ["ZREMRANGEBYSCORE", "#{key}Ticks", tick, tick])

      new_tick = tick_exists |> Enum.at(0) |> Poison.decode!()
      lg = new_tick["liquidityGross"]
      ln = new_tick["liquidityNet"]

      new_liquidity =
        case event_type do
          "Mint" -> %{liquidityGross: lg + liquidity, liquidityNet: ln - liquidity}
          "Burn" -> %{liquidityGross: lg - liquidity, liquidityNet: ln + liquidity}
        end

      if new_liquidity.liquidityGross > 0 do
        Redix.command!(:redix, ["ZADD", "#{key}Ticks", tick, Poison.encode!(new_liquidity)])
      end
    end
  end

  def process_lower_tick(key, event_type, liquidity, tick) do
    tick_exists = Redix.command!(:redix, ["ZRANGEBYSCORE", "#{key}Ticks", tick, tick])

    if tick_exists == [] do
      Redix.command!(:redix, [
        "ZADD",
        "#{key}Ticks",
        tick,
        Poison.encode!(%{liquidityGross: liquidity, liquidityNet: liquidity})
      ])
    else
      Redix.command!(:redix, ["ZREMRANGEBYSCORE", "#{key}Ticks", tick, tick])

      new_tick = tick_exists |> Enum.at(0) |> Poison.decode!()
      lg = new_tick["liquidityGross"]
      ln = new_tick["liquidityNet"]

      new_liquidity =
        case event_type do
          "Mint" -> %{liquidityGross: lg + liquidity, liquidityNet: ln + liquidity}
          "Burn" -> %{liquidityGross: lg - liquidity, liquidityNet: ln - liquidity}
        end

      if new_liquidity.liquidityGross > 0 do
        Redix.command!(:redix, ["ZADD", "#{key}Ticks", tick, Poison.encode!(new_liquidity)])
      end
    end
  end

  def generate_v3_orderbook(key, block_idx \\ "+inf") do
    Redix.command!(:redix, ["ZREMRANGEBYSCORE", "#{key}Ticks", "-inf", "+inf"])

    Redix.command!(:redix, ["ZRANGEBYSCORE", "#{key}Event", "-inf", block_idx])
    |> Enum.map(fn e ->
      event = e |> String.replace(".", "-")
      event_type = e |> String.split(":") |> Enum.at(0)

      case event_type do
        "Mint" ->
          {"Mint",
           Redix.command!(:redix, ["HMGET", "#{key}#{event}", "amount", "tickLower", "tickUpper"])}

        "Burn" ->
          {"Burn",
           Redix.command!(:redix, ["HMGET", "#{key}#{event}", "amount", "tickLower", "tickUpper"])}
      end
    end)
    |> Enum.filter(fn {event_type, [liq, lt, ut]} -> liq != "0" end)
    |> Enum.map(fn {event_type, [liq, lt, ut]} ->
      liquidity = String.to_integer(liq)

      process_lower_tick(key, event_type, liquidity, lt)
      process_upper_tick(key, event_type, liquidity, ut)
    end)
  end

  def get_last_swap_before_block(key, target_block) do
    last_swap =
      Redix.command!(:redix, ["XREVRANGE", "#{key}SwapStream", target_block - 1, "-", "COUNT", 1])
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

    {tick_at_last_swap, sqrt_price_x96}
  end

  def reset_pool_streams(key) do
    burns =
      Redix.command!(:redix, ["keys", "#{key}Burn:*"])
      |> Enum.map(fn b ->
        burn = b |> String.split(":") |> Enum.at(2) |> String.replace("-", ".")
        Redix.command!(:redix, ["ZADD", "#{key}Event", burn, "Burn:#{burn}"])
      end)

    mints =
      Redix.command!(:redix, ["keys", "#{key}Mint:*"])
      |> Enum.map(fn m ->
        mint = m |> String.split(":") |> Enum.at(2) |> String.replace("-", ".")
        Redix.command!(:redix, ["ZADD", "#{key}Event", mint, "Mint:#{mint}"])
      end)

    swaps =
      Redix.command!(:redix, ["keys", "#{key}Swap:*"])
      |> Enum.map(fn s ->
        stream_id = s |> String.split(":") |> Enum.at(2) |> String.replace("-", ".")
        Redix.command!(:redix, ["ZADD", "#{key}Event", stream_id, "Swap:#{stream_id}"])
      end)

    Redix.command!(:redix, ["DEL", "#{key}SwapStream"])

    swap_stream =
      Redix.command!(:redix, ["ZRANGEBYSCORE", "#{key}Event", "-inf", "+inf"])
      |> Enum.filter(fn e -> e |> String.split(":") |> Enum.at(0) == "Swap" end)
      |> Enum.map(fn e ->
        stream_id = e |> String.replace(".", "-") |> String.split(":") |> Enum.at(1)

        [timestamp, sqrtPriceX96, tick, id, amount0, amount1] =
          Redix.command!(:redix, [
            "HMGET",
            "#{key}Swap:#{stream_id}",
            "timestamp",
            "sqrtPriceX96",
            "tick",
            "id",
            "amount0",
            "amount1"
          ])

        Redix.command!(:redix, [
          "XADD",
          "#{key}SwapStream",
          stream_id,
          "tick",
          tick,
          "timestamp",
          timestamp,
          "sqrtPriceX96",
          sqrtPriceX96,
          "id",
          id,
          "amount0",
          amount0,
          "amount1",
          amount1
        ])
      end)

    Redix.command!(:redix, ["ZREMRANGEBYSCORE", "#{key}Ticks2", "-inf", "+inf"])

    Redix.command!(:redix, ["DEL", "#{key}StateStream"])

    events =
      Redix.command!(:redix, ["ZRANGEBYSCORE", "#{key}Event", "-inf", "+inf"])
      |> Enum.filter(fn e -> e |> String.split(":") |> Enum.at(0) != "Swap" end)
      |> Enum.map(fn e ->
        event = e |> String.replace(".", "-")
        event_type = e |> String.split(":") |> Enum.at(0)

        case event_type do
          "Mint" ->
            {"Mint",
             Redix.command!(:redix, [
               "HMGET",
               "#{key}#{event}",
               "amount",
               "tickLower",
               "tickUpper"
             ]), event}

          "Burn" ->
            {"Burn",
             Redix.command!(:redix, [
               "HMGET",
               "#{key}#{event}",
               "amount",
               "tickLower",
               "tickUpper"
             ]), event}
        end
      end)
      |> Enum.filter(fn {event_type, [liq, lt, ut], event} -> liq != "0" end)
      |> Enum.map(fn {event_type, [liq, lt, ut], event} ->
        stream_id = event |> String.split(":") |> Enum.at(1)
        liquidity = String.to_integer(liq)

        lower_tick_exists = Redix.command!(:redix, ["ZRANGEBYSCORE", "#{key}Ticks2", lt, lt])
        upper_tick_exists = Redix.command!(:redix, ["ZRANGEBYSCORE", "#{key}Ticks2", ut, ut])

        new_tick_lower =
          if lower_tick_exists == [] do
            Redix.command!(:redix, [
              "ZADD",
              "#{key}Ticks2",
              lt,
              Poison.encode!(%{tick: lt, liquidityGross: liquidity, liquidityNet: liquidity})
            ])
          else
            Redix.command!(:redix, ["ZREMRANGEBYSCORE", "#{key}Ticks2", lt, lt])
            tick = lower_tick_exists |> Enum.at(0) |> Poison.decode!()
            lg = tick["liquidityGross"]
            ln = tick["liquidityNet"]

            new_liquidity =
              case event_type do
                "Mint" ->
                  %{tick: lt, liquidityGross: lg + liquidity, liquidityNet: ln + liquidity}

                "Burn" ->
                  %{tick: lt, liquidityGross: lg - liquidity, liquidityNet: ln - liquidity}
              end

            if new_liquidity.liquidityGross > 0 do
              Redix.command!(:redix, ["ZADD", "#{key}Ticks2", lt, Poison.encode!(new_liquidity)])
            end
          end

        new_tick_upper =
          if upper_tick_exists == [] do
            Redix.command!(:redix, [
              "ZADD",
              "#{key}Ticks2",
              ut,
              Poison.encode!(%{tick: ut, liquidityGross: liquidity, liquidityNet: -liquidity})
            ])
          else
            Redix.command!(:redix, ["ZREMRANGEBYSCORE", "#{key}Ticks2", ut, ut])
            tick = upper_tick_exists |> Enum.at(0) |> Poison.decode!()
            lg = tick["liquidityGross"]
            ln = tick["liquidityNet"]

            new_liquidity =
              case event_type do
                "Mint" ->
                  %{tick: ut, liquidityGross: lg + liquidity, liquidityNet: ln - liquidity}

                "Burn" ->
                  %{tick: ut, liquidityGross: lg - liquidity, liquidityNet: ln + liquidity}
              end

            if new_liquidity.liquidityGross > 0 do
              Redix.command!(:redix, ["ZADD", "#{key}Ticks2", ut, Poison.encode!(new_liquidity)])
            end
          end

        tick_snapshot = Redix.command!(:redix, ["ZRANGEBYSCORE", "#{key}Ticks2", "-inf", "+inf"])

        decoded_tick_snapshot =
          tick_snapshot
          |> Enum.map(fn ts -> Poison.decode!(ts) end)
          |> Poison.encode!()

        Redix.command!(:redix, [
          "XADD",
          "#{key}StateStream",
          stream_id,
          "ticks",
          decoded_tick_snapshot
        ])
      end)
  end
end
