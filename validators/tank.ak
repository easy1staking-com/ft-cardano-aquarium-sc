use aiken/collection/list
use aiken/interval.{Finite}
use aiken/math/rational.{from_int}
use aiken/option.{is_none}
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{Value, quantity_of, reduce}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use types/datum.{DatumParameters, DatumTank}
use types/general.{CardanoToken}
use types/redeemer.{
  Aggregated, Consume, ConsumeAll, ConsumeAllOracle, ConsumeOracle, Dedicated,
  OraclePriceFeed, Pooled, PriceDataCharlie, PriceDataOrcfax, RedeemerTank,
  ScheduledTransaction, Withdraw,
}
use utils.{retrieve_oracle_data, validate_oracle_ref_input}

validator tank(stakingContract: ByteArray, params_contract_hash: ByteArray) {
  spend(
    datum: Option<DatumTank>,
    redeemer: RedeemerTank,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(input) =
      self.inputs
        |> transaction.find_input(own_ref)
    expect Script(ownScriptHash) = input.output.address.payment_credential
    let tank_inputs = get_inputs_from_sc(self.inputs, ownScriptHash)

    when datum is {
      None ->
        when input.output.address.stake_credential is {
          None -> False
          Some(stake_cred) ->
            when stake_cred is {
              Inline(a) -> {
                expect VerificationKey(hash) = a
                list.has(self.extra_signatories, hash)
              }
              _ -> False
            }
        }
      Some(datum) ->
        when redeemer is {
          Consume(
            payingTokenIndex,
            inputTankIndex,
            _receivers,
            reference_params_index,
            whitelist_index,
          ) -> {
            expect Some(inputTank) = list.at(tank_inputs, inputTankIndex)
            let inputTankAsOutput = inputTank.output

            expect Some(outputTank) = list.at(self.outputs, inputTankIndex)
            expect Some(outputPayment) =
              list.at(self.outputs, inputTankIndex + 1)

            expect Some(payingToken) =
              list.at(datum.allowedTokens, payingTokenIndex)

            let outputPaymentAmount =
              quantity_of(
                outputPayment.value,
                payingToken.policyId,
                payingToken.assetName,
              )

            expect Some(referenceInputParams) =
              list.at(self.reference_inputs, reference_params_index)

            expect InlineDatum(datum_params) = referenceInputParams.output.datum
            expect datum_parsed: DatumParameters = datum_params
            let max_min_ada = datum_parsed.min_ada
            let inputTankAmount = quantity_of(inputTankAsOutput.value, "", "")
            let leftoverTankAmount = quantity_of(outputTank.value, "", "")
            let min_ada = quantity_of(outputPayment.value, "", "")

            and {
              list.length(tank_inputs) == 1,
              own_ref == inputTank.output_reference,
              verify_paying_with_allowed_token(datum.allowedTokens, payingToken),
              validate_tank_output(inputTank, outputTank),
              validate_payment_output(
                outputPayment,
                outputPaymentAmount,
                payingToken,
                datum.tankOwner,
                inputTankAmount - leftoverTankAmount - min_ada,
              ),
              isWhitelisted(self, datum.whitelistedAddresses, whitelist_index),
              is_none(payingToken.oracle),
              min_ada <= max_min_ada,
              quantity_of(
                referenceInputParams.output.value,
                params_contract_hash,
                "parameters",
              ) == 1,
            }
          }

          ConsumeAll(
            payingTokenIndex,
            inputTankIndex,
            _receivers,
            reference_params_index,
            whitelist_index,
          ) -> {
            expect Some(inputTank) = list.at(tank_inputs, inputTankIndex)
            let inputTankAsOutput = inputTank.output

            expect Some(referenceInputParams) =
              list.at(self.reference_inputs, reference_params_index)

            expect InlineDatum(datum_params) = referenceInputParams.output.datum
            expect datum_parsed: DatumParameters = datum_params
            let max_min_ada = datum_parsed.min_ada

            expect Some(outputPayment) = list.at(self.outputs, inputTankIndex)
            expect Some(payingToken) =
              list.at(datum.allowedTokens, payingTokenIndex)

            let outputPaymentAmount =
              quantity_of(
                outputPayment.value,
                payingToken.policyId,
                payingToken.assetName,
              )

            let inputTankAmount = quantity_of(inputTankAsOutput.value, "", "")
            let min_ada = quantity_of(outputPayment.value, "", "")

            and {
              own_ref == inputTank.output_reference,
              // verify that the paying token is greater than the fee
              list.length(tank_inputs) == 1,
              verify_paying_with_allowed_token(datum.allowedTokens, payingToken),
              validate_payment_output(
                outputPayment,
                outputPaymentAmount,
                payingToken,
                datum.tankOwner,
                inputTankAmount - min_ada,
              ),
              isWhitelisted(self, datum.whitelistedAddresses, whitelist_index),
              is_none(payingToken.oracle),
              min_ada <= max_min_ada,
              quantity_of(
                referenceInputParams.output.value,
                params_contract_hash,
                "parameters",
              ) == 1,
            }
          }

          Withdraw -> must_be_signed_by_user_contract(self, datum.tankOwner)
          //Schedule mette come primo output il pagamento, come secondo eventualmente quello di ritorno alla tank
          ScheduledTransaction(
            inputTankIndex,
            batcher,
            reference_staking_index,
            reference_params_index,
            whitelist_index,
          ) -> {
            expect Some(outputScheduled) = list.at(self.outputs, inputTankIndex)
            expect Some(inputTank) =
              list.at(
                get_inputs_from_sc(self.inputs, ownScriptHash),
                inputTankIndex,
              )

            expect Some(referenceInput) =
              list.at(self.reference_inputs, reference_staking_index)
            expect Some(referenceInputParams) =
              list.at(self.reference_inputs, reference_params_index)

            expect InlineDatum(datum_params) = referenceInputParams.output.datum
            expect datum_parsed: DatumParameters = datum_params

            let address_treasury = datum_parsed.address_rewards

            expect Some(outputRewards) =
              list.at(self.outputs, inputTankIndex + 1)
            let outputRewardAmount =
              quantity_of(
                outputRewards.value,
                datum.reward.policyId,
                datum.reward.assetName,
              )
            let outputPaymentAmount =
              quantity_of(
                outputScheduled.value,
                datum.scheduledAmount.policyId,
                datum.scheduledAmount.assetName,
              )

            expect Some(Inline(VerificationKey(hash))) =
              batcher.stake_credential
            and {
              own_ref == inputTank.output_reference,
              validate_scheduled_output(
                outputScheduled,
                outputPaymentAmount,
                datum.scheduledAmount,
                datum.destionationaAddress,
              ),
              validate_scheduled_output(
                outputRewards,
                outputRewardAmount,
                datum.reward,
                address_treasury,
              ),
              isWhitelisted(self, datum.whitelistedAddresses, whitelist_index),
              validate_time(self, datum.executionTime),
              list.has(self.extra_signatories, hash),
              quantity_of(referenceInput.output.value, stakingContract, hash) == 1,
              quantity_of(
                referenceInputParams.output.value,
                params_contract_hash,
                "parameters",
              ) == 1,
            }
          }
          ConsumeAllOracle(
            payingTokenIndex,
            inputTankIndex,
            _receivers,
            oracleIndex,
            reference_params_index,
            whitelist_index,
          ) -> {
            expect Some(oracleRefInput) =
              list.at(self.reference_inputs, oracleIndex)

            expect Some(payingToken) =
              list.at(datum.allowedTokens, payingTokenIndex)

            expect
              validate_oracle_ref_input(
                oracleRefInput.output.value,
                payingToken,
              ) == True

            expect Some(inputTank) = list.at(tank_inputs, inputTankIndex)
            let inputTankAsOutput = inputTank.output

            expect Some(outputPayment) =
              list.at(self.outputs, inputTankIndex + 1)

            expect Some(referenceInputParams) =
              list.at(self.reference_inputs, reference_params_index)

            expect InlineDatum(datum_params) = referenceInputParams.output.datum
            expect datum_parsed: DatumParameters = datum_params
            let max_min_ada = datum_parsed.min_ada

            let outputPaymentAmount =
              quantity_of(
                outputPayment.value,
                payingToken.policyId,
                payingToken.assetName,
              )

            let inputTankAmount = quantity_of(inputTankAsOutput.value, "", "")
            let min_ada = quantity_of(outputPayment.value, "", "")
            expect Finite(start) = self.validity_range.lower_bound.bound_type
            expect Finite(end) = self.validity_range.upper_bound.bound_type
            expect Some(oraclePriceFeed) =
              retrieve_oracle_data(
                oracleRefInput,
                self.redeemers,
                start,
                end,
                payingToken,
              )

            and {
              list.length(tank_inputs) == 1,
              own_ref == inputTank.output_reference,
              verify_paying_with_allowed_token(datum.allowedTokens, payingToken),
              validate_payment_output_oracle(
                outputPayment,
                outputPaymentAmount,
                payingToken,
                datum.tankOwner,
                oraclePriceFeed,
                inputTankAmount - min_ada,
              ),
              isWhitelisted(self, datum.whitelistedAddresses, whitelist_index),
              min_ada <= max_min_ada,
              quantity_of(
                referenceInputParams.output.value,
                params_contract_hash,
                "parameters",
              ) == 1,
            }
          }

          ConsumeOracle(
            payingTokenIndex,
            inputTankIndex,
            _receivers,
            oracleIndex,
            reference_params_index,
            whitelist_index,
          ) -> {
            expect Some(oracleRefInput) =
              list.at(self.reference_inputs, oracleIndex)

            expect Some(payingToken) =
              list.at(datum.allowedTokens, payingTokenIndex)

            expect
              validate_oracle_ref_input(
                oracleRefInput.output.value,
                payingToken,
              ) == True

            expect Some(inputTank) = list.at(tank_inputs, inputTankIndex)
            let inputTankAsOutput = inputTank.output

            expect Some(outputTank) = list.at(self.outputs, inputTankIndex)
            expect Some(outputPayment) =
              list.at(self.outputs, inputTankIndex + 1)

            let outputPaymentAmount =
              quantity_of(
                outputPayment.value,
                payingToken.policyId,
                payingToken.assetName,
              )

            expect Some(referenceInputParams) =
              list.at(self.reference_inputs, reference_params_index)

            expect InlineDatum(datum_params) = referenceInputParams.output.datum
            expect datum_parsed: DatumParameters = datum_params
            let max_min_ada = datum_parsed.min_ada

            let inputTankAmount = quantity_of(inputTankAsOutput.value, "", "")
            let leftoverTankAmount = quantity_of(outputTank.value, "", "")
            let min_ada = quantity_of(outputPayment.value, "", "")

            expect Finite(start) = self.validity_range.lower_bound.bound_type
            expect Finite(end) = self.validity_range.upper_bound.bound_type
            expect Some(oraclePriceFeed) =
              retrieve_oracle_data(
                oracleRefInput,
                self.redeemers,
                start,
                end,
                payingToken,
              )

            and {
              list.length(tank_inputs) == 1,
              own_ref == inputTank.output_reference,
              verify_paying_with_allowed_token(datum.allowedTokens, payingToken),
              validate_tank_output(inputTank, outputTank),
              validate_payment_output_oracle(
                outputPayment,
                outputPaymentAmount,
                payingToken,
                datum.tankOwner,
                oraclePriceFeed,
                inputTankAmount - leftoverTankAmount - min_ada,
              ),
              isWhitelisted(self, datum.whitelistedAddresses, whitelist_index),
              min_ada <= max_min_ada,
              quantity_of(
                referenceInputParams.output.value,
                params_contract_hash,
                "parameters",
              ) == 1,
            }
          }
        }
    }
  }

  else(_) {
    fail
  }
}

