defmodule V3Visualizer.Uniswap.V3 do
  alias Decimal, as: D
  import Math
  import V3Visualizer.Uniswap.Utils
  alias V3Visualizer.Uniswap.Utils
  import Bitwise
  D.Context.set(%D.Context{D.Context.get() | precision: 80})

  @q96 2 ** 96
  @uint160_max 1_461_501_637_330_902_918_203_684_832_716_283_019_655_932_542_976
  @uint256_max 115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935

  @min_tick -887_272
  @max_tick -@min_tick

  @min_sqrt_ratio 4_295_128_739
  @max_sqrt_ratio 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342

  @bitwise_ops [
    [0x2, 0xFFF97272373D413259A46990580E213A],
    [0x4, 0xFFF2E50F5F656932EF12357CF3C7FDCC],
    [0x8, 0xFFE5CACA7E10E4E61C3624EAA0941CD0],
    [0x10, 0xFFCB9843D60F6159C9DB58835C926644],
    [0x20, 0xFF973B41FA98C081472E6896DFB254C0],
    [0x40, 0xFF2EA16466C96A3843EC78B326B52861],
    [0x80, 0xFE5DEE046A99A2A811C461F1969C3053],
    [0x100, 0xFCBE86C7900A88AEDCFFC83B479AA3A4],
    [0x200, 0xF987A7253AC413176F2B074CF7815E54],
    [0x400, 0xF3392B0822B70005940C7A398E4B70F3],
    [0x800, 0xE7159475A2C29B7443B29C7FA6E889D9],
    [0x1000, 0xD097F3BDFD2022B8845AD8F792AA5825],
    [0x2000, 0xA9F746462D870FDF8A65DC1F90E061E5],
    [0x4000, 0x70D869A156D2A1B890BB3DF62BAF32F7],
    [0x8000, 0x31BE135F97D08FD981231505542FCFA6],
    [0x10000, 0x9AA508B5B7A84E1C677DE54F3E99BC9],
    [0x20000, 0x5D6AF8DEDB81196699C329225EE604],
    [0x40000, 0x2216E584F5FA1EA926041BEDFE98],
    [0x80000, 0x48A170391F7DC42444E8FA2]
  ]

  @sqrt_ratios [
    [7, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF],
    [6, 0xFFFFFFFFFFFFFFFF],
    [5, 0xFFFFFFFF],
    [4, 0xFFFF],
    [3, 0xFF],
    [2, 0xF],
    [1, 0x3],
    [0, 0x1]
  ]

  def get_next_tick_range(tick, tick_spacing, zero_for_one) do
    is_negative = tick < 0
    r = rem(tick, tick_spacing)

    cond do
      !zero_for_one && !is_negative -> [tick - r + tick_spacing, tick - r + 2 * tick_spacing]
      !zero_for_one && is_negative -> [tick + -r, tick + -r + tick_spacing]
      zero_for_one && !is_negative -> [tick - r + 2 * tick_spacing, tick - r + tick_spacing]
      zero_for_one && is_negative -> [tick + -r - tick_spacing, tick + -r - 2 * tick_spacing]
    end
  end

  def get_current_tick_range(tick, tick_spacing, zero_for_one) do
    is_negative = tick < 0
    r = rem(tick, tick_spacing)

    cond do
      !zero_for_one && !is_negative -> [tick - r, tick - r + tick_spacing]
      !zero_for_one && is_negative -> [tick + -r - tick_spacing, tick + -r]
      zero_for_one && !is_negative -> [tick - r + tick_spacing, tick - r]
      zero_for_one && is_negative -> [tick + -r, tick + -r - tick_spacing]
    end
  end

  def get_tick_list(key, block \\ nil) do
    key =
      cond do
        is_nil(block) -> "#{key}:Ticks"
        true -> "#{key}:Ticks:#{block}"
      end

    Redix.command!(:redix, ["ZRANGE", key, "-inf", "+inf", "BYSCORE", "WITHSCORES"])
    |> Enum.map(&String.to_integer(&1))
    |> Enum.chunk_every(2)
    |> Enum.map(&[Enum.at(&1, 1), Enum.at(&1, 0)])
  end

  def generate_tick_state_from_list(tick_list) do
    tick_count = Enum.count(tick_list)

    tick_list
    |> Enum.with_index()
    |> Enum.reduce_while({0, []}, fn {[t, l], i}, {liquidity, data} ->
      liquidity = liquidity + l
      ht = Enum.at(tick_list, i + 1)

      new_data = Enum.concat(data, [[t, Enum.at(ht, 0), liquidity]])

      if i == tick_count - 2 do
        {:halt, {liquidity, new_data}}
      else
        {:cont, {liquidity, new_data}}
      end
    end)
    |> elem(1)
  end

  def generate_jit_tick_state_by_key(
        key,
        target_block,
        next_sqrtp,
        amount0,
        amount1,
        jit_tick_low,
        jit_tick_high,
        zero_for_one \\ true
      ) do
    jit_liquidity =
      get_liquidity_for_amounts(
        next_sqrtp,
        tick_to_sqrt_ratio(jit_tick_low),
        tick_to_sqrt_ratio(jit_tick_high),
        amount0,
        amount1
      )

    target_ticks =
      get_target_ticks_at_block(key, target_block)
      |> Enum.map(fn [t, l] ->
        cond do
          t == jit_tick_low -> [t, l + jit_liquidity]
          t == jit_tick_high -> [t, l + -jit_liquidity]
          true -> [t, l]
        end
      end)

    low_index = Enum.find_index(target_ticks, fn [t, l] -> t == jit_tick_low end)
    high_index = Enum.find_index(target_ticks, fn [t, l] -> t == jit_tick_high end)

    target_ticks =
      if high_index == nil,
        do: Enum.concat(target_ticks, [[jit_tick_high, -jit_liquidity]]),
        else: target_ticks

    target_ticks =
      if low_index == nil,
        do: Enum.concat(target_ticks, [[jit_tick_low, jit_liquidity]]),
        else: target_ticks

    tick_count = Enum.count(target_ticks)
    target_ticks = Enum.sort_by(target_ticks, & &1, :asc)

    {_liq, data} =
      target_ticks
      |> Enum.with_index()
      |> Enum.reduce_while({0, []}, fn {[t, l], i}, {liquidity, data} ->
        liquidity = liquidity + l
        [ht, _] = Enum.at(target_ticks, i + 1)

        new_tick =
          if t >= jit_tick_low && jit_tick_high >= ht do
            liq_fraction = D.div(jit_liquidity, liquidity)

            [t, ht, liquidity, liq_fraction]
          else
            [t, ht, liquidity, 0]
          end

        new_data = Enum.concat(data, [new_tick])

        if i == tick_count - 2 do
          {:halt, {liquidity, new_data}}
        else
          {:cont, {liquidity, new_data}}
        end
      end)

    if zero_for_one,
      do: Enum.reverse(data),
      else: data
  end

  def generate_jit_tick_state(
        tick_state,
        next_sqrtp,
        amount0,
        amount1,
        jit_tick_low,
        jit_tick_high,
        zero_for_one \\ true
      ) do
    jit_liquidity =
      get_liquidity_for_amounts(
        next_sqrtp,
        tick_to_sqrt_ratio(jit_tick_low),
        tick_to_sqrt_ratio(jit_tick_high),
        amount0,
        amount1
      )

    target_ticks =
      Enum.map(tick_state, fn [t, l] ->
        cond do
          t == jit_tick_low -> [t, l + jit_liquidity]
          t == jit_tick_high -> [t, l + -jit_liquidity]
          true -> [t, l]
        end
      end)

    low_index = Enum.find_index(target_ticks, fn [t, l] -> t == jit_tick_low end)
    high_index = Enum.find_index(target_ticks, fn [t, l] -> t == jit_tick_high end)

    target_ticks =
      if high_index == nil,
        do: Enum.concat(target_ticks, [[jit_tick_high, -jit_liquidity]]),
        else: target_ticks

    target_ticks =
      if low_index == nil,
        do: Enum.concat(target_ticks, [[jit_tick_low, jit_liquidity]]),
        else: target_ticks

    tick_count = Enum.count(target_ticks)
    target_ticks = Enum.sort_by(target_ticks, & &1, :asc)

    {_liq, data} =
      target_ticks
      |> Enum.with_index()
      |> Enum.reduce_while({0, []}, fn {[t, l], i}, {liquidity, data} ->
        liquidity = liquidity + l
        [ht, _] = Enum.at(target_ticks, i + 1)

        new_tick =
          if t >= jit_tick_low && jit_tick_high >= ht do
            liq_fraction = D.div(jit_liquidity, liquidity)

            [t, ht, liquidity, liq_fraction]
          else
            [t, ht, liquidity, 0]
          end

        new_data = Enum.concat(data, [new_tick])

        if i == tick_count - 2 do
          {:halt, {liquidity, new_data}}
        else
          {:cont, {liquidity, new_data}}
        end
      end)

    if zero_for_one,
      do: Enum.reverse(data),
      else: data
  end

  def generate_jit_tick_list(tick_list, jit_tick_low, jit_tick_high, jit_liquidity) do
    jit_tick_list =
      Enum.map(tick_list, fn [t, l] ->
        cond do
          t == jit_tick_low -> [t, l + jit_liquidity, jit_liquidity]
          t == jit_tick_high -> [t, l + -jit_liquidity, -jit_liquidity]
          true -> [t, l, 0]
        end
      end)

    low_index = Enum.find_index(jit_tick_list, fn [t, _l, _jl] -> t == jit_tick_low end)
    high_index = Enum.find_index(jit_tick_list, fn [t, _l, _jl] -> t == jit_tick_high end)

    jit_tick_list =
      cond do
        is_nil(high_index) && is_nil(low_index) ->
          Enum.concat(jit_tick_list, [
            [jit_tick_low, jit_liquidity, jit_liquidity],
            [jit_tick_high, -jit_liquidity, -jit_liquidity]
          ])

        is_nil(high_index) ->
          Enum.concat(jit_tick_list, [[jit_tick_high, -jit_liquidity, -jit_liquidity]])

        is_nil(low_index) ->
          Enum.concat(jit_tick_list, [[jit_tick_low, jit_liquidity, jit_liquidity]])

        true ->
          jit_tick_list
      end

    Enum.sort_by(jit_tick_list, & &1, :asc)
  end

  def generate_jit_tick_list(tick_list, sqrtp, amount0, amount1, jit_tick_low, jit_tick_high) do
    jit_liquidity =
      get_liquidity_for_amounts(
        sqrtp,
        tick_to_sqrt_ratio(jit_tick_low),
        tick_to_sqrt_ratio(jit_tick_high),
        amount0,
        amount1
      )

    generate_jit_tick_list(tick_list, jit_tick_low, jit_tick_high, jit_liquidity)
  end

  def generate_jit_tick_state_from_list(jit_tick_list) do
    tick_count = Enum.count(jit_tick_list)

    jit_tick_list
    |> Enum.with_index()
    |> Enum.reduce_while({0, 0, []}, fn {[t, l, jl], i}, {liquidity, jl_pntr, data} ->
      liquidity = liquidity + l
      [ht, _l, _jl] = Enum.at(jit_tick_list, i + 1)
      jl_pntr = jl_pntr + jl

      new_tick =
        if jl_pntr > 0 do
          liq_fraction = D.div(jl_pntr, liquidity)

          [t, ht, liquidity, liq_fraction]
        else
          [t, ht, liquidity, 0]
        end

      new_data = Enum.concat(data, [new_tick])

      if i == tick_count - 2 do
        {:halt, {liquidity, jl_pntr, new_data}}
      else
        {:cont, {liquidity, jl_pntr, new_data}}
      end
    end)
    |> elem(2)
  end

  def generate_tick_state_at_block(
        key,
        target_block,
        zero_for_one \\ true
      ) do
    target_ticks = get_target_ticks_at_block(key, target_block)

    tick_count = Enum.count(target_ticks)

    {_liq, data} =
      target_ticks
      |> Enum.with_index()
      |> Enum.reduce_while({0, []}, fn {[t, l], i}, {liquidity, data} ->
        liquidity = liquidity + l
        ht = Enum.at(target_ticks, i + 1)

        new_data = Enum.concat(data, [[t, Enum.at(ht, 0), liquidity]])

        if i == tick_count - 2 do
          {:halt, {liquidity, new_data}}
        else
          {:cont, {liquidity, new_data}}
        end
      end)

    if zero_for_one,
      do: Enum.reverse(data),
      else: data
  end

  def get_target_ticks_at_block(key, target_block) do
    Redix.command!(:redix, ["XREVRANGE", "#{key}StateStream", target_block, "-", "COUNT", 1])
    |> Enum.at(0)
    |> Enum.at(1)
    |> Enum.at(1)
    |> Poison.decode!()
    |> Enum.map(fn t -> [String.to_integer(t["tick"]), t["liquidityNet"]] end)
  end

  def get_pools_from_path(path) do
    num_pools = ((Enum.count(path) - 1) / 2) |> round()

    Enum.reduce(1..num_pools, {[], path}, fn x, {pool_list, path_pntr} ->
      token0 = Enum.at(path_pntr, 0)
      fee = Enum.at(path_pntr, 1)
      token1 = Enum.at(path_pntr, 2)

      pool = calculate_pool_address(token0, token1, fee)

      {[pool | pool_list], Enum.slice(path_pntr, 2..-1)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def calculate_pool_address(token0, token1, fee) do
    v3_factory = decode_hex("0x1F98431c8aD98523631AE4a59f267346ea31F984")

    v3_pool_init_hash =
      decode_hex("0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54")

    {t0, t1} = sort_tokens(token0, token1)

    salt =
      ABI.TypeEncoder.encode_raw(
        [
          t0 |> String.slice(2..-1) |> Base.decode16!(case: :lower),
          t1 |> String.slice(2..-1) |> Base.decode16!(case: :lower),
          fee
        ],
        [
          :address,
          :address,
          {:uint, 24}
        ]
      )
      |> Web3x.Utils.keccak256()
      |> String.slice(2..-1)
      |> Base.decode16!(case: :lower)

    "0x" <>
      (Web3x.Utils.keccak256(
         Base.decode16!("ff", case: :lower) <> v3_factory <> salt <> v3_pool_init_hash
       )
       |> String.slice(26..-1))
  end

  def compute_swap_step(
        current_sqrtp_x96,
        target_sqrtp_x96,
        liquidity,
        amount_remaining,
        fee_pips
      ) do
    zeroForOne = current_sqrtp_x96 >= target_sqrtp_x96
    exactIn = amount_remaining >= 0

    {amountIn, amountOut, sqrtRatioNextX96} =
      if exactIn do
        amountRemainingLessFee =
          D.mult(amount_remaining, 10 ** 6 - fee_pips)
          |> D.div(10 ** 6)
          |> D.round(0, :floor)
          |> D.to_integer()

        amountIn =
          if zeroForOne,
            do: get_amount0_delta(target_sqrtp_x96, current_sqrtp_x96, liquidity, true),
            else: get_amount1_delta(current_sqrtp_x96, target_sqrtp_x96, liquidity, true)

        sqrtRatioNextX96 =
          if amountRemainingLessFee >= amountIn,
            do: target_sqrtp_x96,
            else:
              get_next_sqrt_price_from_input(
                amountRemainingLessFee,
                liquidity,
                current_sqrtp_x96,
                zeroForOne
              )

        # IO.inspect({amountIn, sqrtRatioNextX96}, label: "amountIn, sqrtRatioNextX96")
        {amountIn, nil, sqrtRatioNextX96}
      else
        amountOut =
          if zeroForOne,
            do: get_amount1_delta(target_sqrtp_x96, current_sqrtp_x96, liquidity, false),
            else: get_amount0_delta(current_sqrtp_x96, target_sqrtp_x96, liquidity, false)

        sqrtRatioNextX96 =
          if -amount_remaining >= amountOut,
            do: target_sqrtp_x96,
            else:
              get_next_sqrt_price_from_output(
                -amount_remaining,
                liquidity,
                current_sqrtp_x96,
                zeroForOne
              )

        # IO.inspect({amountOut, sqrtRatioNextX96}, label: "amountOut, sqrtRatioNextX96")
        {nil, amountOut, sqrtRatioNextX96}
      end

    max = target_sqrtp_x96 == sqrtRatioNextX96

    {amountIn, amountOut} =
      if zeroForOne do
        amountIn =
          if max && exactIn,
            do: amountIn,
            else: get_amount0_delta(sqrtRatioNextX96, current_sqrtp_x96, liquidity, true)

        amountOut =
          if max && !exactIn,
            do: amountOut,
            else: get_amount1_delta(sqrtRatioNextX96, current_sqrtp_x96, liquidity, false)

        {amountIn, amountOut}
      else
        amountIn =
          if max && exactIn,
            do: amountIn,
            else: get_amount1_delta(current_sqrtp_x96, sqrtRatioNextX96, liquidity, true)

        amountOut =
          if max && !exactIn,
            do: amountOut,
            else: get_amount0_delta(current_sqrtp_x96, sqrtRatioNextX96, liquidity, false)

        {amountIn, amountOut}
      end

    amountOut =
      if !exactIn && amountOut > -amount_remaining,
        do: -amount_remaining,
        else: amountOut

    feeAmount =
      if exactIn && sqrtRatioNextX96 != target_sqrtp_x96,
        do: amount_remaining - amountIn,
        else:
          D.mult(amountIn, fee_pips)
          |> D.div(10 ** 6 - fee_pips)
          |> D.round(0, :ceiling)
          |> D.to_integer()

    {sqrtRatioNextX96, amountIn, amountOut, feeAmount}
  end

  def exact_in_swap(
        tick_state,
        pool_fee,
        init_sqrtp_x96,
        amount_specified,
        amount_out_min,
        zero_for_one,
        sqrtp_limit_x96 \\ nil
      ) do
    {nextSqrtRatioX96, amount_in, amount_out} =
      swap(tick_state, pool_fee, init_sqrtp_x96, amount_specified, zero_for_one, sqrtp_limit_x96)

    if amount_out_min > amount_out do
      {:revert, "Too little received", amount_out}
    else
      {nextSqrtRatioX96, amount_in, amount_out}
    end
  end

  def exact_out_swap(
        tick_state,
        pool_fee,
        init_sqrtp_x96,
        amount_specified,
        amount_in_max,
        zero_for_one,
        sqrtp_limit_x96 \\ nil
      ) do
    {nextSqrtRatioX96, amount_in, amount_out} =
      swap(tick_state, pool_fee, init_sqrtp_x96, amount_specified, zero_for_one, sqrtp_limit_x96)

    if amount_in > amount_in_max do
      {:revert, "Too much requested", amount_in}
    else
      {nextSqrtRatioX96, amount_in, amount_out}
    end
  end

  def get_tick_index_from_state(sqrtp, tick_state) do
    tick = sqrt_ratio_to_tick(sqrtp)

    tick_state
    |> Enum.find_index(fn ts ->
      lt = Enum.at(ts, 0)
      ht = Enum.at(ts, 1)
      lt <= tick && tick < ht
    end)
  end

  def get_directional_tick_state(tick_state, sqrtp_x96, zero_for_one) do
    if zero_for_one do
      tick_state = Enum.reverse(tick_state)
      current_tick_index = get_tick_index_from_state(sqrtp_x96, tick_state)

      tick_state
      |> Enum.slice(current_tick_index..-1)
      |> Enum.map(fn ts ->
        [Enum.at(ts, 0) | Enum.slice(ts, 2..Enum.count(ts))]
      end)
    else
      current_tick_index = get_tick_index_from_state(sqrtp_x96, tick_state)

      tick_state
      |> Enum.slice(current_tick_index..-1)
      |> Enum.map(fn ts ->
        Enum.slice(ts, 1..Enum.count(ts))
      end)
    end
  end

  def swap(
        tick_state,
        pool_fee,
        curr_sqrtp_x96,
        amount_specified,
        zero_for_one,
        sqrtp_limit_x96 \\ nil
      ) do
    tick_state = get_directional_tick_state(tick_state, curr_sqrtp_x96, zero_for_one)

    {_, nextSqrtRatioX96, amount_in, amount_out, _} =
      tick_state
      |> Enum.reduce_while({amount_specified, curr_sqrtp_x96, 0, 0, 0}, fn [tick, liq],
                                                                           {am_specified_remaining,
                                                                            sqrtRatioNextX96,
                                                                            ams_in, ams_out,
                                                                            fees} ->
        next_sqrtp_pntr = tick_to_sqrt_ratio(tick)

        next_sqrtp_pntr =
          cond do
            sqrtp_limit_x96 == nil -> next_sqrtp_pntr
            zero_for_one && next_sqrtp_pntr < sqrtp_limit_x96 -> sqrtp_limit_x96
            !zero_for_one && next_sqrtp_pntr > sqrtp_limit_x96 -> sqrtp_limit_x96
            true -> next_sqrtp_pntr
          end

        exact_input = amount_specified > 0

        {sqrtRatioNextX96, am_in, am_out, fee} =
          compute_swap_step(
            sqrtRatioNextX96,
            next_sqrtp_pntr,
            liq,
            am_specified_remaining,
            pool_fee
          )

        am_specified_remaining =
          if exact_input do
            am_specified_remaining - (am_in + fee)
          else
            am_specified_remaining + am_out
          end

        fees = fees + fee
        ams_in = ams_in + am_in + fee
        ams_out = ams_out + am_out

        if am_specified_remaining != 0 && next_sqrtp_pntr != sqrtp_limit_x96 do
          {:cont, {am_specified_remaining, sqrtRatioNextX96, ams_in, ams_out, fees}}
        else
          {:halt, {am_specified_remaining, sqrtRatioNextX96, ams_in, ams_out, fees}}
        end
      end)

    {nextSqrtRatioX96, amount_in, amount_out}
  end

  def jit_swap_old(
        key,
        target_block,
        pool_fee,
        curr_sqrtp_x96,
        amount0,
        amount1,
        jit_tick_low,
        jit_tick_high,
        amount_specified,
        zero_for_one,
        sqrtp_limit_x96 \\ nil
      ) do
    # USE LATEST FROM SWAP MODULE
    tick_state =
      generate_jit_tick_state(
        get_target_ticks_at_block(key, target_block),
        curr_sqrtp_x96,
        amount0,
        amount1,
        jit_tick_low,
        jit_tick_high,
        zero_for_one
      )

    jit_liquidity =
      get_liquidity_for_amounts(
        curr_sqrtp_x96,
        tick_to_sqrt_ratio(jit_tick_low),
        tick_to_sqrt_ratio(jit_tick_high),
        amount0,
        amount1
      )

    curr_tick = sqrt_ratio_to_tick(curr_sqrtp_x96)

    current_tick_index =
      tick_state
      |> Enum.find_index(fn [lt, ht, _liq, _lf] ->
        lt <= curr_tick && curr_tick < ht
      end)

    {_, nextSqrtRatioX96, amount_in, amount_out, jit_fees} =
      tick_state
      |> Enum.slice(current_tick_index..-1)
      |> Enum.map(fn [lt, ht, liq, _lf] ->
        if zero_for_one,
          do: [lt, liq, _lf],
          else: [ht, liq, _lf]
      end)
      |> Enum.reduce_while(
        {amount_specified, curr_sqrtp_x96, 0, 0, 0},
        fn [tick, liq, liq_fraction],
           {am_specified_remaining, sqrtRatioNextX96, ams_in, ams_out, jit_fees} ->
          next_sqrtp_pntr = tick_to_sqrt_ratio(tick)

          next_sqrtp_pntr =
            cond do
              sqrtp_limit_x96 == nil -> next_sqrtp_pntr
              zero_for_one && next_sqrtp_pntr < sqrtp_limit_x96 -> sqrtp_limit_x96
              !zero_for_one && next_sqrtp_pntr > sqrtp_limit_x96 -> sqrtp_limit_x96
              true -> next_sqrtp_pntr
            end

          exact_input = amount_specified > 0

          {sqrtRatioNextX96, am_in, am_out, fee} =
            compute_swap_step(
              sqrtRatioNextX96,
              next_sqrtp_pntr,
              liq,
              am_specified_remaining,
              pool_fee
            )

          am_specified_remaining =
            if exact_input do
              am_specified_remaining - (am_in + fee)
            else
              am_specified_remaining + am_out
            end

          jit_fee =
            D.mult(fee, liq_fraction)
            |> D.round(0, :floor)
            |> D.to_integer()

          jit_fees = jit_fees + jit_fee
          ams_in = ams_in + am_in + fee
          ams_out = ams_out + am_out

          if am_specified_remaining != 0 && next_sqrtp_pntr != sqrtp_limit_x96 do
            {:cont, {am_specified_remaining, sqrtRatioNextX96, ams_in, ams_out, jit_fees}}
          else
            {:halt, {am_specified_remaining, sqrtRatioNextX96, ams_in, ams_out, jit_fees}}
          end
        end
      )

    # TODO: calc fees of each token off of zero_for_one
    {am0, am1} =
      get_amounts_for_liquidity(
        nextSqrtRatioX96,
        tick_to_sqrt_ratio(jit_tick_low),
        tick_to_sqrt_ratio(jit_tick_high),
        jit_liquidity
      )

    %{
      next_sqrtp: nextSqrtRatioX96,
      amount_in: amount_in,
      amount_out: amount_out,
      jit_fees: jit_fees,
      amount0_burned: am0,
      amount1_burned: am1
    }
  end

  def simulate_swap(
        key,
        target_block,
        pool_fee,
        init_sqrtp_x96,
        amount_specified,
        zero_for_one,
        sqrtp_limit_x96 \\ nil
      ) do
    tick_state = generate_tick_state_at_block(key, target_block, zero_for_one)

    swap(tick_state, pool_fee, init_sqrtp_x96, amount_specified, zero_for_one, sqrtp_limit_x96)
  end

  # def decode_swap(data) do
  #   [_address, amount_in, amount_out, path, _bool] =
  #     ABI.TypeDecoder.decode(data, [
  #       :address,
  #       {:uint, 256},
  #       {:uint, 256},
  #       :bytes,
  #       :bool
  #     ])
  # end

  def decode_path(path) do
    num_tokens = (String.length(path) / 40) |> round()

    Enum.reduce(1..num_tokens, {[], path}, fn x, {path_list, path_pntr} ->
      if x != num_tokens do
        {token, path_pntr} = String.split_at(path_pntr, 40)
        {fee, path_pntr} = String.split_at(path_pntr, 6)
        path_list = ["0x" <> String.downcase(token) | path_list]

        {[hex_to_int(fee) | path_list], path_pntr}
      else
        {token, path_pntr} = String.split_at(path_pntr, 40)
        {["0x" <> String.downcase(token) | path_list], path_pntr}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def mint(sqrtp_x96, tick_lower, tick_upper, amount0, amount1) do
    sqrtp_lower = tick_to_sqrt_ratio(tick_lower)
    sqrtp_upper = tick_to_sqrt_ratio(tick_upper)

    liquidity = get_liquidity_for_amounts(sqrtp_x96, sqrtp_lower, sqrtp_upper, amount0, amount1)

    {amount0, amount1} = get_amounts_for_liquidity(sqrtp_x96, sqrtp_lower, sqrtp_upper, liquidity)

    {liquidity, amount0, amount1}
  end

  # TickMath
  def low_tick_to_sqrt_prices(tick, tick_spacing) do
    sqrt_price_low = 1.0001 ** (tick / 2)
    sqrt_price_high = 1.0001 ** ((tick + tick_spacing) / 2)

    {sqrt_price_low, sqrt_price_high}
  end

  def price_to_tick(p) do
    Math.log(p, 1.0001)
    |> :math.floor()
    |> round()
  end

  def price_to_sqrtp_x96(price) do
    D.from_float(price)
    |> D.sqrt()
    |> D.mult(1 <<< 96)
    |> D.round(0, :floor)
    |> D.to_integer()
  end

  def tick_to_price(tick) do
    (tick_to_sqrt_ratio(tick) / (1 <<< 96)) ** 2
  end

  def sqrtp_x96_to_price(sqrtp_x96) do
    (sqrtp_x96 / (1 <<< 96)) ** 2
  end

  def tick_to_sqrt_price_x96(tick) do
    D.from_float(1.0001 ** (tick / 2))
    |> D.mult(1 <<< 96)
    |> D.to_integer()
  end

  def tick_to_sqrt_ratio(tick) do
    absTick = if tick < 0, do: -tick, else: tick

    ratio =
      if (absTick &&& 0x1) != 0,
        do: 0xFFFCB933BD6FAD37AA2D162D1A594001,
        else: 0x100000000000000000000000000000000

    ratio =
      @bitwise_ops
      |> Enum.reduce(ratio, fn [k, v], acc ->
        if (absTick &&& k) != 0,
          do: (acc * v) >>> 128,
          else: acc
      end)

    ratio =
      if tick > 0 do
        D.div(@uint256_max, ratio) |> D.round() |> D.to_integer()
      else
        ratio
      end

    zero_or_one =
      if rem(ratio, 1 <<< 32) == 0,
        do: 0,
        else: 1

    (ratio >>> 32) + zero_or_one
  end

  def sqrt_ratio_to_tick(sqrt_price_x96) do
    ratio = sqrt_price_x96 <<< 32

    {msb, r} =
      @sqrt_ratios
      |> Enum.reduce({0, ratio}, fn [shift, comp], {msb, r} ->
        to_shift = if r > comp, do: 1, else: 0

        if shift > 0 do
          f = bsl(to_shift, shift)
          msb = bor(msb, f)
          r = bsr(r, f)
          {msb, r}
        else
          msb = bor(to_shift, msb)
          {msb, r}
        end
      end)

    r =
      if msb >= 128,
        do: ratio >>> (msb - 127),
        else: ratio <<< (127 - msb)

    log_2 = (msb - 128) <<< 64

    {log_2, r} =
      63..50
      |> Enum.reduce({log_2, r}, fn shift, {log_2, r} ->
        r = D.mult(r, r) |> D.to_integer() |> bsr(127)
        f = bsr(r, 128)
        log_2 = bor(log_2, bsl(f, shift))

        case shift do
          50 -> {log_2, r}
          _ -> {log_2, bsr(r, f)}
        end
      end)

    log_sqrt10001 = log_2 * 255_738_958_999_603_826_347_141

    tick_low = (log_sqrt10001 - 3_402_992_956_809_132_418_596_140_100_660_247_210) >>> 128
    tick_high = (log_sqrt10001 + 291_339_464_771_989_622_907_027_621_153_398_088_495) >>> 128

    cond do
      tick_low == tick_high -> tick_low
      tick_to_sqrt_ratio(tick_high) <= sqrt_price_x96 -> tick_high
      true -> tick_low
    end
  end

  # SqrtPriceMath.sol
  def get_next_sqrt_price_from_amount0(amount, liquidity, sqrt_price_x96, add \\ true) do
    numerator1 = liquidity <<< 96

    # IO.inspect({amount, liquidity, sqrt_price_x96, add}, label: "get_next_sqrt_price_from_amount0")
    if add do
      product = amount * sqrt_price_x96

      if D.to_integer(D.div(product, amount)) == sqrt_price_x96 do
        denominator = numerator1 + product

        if denominator >= numerator1 do
          D.mult(numerator1, sqrt_price_x96)
          |> D.div(denominator)
          |> D.round(0, :ceiling)
          |> D.to_integer()
        end
      else
        IO.inspect("test me")

        denom =
          D.div(numerator1, sqrt_price_x96)
          |> D.round(0, :floor)
          |> D.to_integer()

        D.div(numerator1, denom + amount)
        |> D.round(0, :ceiling)
        |> D.to_integer()

        # |> IO.inspect()
      end
    else
      product = amount * sqrt_price_x96
      # if (numerator1 > product) do
      denominator = numerator1 - product

      D.mult(numerator1, sqrt_price_x96)
      |> D.div(denominator)
      |> D.round(0, :ceiling)
      |> D.to_integer()

      # end
    end
  end

  def get_next_sqrt_price_from_amount1(amount, liquidity, sqrt_price_x96, add \\ true) do
    if add do
      quotient =
        if amount <= @uint160_max do
          D.div(amount <<< 96, liquidity)
          |> D.round(0, :floor)
          |> D.to_integer()
        else
          D.mult(amount, @q96)
          |> D.div(liquidity)
          |> D.round(0, :floor)
          |> D.to_integer()
        end

      sqrt_price_x96 + quotient
    else
      quotient =
        if amount <= @uint160_max do
          D.div(amount <<< 96, liquidity)
          |> D.round(0, :ceiling)
          |> D.to_integer()
        else
          D.mult(amount, @q96)
          |> D.div(liquidity)
          |> D.round(0, :ceiling)
          |> D.to_integer()
        end

      sqrt_price_x96 - quotient
    end
  end

  def get_next_sqrt_price_from_input(amount_in, liquidity, sqrt_price_x96, zero_for_one) do
    if zero_for_one do
      get_next_sqrt_price_from_amount0(amount_in, liquidity, sqrt_price_x96, true)
    else
      get_next_sqrt_price_from_amount1(amount_in, liquidity, sqrt_price_x96, true)
    end
  end

  # Gets the next sqrt price given an output amount of token0 or token1
  def get_next_sqrt_price_from_output(
        amount_out,
        liquidity,
        sqrt_price_x96,
        zero_for_one
      ) do
    if zero_for_one do
      get_next_sqrt_price_from_amount1(amount_out, liquidity, sqrt_price_x96, false)
    else
      get_next_sqrt_price_from_amount0(amount_out, liquidity, sqrt_price_x96, false)
    end
  end

  # Gets the amount0 delta between two prices
  def get_amount0_delta(sqrt_price_x96_a, sqrt_price_x96_b, liquidity, round_up) do
    {sqrtp_x96_a, sqrtp_x96_b} =
      if sqrt_price_x96_a > sqrt_price_x96_b,
        do: {sqrt_price_x96_b, sqrt_price_x96_a},
        else: {sqrt_price_x96_a, sqrt_price_x96_b}

    numerator1 = liquidity <<< 96
    numerator2 = sqrtp_x96_b - sqrtp_x96_a

    result =
      if round_up do
        D.mult(numerator1, numerator2)
        |> D.div(sqrtp_x96_b)
        |> D.round(0, :ceiling)
        |> D.div(sqrtp_x96_a)
        |> D.round(0, :ceiling)
        |> D.to_integer()
      else
        D.mult(numerator1, numerator2)
        |> D.div(sqrtp_x96_b)
        |> D.div(sqrtp_x96_a)
        |> D.round(0, :floor)
        |> D.to_integer()
      end
  end

  # Gets the amount1 delta between two prices
  def get_amount1_delta(sqrt_price_x96_a, sqrt_price_x96_b, liquidity, round_up) do
    {sqrtp_x96_a, sqrtp_x96_b} =
      if sqrt_price_x96_a > sqrt_price_x96_b,
        do: {sqrt_price_x96_b, sqrt_price_x96_a},
        else: {sqrt_price_x96_a, sqrt_price_x96_b}

    result =
      if round_up do
        D.mult(liquidity, sqrtp_x96_b - sqrtp_x96_a)
        |> D.div(@q96)
        |> D.round(0, :ceiling)
        |> D.to_integer()
      else
        D.mult(liquidity, sqrtp_x96_b - sqrtp_x96_a)
        |> D.div(@q96)
        |> D.round(0, :floor)
        |> D.to_integer()
      end
  end

  # LiquidityAmounts.sol
  def sort_sqrt_ratios(sqrtRatioAX96, sqrtRatioBX96) do
    if sqrtRatioAX96 > sqrtRatioBX96,
      do: {sqrtRatioBX96, sqrtRatioAX96},
      else: {sqrtRatioAX96, sqrtRatioBX96}
  end

  def get_liquidity_for_amount0(sqrtRatioAX96, sqrtRatioBX96, amount0) do
    {sqrtRatioAX96, sqrtRatioBX96} = sort_sqrt_ratios(sqrtRatioAX96, sqrtRatioBX96)

    intermediate =
      D.mult(sqrtRatioAX96, sqrtRatioBX96)
      |> D.div(@q96)

    D.mult(amount0, intermediate)
    |> D.div(sqrtRatioBX96 - sqrtRatioAX96)
    |> D.round(0, :floor)
    |> D.to_integer()
  end

  def get_liquidity_for_amount1(sqrtRatioAX96, sqrtRatioBX96, amount1) do
    {sqrtRatioAX96, sqrtRatioBX96} = sort_sqrt_ratios(sqrtRatioAX96, sqrtRatioBX96)

    D.mult(amount1, @q96)
    |> D.div(sqrtRatioBX96 - sqrtRatioAX96)
    |> D.round(0, :floor)
    |> D.to_integer()
  end

  def get_liquidity_for_amounts(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1) do
    {sqrtRatioAX96, sqrtRatioBX96} = sort_sqrt_ratios(sqrtRatioAX96, sqrtRatioBX96)

    cond do
      sqrtRatioX96 <= sqrtRatioAX96 ->
        get_liquidity_for_amount0(sqrtRatioAX96, sqrtRatioBX96, amount0)

      sqrtRatioX96 < sqrtRatioBX96 ->
        liquidity0 = get_liquidity_for_amount0(sqrtRatioX96, sqrtRatioBX96, amount0)
        liquidity1 = get_liquidity_for_amount1(sqrtRatioAX96, sqrtRatioX96, amount1)

        if liquidity0 < liquidity1,
          do: liquidity0,
          else: liquidity1

      true ->
        get_liquidity_for_amount1(sqrtRatioAX96, sqrtRatioBX96, amount1)
    end
  end

  def get_amount0_for_liquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity) do
    {sqrtRatioAX96, sqrtRatioBX96} = sort_sqrt_ratios(sqrtRatioAX96, sqrtRatioBX96)

    liquidity <<< 96
    |> D.mult(sqrtRatioBX96 - sqrtRatioAX96)
    |> D.div(sqrtRatioBX96)
    |> D.div(sqrtRatioAX96)
    |> D.round(0, :floor)
    |> D.to_integer()
  end

  def get_amount1_for_liquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity) do
    {sqrtRatioAX96, sqrtRatioBX96} = sort_sqrt_ratios(sqrtRatioAX96, sqrtRatioBX96)

    liquidity
    |> D.mult(sqrtRatioBX96 - sqrtRatioAX96)
    |> D.div(@q96)
    |> D.round(0, :floor)
    |> D.to_integer()
  end

  def get_amounts_for_liquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidity) do
    {sqrtRatioAX96, sqrtRatioBX96} = sort_sqrt_ratios(sqrtRatioAX96, sqrtRatioBX96)

    {amount0, amount1} =
      cond do
        sqrtRatioX96 <= sqrtRatioAX96 ->
          {get_amount0_for_liquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity), 0}

        sqrtRatioX96 < sqrtRatioBX96 ->
          {
            get_amount0_for_liquidity(sqrtRatioX96, sqrtRatioBX96, liquidity),
            get_amount1_for_liquidity(sqrtRatioAX96, sqrtRatioX96, liquidity)
          }

        true ->
          {0, get_amount1_for_liquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity)}
      end
  end
end
