use cardano/address.{Address}
use types/general.{Asset}

pub type CommonFeedData {
  valid_from: Int,
  valid_to: Int,
  token: Asset,
}

pub type OraclePriceFeed {
  //Tokens that have a lot of liquidity are in CEX. The price is in lovelace
  Aggregated {
    common: CommonFeedData,
    token_price_in_lovelaces: Int,
    denominator: Int,
  }
  //Tokens that have lower liquidity, AMM pool data is used to calculate the price
  Pooled { common: CommonFeedData, token_a_amount: Int, token_b_amount: Int }
  //Complex vaults can have a dedicated oracle that calculates the value of all collateral assets in a custom currency
  Dedicated {
    common: CommonFeedData,
    price_in_lovelaces: Int,
    denominator: Int,
  }
  PriceDataCharlie {
    provider_ref_input_index: Int,
    common: CommonFeedData,
    price_in_lovelaces: Int,
    price_denominator: Int,
  }
  PriceDataOrcfax {
    pointer_ref_input_index: Int,
    provider_ref_input_index: Int,
    common: CommonFeedData,
    price_in_lovelaces: Int,
    price_denominator: Int,
  }
}

pub type Signature {
  signature: ByteArray,
  key_position: Int,
}

pub type OracleRedeemer {
  data: OraclePriceFeed,
  signatures: List<Signature>,
}

pub type RedeemerStaker {
  owner: Address,
  signer_bot: Address,
  reference_index: Int,
  output_staking: Int,
  staking_inputs: Int,
}

pub type RedeemerTank {
  Consume {
    payingTokenIndex: Int,
    inputTankIndex: Int,
    receivers: Int,
    reference_params_index: Int,
    whitelist_index: Int,
  }
  ConsumeAll {
    payingTokenIndex: Int,
    inputTankIndex: Int,
    receivers: Int,
    reference_params_index: Int,
    whitelist_index: Int,
  }
  Withdraw
  ScheduledTransaction {
    inputTankIndex: Int,
    batcher: Address,
    reference_staking_index: Int,
    reference_params_index: Int,
    whitelist_index: Int,
  }
  ConsumeOracle {
    payingTokenIndex: Int,
    inputTankIndex: Int,
    receivers: Int,
    oracleIndex: Int,
    reference_params_index: Int,
    whitelist_index: Int,
  }
  ConsumeAllOracle {
    payingTokenIndex: Int,
    inputTankIndex: Int,
    receivers: Int,
    oracleIndex: Int,
    reference_params_index: Int,
    whitelist_index: Int,
  }
}