fn validate_tank_output(inputTank: Input, outputTank: Output) {
  and {
    check_dos_protection(outputTank.value),
    // verify that the input tank datum is equal to the output tank datum
    inputTank.output.datum == outputTank.datum,
    outputTank.address == inputTank.output.address,
  }
}

fn validate_payment_output(
  outputPayment: Output,
  outputPaymentAmount: Int,
  payingToken: CardanoToken,
  tankOwner: Address,
  ada_used: Int,
) {
  and {
    ada_used * payingToken.amount / payingToken.divider <= outputPaymentAmount,
    outputPayment.address == tankOwner,
    check_dos_protection(outputPayment.value),
  }
}

fn validate_payment_output_oracle(
  outputPayment: Output,
  outputPaymentAmount: Int,
  payingToken: CardanoToken,
  tankOwner: Address,
  oraclePriceFeed: OraclePriceFeed,
  used_ada: Int,
) {
  expect Some(tokenPrice) =
    when oraclePriceFeed is {
      Aggregated(_, token_price_in_lovelaces, denominator) ->
        rational.new(token_price_in_lovelaces, denominator)
      Pooled(_, token_a_amount, token_b_amount) ->
        rational.new(token_a_amount, token_b_amount)
      Dedicated(_, token_price, denominator) ->
        rational.new(token_price, denominator)
      PriceDataCharlie(_, _, token_price, denominator) ->
        rational.new(token_price, denominator)
      PriceDataOrcfax(_, _, _, token_price, denominator) ->
        rational.new(token_price, denominator)
    }

  expect Some(minTokenPayment) = rational.div(from_int(used_ada), tokenPrice)
  and {
    rational.ceil(minTokenPayment) * payingToken.amount / payingToken.divider <= outputPaymentAmount,
    outputPayment.address == tankOwner,
    check_dos_protection(outputPayment.value),
  }
}

