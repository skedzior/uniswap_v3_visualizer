defmodule V3Visualizer.Pool.Gql do
  @endpoint "https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3"
  @headers [{"Content-type", "application/json"}]

  def get_pool_data(address) do
    body =
      Poison.encode!(%{
        operationName: "pool",
        variables: %{
          poolAddress: String.downcase(address)
        },
        query: "query pool($poolAddress: String!) {
            pool(id: $poolAddress) {
              tick
              feeTier
              sqrtPrice
              liquidity
            }
          }"
      })

    resp =
      HTTPoison.post(@endpoint, body, @headers)
      |> parse_response

    resp["pool"]
  end

  def get_all_ticks(address) do
    body =
      Poison.encode!(%{
        operationName: "ticks",
        variables: %{
          poolAddress: String.downcase(address)
        },
        query: "query ticks($poolAddress: String!) {
            ticks(
              where: {
                poolAddress: $poolAddress,
                liquidityGross_not: 0
              },
              orderBy: tickIdx,
              orderDirection: desc,
              first: 1000,
              skip: 0
            ) {
              tickIdx
              liquidityNet
              liquidityGross
              price0
              price1
            }
          }"
      })

    resp =
      HTTPoison.post(@endpoint, body, @headers)
      |> parse_response

    resp["ticks"]
  end

  def get_pool_creation_block(address) do
    body =
      Poison.encode!(%{
        operationName: "pool",
        variables: %{
          poolAddress: String.downcase(address)
        },
        query: "query pool_creation_block($poolAddress: String!){
            pool(id: $poolAddress) {
              createdAtBlockNumber
            }
          }"
      })

    data =
      HTTPoison.post(@endpoint, body, @headers)
      |> parse_response

    data["pool"]["createdAtBlockNumber"]
  end

  def get_events_from_hash(:v3, pool, tx_hash) do
    body =
      Poison.encode!(%{
        operationName: "get_events_from_hash",
        query:
          "query get_events_from_hash($tx_hash: String!, $pool: String!) {
            transaction(id: $tx_hash) {
              id
              blockNumber
              timestamp
              gasUsed
              gasPrice
              mints(where: {pool: $pool}) {
                id
                transaction {
                  blockNumber
                }
                amount
                amount0
                amount1
                amountUSD
                timestamp
                tickLower
                tickUpper
                logIndex
              }
              burns(where: {pool: $pool}) {
                id
                transaction {
                  blockNumber
                }
                amount
                amount0
                amount1
                amountUSD
                timestamp
                tickLower
                tickUpper
                logIndex
              }
              swaps(where: {pool: $pool}) {
                id
                transaction {
                  blockNumber
                }
                tick
                sender
                recipient
                sqrtPriceX96
                origin
                amount0
                amount1
                amountUSD
                timestamp
                logIndex
              }
            }
          }",
        variables: %{
          tx_hash: tx_hash,
          pool: String.downcase(pool)
        }
      })

    data =
      HTTPoison.post(@endpoint, body, @headers)
      |> parse_response

    data["transaction"]
  end

  def surrounding_ticks(address) do
    body =
      Poison.encode!(%{
        operationName: "surroundingTicks",
        query:
          "query surroundingTicks($poolAddress: String!, $tickIdxLowerBound: BigInt!, $tickIdxUpperBound: BigInt!, $skip: Int!) {
            ticks(
              subgraphError: allow
              first: 1000
              skip: $skip
              where: {poolAddress: $poolAddress, tickIdx_lte: $tickIdxUpperBound, tickIdx_gte: $tickIdxLowerBound}
            ) {
              tickIdx
              liquidityGross
              liquidityNet
              price0
              price1
              __typename
            }
          }",
        variables: %{
          # CryptoLiveview.Pools.Pool.surrounding_ticks("0x80c7770b4399ae22149db17e97f9fc8a10ca5100")
          poolAddress: String.downcase(address),
          skip: 0,
          tickIdxLowerBound: -63420,
          tickIdxUpperBound: -37020
        }
      })

    data =
      HTTPoison.post(@endpoint, body, @headers)
      |> parse_response

    data["ticks"]
  end

  def parse_response({:ok, response}) do
    data =
      response.body
      |> Poison.decode!()

    data["data"]
  end
end
