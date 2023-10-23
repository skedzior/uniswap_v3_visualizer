defmodule V3Visualizer.Chain do
  alias Ethereumex.HttpClient

  @stream_endpoint "wss://mainnet.infura.io/ws/v3/#{INSERT_YOUR_KEY}"

  def get_block(number) do
    {status, result} = HttpClient.eth_get_block_by_number(to_hex(number), true)
    IO.inspect(result)
  end

  def get_current_block_number() do
    {status, result} = HttpClient.eth_get_block_by_number("latest", true)
    block_number = String.to_integer(String.slice(result["number"], 2..-1), 16)
  end

  def to_hex(decimal), do: "0x" <> Integer.to_string(decimal, 16)
end
