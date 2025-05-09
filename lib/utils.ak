use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Address, Script}
use cardano/assets.{PolicyId, Value, quantity_of}
use cardano/transaction.{Input,
  Output, Redeemer, ScriptPurpose, Spend, Withdraw}
use constants
use types/general.{
  Asset, CardanoToken, CharlieTokenSpecs, GenericData, OrcfaxTokenSpecs,
  PriceData,
}
use types/redeemer.{
  Aggregated, Dedicated, OraclePriceFeed, OracleRedeemer, Pooled,
  PriceDataCharlie, PriceDataOrcfax,
}

pub fn is_output_to_sc(output: Output, scHash: ByteArray) -> Bool {
  when output.address.payment_credential is {
    Script(hash) -> hash == scHash
    _ -> False
  }
}

pub fn get_outputs_to_sc(
  outputs: List<Output>,
  scHash: ByteArray,
) -> List<Output> {
  list.filter(outputs, fn(output) { is_output_to_sc(output, scHash) })
}

pub fn get_inputs_from_sc(inputs: List<Input>, scHash: ByteArray) -> List<Input> {
  list.filter(inputs, fn(input) { is_output_to_sc(input.output, scHash) })
}

pub fn get_own_hash(purpose: ScriptPurpose, txInputs: List<Input>) {
  expect Spend(output_reference) = purpose

  let inputList =
    list.filter(txInputs, fn(x) { x.output_reference == output_reference })

  expect Some(input) = list.head(inputList)
  when input.output.address.payment_credential is {
    Script(hash) -> hash
    _ -> fail
  }
}

pub fn validate_oracle_ref_input(
  oracleInputValue: Value,
  chosenCollateral: CardanoToken,
) {
  expect Some(oracleToken) = chosenCollateral.oracle
  quantity_of(oracleInputValue, oracleToken.policyId, oracleToken.assetName) > 0
}

pub fn is_feed_token_correct(
  expectedPaymentToken: CardanoToken,
  feedToken: Asset,
) {
  and {
    feedToken.policyId == expectedPaymentToken.policyId,
    feedToken.assetName == expectedPaymentToken.assetName,
  }
}

pub fn retrieve_oracle_data(
  oracleInput: Input,
  redeemers: Pairs<ScriptPurpose, Redeemer>,
  transaction_valid_from: Int,
  transaction_valid_to: Int,
  expectedPaymentToken: CardanoToken,
) -> Option<OraclePriceFeed> {
  expect Some(loan_oracle_redeemer) =
    pairs.get_first(
      redeemers,
      Withdraw(oracleInput.output.address.payment_credential),
    )
  expect loan_tokens_price: OracleRedeemer = loan_oracle_redeemer

  let commonFeedData =
    when loan_tokens_price.data is {
      Pooled { common, .. } -> common
      Aggregated { common, .. } -> common
      Dedicated { common, .. } -> common
      PriceDataCharlie { common, .. } -> common
      PriceDataOrcfax { common, .. } -> common
    }

  if and {
    commonFeedData.valid_to - commonFeedData.valid_from <= constants.max_oracle_validity_range,
    commonFeedData.valid_to >= transaction_valid_to,
    commonFeedData.valid_from <= transaction_valid_from,
    is_feed_token_correct(expectedPaymentToken, commonFeedData.token),
  } {
    Some(loan_tokens_price.data)
  } else {
    trace @"oracle is expired, has wrong token or wrong interval"
    None
  }
}

//-------------------------- CHARLIE 3 UTILS

pub fn get_oracle_info(price_data: PriceData) -> (Int, Int, Int) {
  when price_data is {
    GenericData { price_map } ->
      when price_map is {
        [Pair(0, price), Pair(1, timestamp), Pair(2, expiry)] ->
          (price, timestamp, expiry)
        _ -> fail @"Invalid price, timestamp or expiry"
      }
    _ -> fail @"Invalid PriceData variant"
  }
}

pub fn get_oracle_config(
  oracle_specs: CharlieTokenSpecs,
  feedToken: Asset,
) -> (PolicyId, Int) {
  expect Some(token_pairs) = pairs.get_first(oracle_specs, feedToken.policyId)
  expect Some(result) = pairs.get_first(token_pairs, feedToken.assetName)
  result
}

pub fn get_oracle_orcfax_config(
  oracle_specs: OrcfaxTokenSpecs,
  feedToken: Asset,
) -> (PolicyId, Int, ByteArray) {
  expect Some(token_pairs) = pairs.get_first(oracle_specs, feedToken.policyId)
  expect Some(result) = pairs.get_first(token_pairs, feedToken.assetName)
  result
}

pub fn count_inputs(inputs: List<Input>, policy: ByteArray) {
  inputs
    |> list.count(
        fn(input) { input.output.address.payment_credential == Script(policy) },
      )
}

pub fn force_spend_inputs(
  purposes: Pairs<ScriptPurpose, Redeemer>,
  spend_inputs: Int,
) {
  //we remove the first n - 1 purposes, because that's what we expect to have in the inputs
  let filtered_purposes = tail_recursive(purposes, spend_inputs - 1)

  expect Some(first_purpose) = list.at(filtered_purposes, 0)
  let maybe_purpose = list.at(filtered_purposes, 1)
  let head_check =
    when first_purpose.1st is {
      Spend(_) -> True
      _ -> False
    }
  let tail_check =
    when maybe_purpose is {
      Some(next_purpose) ->
        when next_purpose.1st is {
          Spend(_) -> False
          _ -> True
        }
      None -> True
    }

  and {
    head_check,
    tail_check,
  }
}

fn tail_recursive(purposes: Pairs<ScriptPurpose, Redeemer>, n: Int) {
  if n > 1 {
    expect Some(purposes_tailed) = list.tail(purposes)
    tail_recursive(purposes_tailed, n - 1)
  } else {
    purposes
  }
}
