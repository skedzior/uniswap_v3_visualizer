defmodule V3Visualizer.ForgeFactory do
  @rpc_url "https://eth-mainnet.alchemyapi.io/v2/#{INSERT_YOUR_KEY}"

  def quote_exact_input_single(token_in, token_out, fee, amount_in, sqrtp_x96, rpc_url \\ @rpc_url) do
    result =
      System.shell(
        "cast call 0xb27308f9f90d607463bb33ea1bebb41c27ce5ab6 quoteExactInputSingle(address,address,uint24,uint256,uint160)(uint256) #{token_in} #{token_out} #{fee} #{amount_in} #{sqrtp_x96} --rpc-url #{rpc_url}"
      )
      |> elem(0)
      |> String.split("\n")

    if result == [""] do
      {:error, "error"}
    else
      [amount_out, _] = result

      String.to_integer(amount_out)
    end
  end

  def quote_exact_input(path, amount_in, rpc_url \\ @rpc_url) do
    result =
      System.shell(
        "cast call 0xb27308f9f90d607463bb33ea1bebb41c27ce5ab6 quoteExactInput(bytes,uint256)(uint256) #{path} #{amount_in} --rpc-url #{rpc_url}"
      )
      |> elem(0)
      |> String.split("\n")

    if result == [""] do
      {:error, "error"}
    else
      [amount_out, _] = result

      String.to_integer(amount_out)
    end
  end

  def quote_exact_output_single(token_in, token_out, fee, amount_out, sqrtp_x96, rpc_url \\ @rpc_url) do
    result =
      System.shell(
        "cast call 0xb27308f9f90d607463bb33ea1bebb41c27ce5ab6 quoteExactOutputSingle(address,address,uint24,uint256,uint160)(uint256) #{token_in} #{token_out} #{fee} #{amount_out} #{sqrtp_x96} --rpc-url #{rpc_url}"
      )
      |> elem(0)
      |> String.split("\n")

    if result == [""] do
      {:error, "error"}
    else
      [amount_out, _] = result

      String.to_integer(amount_out)
    end
  end

  def quote_exact_output(path, amount_out, rpc_url \\ @rpc_url) do
    result =
      System.shell(
        "cast call 0xb27308f9f90d607463bb33ea1bebb41c27ce5ab6 quoteExactOutput(bytes,uint256)(uint256) #{path} #{amount_out} --rpc-url #{rpc_url}"
      )
      |> elem(0)
      |> String.split("\n")

    if result == [""] do
      {:error, "error"}
    else
      [amount_out, _] = result

      String.to_integer(amount_out)
    end
  end

  def get_reserves_at_block(address, rpc_url \\ @rpc_url) do
    result =
      System.shell(
        "cast call #{address} getReserves()(uint112,uint112) --rpc-url #{rpc_url}"
      )
      |> elem(0)
      |> String.split("\n")

    if result == [""] do
      {:error, "Make sure address is a V2Pair"}
    else
      [reserve0, reserve1, _] = result

      [
        String.to_integer(reserve0),
        String.to_integer(reserve1)
      ]
    end
  end

  def get_slot0_at_block(address, rpc_url \\ @rpc_url) do
    result =
      System.shell(
        "cast call #{address} slot0()(uint160,int24) --rpc-url #{rpc_url}"
      )
      |> elem(0)
      |> String.split("\n")

    if result == [""] do
      {:error, "Make sure address is a V3Pool"}
    else
      [sqrt_price_x96, tick, _] = result

      [
        String.to_integer(sqrt_price_x96),
        String.to_integer(tick)
      ]
    end
  end

  def get_liquidity_at_block(address, rpc_url \\ @rpc_url) do
    result =
      System.shell(
        "cast call #{address} liquidity()(uint128) --rpc-url #{rpc_url}"
      )
      |> elem(0)
      |> String.split("\n")
      |> Enum.at(0)

    if result == "" do
      {:error, "Make sure address is a V3Pool"}
    else
      String.to_integer(result)
    end
  end
end