fn verify_paying_with_allowed_token(
  allowedTokens: List<CardanoToken>,
  payingToken: CardanoToken,
) {
  list.has(allowedTokens, payingToken)
}

fn check_dos_protection(value: Value) {
  reduce(value, 0, fn(_, _, _, count) { count + 1 }) <= 5
}

fn must_be_signed_by_user_contract(transaction: Transaction, address: Address) {
  let input_addresses =
    list.foldl(transaction.inputs, [], fn(x, xs) { [x.output.address, ..xs] })
  list.has(input_addresses, address)
}

fn isWhitelisted(
  transaction: Transaction,
  whitelistedAddresses: List<Address>,
  index: Int,
) {
  if list.length(whitelistedAddresses) > 0 {
    expect Some(whitelisted) = list.at(whitelistedAddresses, index)
    must_be_signed_by_user_contract(transaction, whitelisted)
  } else {
    True
  }
}

//Here is all scheduled new functions

fn validate_scheduled_output(
  outputPayment: Output,
  outputPaymentAmount: Int,
  scheduledAmount: CardanoToken,
  receiver: Address,
) {
  and {
    scheduledAmount.amount == outputPaymentAmount,
    outputPayment.address == receiver,
    check_dos_protection(outputPayment.value),
  }
}

fn validate_time(tx: Transaction, timeScheduled: Int) {
  when tx.validity_range.lower_bound.bound_type is {
    Finite(begin) -> begin > timeScheduled
    _ -> False
  }
}

fn is_output_to_sc(output: Output, scHash: ByteArray) -> Bool {
  when output.address.payment_credential is {
    Script(hash) -> hash == scHash
    _ -> False
  }
}

fn get_inputs_from_sc(inputs: List<Input>, scHash: ByteArray) -> List<Input> {
  list.filter(inputs, fn(input) { is_output_to_sc(input.output, scHash) })
}
