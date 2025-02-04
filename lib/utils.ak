use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Address, Script}
use cardano/assets.{Value, quantity_of}
use cardano/transaction.{Input,
  Output, Redeemer, ScriptPurpose, Spend, Withdraw}
use constants
use types/general.{Asset, CardanoToken}
use types/redeemer.{
  Aggregated, Dedicated, OraclePriceFeed, OracleRedeemer, Pooled,
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
    }

  if and {
    commonFeedData.valid_to - commonFeedData.valid_from <= constants.max_oracle_validity_range,
    commonFeedData.valid_to >= transaction_valid_to,
    is_feed_token_correct(expectedPaymentToken, commonFeedData.token),
  } {
    Some(loan_tokens_price.data)
  } else {
    trace @"oracle is expired, has wrong token or wrong interval"
    None
  }
}
