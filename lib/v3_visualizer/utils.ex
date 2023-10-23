defmodule V3Visualizer.Utils do

  def decode_v2_swap(data) do
    [_address, amount_in, amount_out, path, _bool] =
      ABI.TypeDecoder.decode(data, %ABI.FunctionSelector{
        types: [
          :address,
          {:uint, 256},
          {:uint, 256},
          {:array, :address},
          :bool
        ]
      })

    decoded_path =
      path
      |> Enum.map(fn p ->
        address = "0x" <> String.downcase(Base.encode16(p))
        symbol = Redix.command!(:redix, ["HGET", "TokenList:#{address}", "symbol"])
        if symbol != nil, do: symbol, else: address
      end)

    %{
      path: decoded_path,
      amount_in: amount_in,
      amount_out: amount_out
    }
  end

  # V3 UTILS
  def decode_v3_swap(data) do
    [_address, amount_in, amount_out, raw_path, _bool] =
      ABI.TypeDecoder.decode(data, %ABI.FunctionSelector{
        types: [
          :address,
          {:uint, 256},
          {:uint, 256},
          :bytes,
          :bool
        ]
      })

    path = decode_v3_path(Base.encode16(raw_path))
    #pool_path = get_pools_from_path(path)

    %{
      path: path,
      amount_in: amount_in,
      amount_out: amount_out
    }
  end

  def get_pools_from_path(path) do

  end

  def decode_v3_path(path) do
    num_tokens = String.length(path) / 40 |> round()

    Enum.reduce(1..num_tokens, {[], String.downcase(path)}, fn x, {path_list, path_pntr} ->
      if x != num_tokens do
        {token, path_pntr} = String.split_at(path_pntr, 40)
        {fee, path_pntr} = String.split_at(path_pntr, 6)
        path_list = ["0x" <> token | path_list]

        {[hex_to_int(fee) | path_list], path_pntr}
      else
        {token, path_pntr} = String.split_at(path_pntr, 40)
        {["0x" <> token | path_list], path_pntr}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
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

  def calculate_token0_amount(liquidity, sp, sa, sb) do
    sp = max(min(sp, sb), sa)
    liquidity * (sb - sp) / (sp * sb)
  end

  def calculate_token1_amount(liquidity, sp, sa, sb) do
    sp = max(min(sp, sb), sa)
    liquidity * (sp - sa)
  end

  def to_int(hash) do
    case String.slice(hash, 0..1) do
      "0x" ->
        hash
        |> String.slice(2..-1)
        |> Integer.parse(16)
        |> elem(0)

      _ ->
        hash
        |> Integer.parse(16)
        |> elem(0)
    end
  end

  def hex_to_int(hex) do
    hex
    |> Integer.parse(16)
    |> elem(0)
  end

  def zero_pad(log_index) do
    index_length = String.length(log_index)

    case index_length do
      1 -> "000" <> log_index
      2 -> "00" <> log_index
      3 -> "0" <> log_index
      4 -> log_index
    end
  end
end
# V3Visualizer.Utils.to_int("0xa91e0b15d0164cec30d77807953daba82c8b722c")
# 0x00000000000000ef09f35ca07e4404f72b4f5688
