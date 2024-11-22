use types/general.{Asset}

//Tokens that have a lot of liquidity are in CEX. The price is in lovelace
pub type AggregatedFeed {
  token: Asset,
  token_price_in_lovelaces: Int,
  denominator: Int,
  valid_to: Int,
}

//Tokens that have lower liquidity, AMM pool data is used to calculate the price
pub type PooledFeed {
  token: Asset,
  token_a_amount: Int,
  token_b_amount: Int,
  valid_to: Int,
}

//Complex vaults can have a dedicated oracle that calculates the value of all collateral assets in a custom currency
pub type DedicatedFeed {
  token: Asset,
  token_price_currency: Asset,
  token_price: Int,
  denominator: Int,
  valid_to: Int,
}

pub type OraclePriceFeed {
  Aggregated(AggregatedFeed)
  Pooled(PooledFeed)
  Dedicated(DedicatedFeed)
}

pub type Signature {
  signature: ByteArray,
  key_position: Int,
}

pub type OracleRedeemer {
  data: OraclePriceFeed,
  signatures: List<Signature>,
}
