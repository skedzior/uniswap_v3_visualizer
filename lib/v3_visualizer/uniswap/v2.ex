defmodule V3Visualizer.Uniswap.V2 do
  alias Decimal, as: D
  import V3Visualizer.Uniswap.Utils
  D.Context.set(%D.Context{D.Context.get() | precision: 80})

  def calculate_optimal_sando(amount_in, amount_out_min, reserve0, reserve1, zero_for_one, fee \\ 30) do
    swap_fee = 10000 - fee
    k = D.mult(reserve1, reserve0)
    negb = D.mult(-swap_fee, amount_in)

    fourac =
      D.new(40000 * swap_fee * amount_in)
      |> D.mult(k)
      |> D.div(amount_out_min)

    sqrt =
      D.new((swap_fee * amount_in) ** 2)
      |> D.add(fourac)
      |> D.sqrt()

    worst_r_in =
      D.add(negb, sqrt)
      |> D.div(20000)
      |> D.round(0, :floor)
      |> D.to_integer()

    new_r_out =
      D.div(k, worst_r_in)
      |> D.round(0, :floor)
      |> D.to_integer()

    case zero_for_one do
      true ->  %{new_r0: worst_r_in, new_r1: new_r_out, sando_in: worst_r_in - reserve0}
      false -> %{new_r0: new_r_out, new_r1: worst_r_in, sando_in: worst_r_in - reserve1}
    end
  end

  def calculate_pair_address(token0, token1) do
    v2_factory = decode_hex("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f")

    v2_pair_init_hash =
      decode_hex("0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f")

    {t0, t1} = sort_tokens(token0, token1)

    salt = ExKeccak.hash_256(decode_hex(t0) <> decode_hex(t1))

    "0x" <>
      (Web3x.Utils.keccak256(
         Base.decode16!("ff", case: :lower) <> v2_factory <> salt <> v2_pair_init_hash
       )
       |> String.slice(26..-1))
  end

  def get_pairs_from_path(path) do
    num_pairs = Enum.count(path) - 1

    Enum.reduce(1..num_pairs, {[], path}, fn x, {pair_list, path_pntr} ->
      token0 = Enum.at(path_pntr, 0)
      token1 = Enum.at(path_pntr, 1)

      pair = calculate_pair_address(token0, token1)

      {[pair | pair_list], Enum.slice(path_pntr, 1..-1)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # def decode_swap(data) do
  #   ABI.TypeDecoder.decode(data, [
  #     :address,
  #     {:uint, 256},
  #     {:uint, 256},
  #     {:array, :address},
  #     :bool
  #   ])
  # end

  def get_amount_out(amount_in, reserve_in, reserve_out, swap_fee \\ 30) do
    a_in_with_fee = amount_in * (10000 - swap_fee)
    numerator = a_in_with_fee * reserve_out
    denominator = a_in_with_fee + reserve_in * 10000

    amount_out =
      D.div(numerator, denominator)
      |> D.round(0, :floor)
      |> D.to_integer()

    new_reserve_out = reserve_out - amount_out
    new_reserve_in = reserve_in + amount_in

    {amount_out, new_reserve_in, new_reserve_out}
  end

  def get_amount_in(amount_out, reserve_in, reserve_out, swap_fee \\ 30) do
    new_reserve_out = reserve_out - amount_out

    numerator = reserve_in * amount_out * 10000
    denominator = new_reserve_out * (10000 - swap_fee)

    amount_in =
      (D.div(numerator, denominator)
       |> D.round(0, :floor)
       |> D.to_integer()) + 1

    new_reserve_in = reserve_in + amount_in

    {amount_in, new_reserve_in, new_reserve_out}
  end

  # def get_amounts_out(amount_in, reserve_in, reserve_out, swap_fee \\ 30) do
  #   a_in_with_fee = amount_in * (10000 - swap_fee)
  #   numerator = a_in_with_fee * reserve_out
  #   denominator = a_in_with_fee + (reserve_in * 10000)
  #   amount_out =
  #     D.div(numerator,denominator)
  #     |> D.round(0, :floor)
  #     |> D.to_integer()

  #   new_reserve_out = reserve_out - amount_out
  #   new_reserve_in = reserve_in + amount_in

  #   {amount_out, new_reserve_in, new_reserve_out}
  # end

  # def get_amounts_in(amount_out, reserve_in, reserve_out, swap_fee \\ 30) do
  #   new_reserve_out = reserve_out - amount_out

  #   numerator = reserve_in * amount_out * 10000
  #   denominator = new_reserve_out * (10000 - swap_fee)
  #   amount_in =
  #     (D.div(numerator, denominator)
  #     |> D.round(0, :floor)
  #     |> D.to_integer()) + 1

  #   new_reserve_in = reserve_in + amount_in

  #   {amount_in, new_reserve_in, new_reserve_out}
  # end
end
