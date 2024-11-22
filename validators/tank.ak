use aiken/collection/list.{length}
use aiken/interval.{Finite}
use aiken/math/rational.{from_int}
use aiken/option.{is_none}
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{Value, flatten, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use types/general.{CardanoToken}
use types/redeemer.{Aggregated, Dedicated, OraclePriceFeed, Pooled}
use utils.{retrieve_oracle_data, validate_oracle_ref_input}

pub type DatumParameters {
  min_to_stake: Int,
  owner: ByteArray,
  address_rewards: Address,
}

//Each utxo has it's datum and can be used as Babel Fee OR as scheduled tx
//Each utxo can contain only 1 scheduled tx, meaning that multiple schedule txs are different utxos
//we'll be adding some ADA more in the scheduled utxo to cover fees of the batcher
pub type Datum {
  allowedTokens: List<CardanoToken>,
  tankOwner: Address,
  whitelistedAddresses: List<Address>,
  executionTime: Int,
  destionationaAddress: Address,
  scheduledAmount: CardanoToken,
  reward: CardanoToken,
}

pub type Redeemer {
  Consume { payingToken: CardanoToken, inputTankIndex: Int, receivers: Int }
  ConsumeAll { payingToken: CardanoToken, inputTankIndex: Int, receivers: Int }
  Withdraw
  ScheduledTransaction {
    inputTankIndex: Int,
    batcher: Address,
    reference_staking_index: Int,
    reference_params_index: Int,
  }
  ConsumeOracle {
    payingToken: CardanoToken,
    inputTankIndex: Int,
    receivers: Int,
    oracleIndex: Int,
  }
  ConsumeAllOracle {
    payingToken: CardanoToken,
    inputTankIndex: Int,
    receivers: Int,
    oracleIndex: Int,
  }
}

validator tank(stakingContract: ByteArray, params_contract_hash: ByteArray) {
  spend(
    datum: Option<Datum>,
    redeemer: Redeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(input) =
      self.inputs
        |> transaction.find_input(own_ref)
    expect Script(ownScriptHash) = input.output.address.payment_credential

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
          Consume(payingToken, inputTankIndex, receivers) -> {
            expect Some(inputTank) =
              list.at(
                get_inputs_from_sc(self.inputs, ownScriptHash),
                inputTankIndex,
              )
            let inputTankAsOutput = inputTank.output

            expect Some(outputTank) = list.at(self.outputs, inputTankIndex)
            expect Some(outputPayment) =
              list.at(self.outputs, inputTankIndex + 1)

            // calculate fee of transaction (ADA)
            let feeAmount = self.fee

            let outputPaymentAmount =
              quantity_of(
                outputPayment.value,
                payingToken.policyId,
                payingToken.assetName,
              )

            let inputTankAmount = quantity_of(inputTankAsOutput.value, "", "")

            and {
              own_ref == inputTank.output_reference,
              verify_paying_with_allowed_token(datum.allowedTokens, payingToken),
              validate_tank_output(
                inputTank,
                outputTank,
                inputTankAmount,
                feeAmount,
                receivers,
              ),
              validate_payment_output(
                outputPayment,
                outputPaymentAmount,
                feeAmount,
                payingToken,
                datum.tankOwner,
                receivers,
              ),
              isWhitelisted(self, datum.whitelistedAddresses),
              is_none(payingToken.oracle),
            }
          }

          ConsumeAll(payingToken, inputTankIndex, receivers) -> {
            expect Some(inputTank) =
              list.at(
                get_inputs_from_sc(self.inputs, ownScriptHash),
                inputTankIndex,
              )
            let inputTankAsOutput = inputTank.output

            expect Some(outputPayment) = list.at(self.outputs, inputTankIndex)

            // calculate fee of transaction (ADA)
            let feeAmount = self.fee

            let outputPaymentAmount =
              quantity_of(
                outputPayment.value,
                payingToken.policyId,
                payingToken.assetName,
              )

            let inputTankAmount = quantity_of(inputTankAsOutput.value, "", "")

            and {
              own_ref == inputTank.output_reference,
              // verify that the paying token is greater than the fee

              inputTankAmount <= feeAmount,
              verify_paying_with_allowed_token(datum.allowedTokens, payingToken),
              validate_payment_output(
                outputPayment,
                outputPaymentAmount,
                feeAmount,
                payingToken,
                datum.tankOwner,
                receivers,
              ),
              isWhitelisted(self, datum.whitelistedAddresses),
              is_none(payingToken.oracle),
            }
          }

          Withdraw -> must_be_signed_by(self, datum.tankOwner)
          //Schedule mette come primo output il pagamento, come secondo eventualmente quello di ritorno alla tank
          ScheduledTransaction(
            inputTankIndex,
            batcher,
            reference_staking_index,
            reference_params_index,
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
              isWhitelisted(self, datum.whitelistedAddresses),
              validate_time(self, datum.executionTime),
              list.has(self.extra_signatories, hash),
              referenceInput.output.address.stake_credential == batcher.stake_credential,
              quantity_of(referenceInput.output.value, stakingContract, hash) == 1,
              quantity_of(
                referenceInputParams.output.value,
                params_contract_hash,
                "parameters",
              ) == 1,
            }
          }
          ConsumeOracle(payingToken, inputTankIndex, receivers, oracleIndex) -> {
            expect Some(oracleRefInput) =
              list.at(self.reference_inputs, oracleIndex)
            expect
              validate_oracle_ref_input(
                oracleRefInput.output.value,
                payingToken,
              ) == True

            expect Some(inputTank) =
              list.at(
                get_inputs_from_sc(self.inputs, ownScriptHash),
                inputTankIndex,
              )
            let inputTankAsOutput = inputTank.output

            expect Some(outputTank) = list.at(self.outputs, inputTankIndex)
            expect Some(outputPayment) =
              list.at(self.outputs, inputTankIndex + 1)

            // calculate fee of transaction (ADA)
            let feeAmount = self.fee

            let outputPaymentAmount =
              quantity_of(
                outputPayment.value,
                payingToken.policyId,
                payingToken.assetName,
              )

            let inputTankAmount = quantity_of(inputTankAsOutput.value, "", "")
            expect Finite(end) = self.validity_range.upper_bound.bound_type
            expect Some(oraclePriceFeed) =
              retrieve_oracle_data(
                oracleRefInput,
                self.redeemers,
                end,
                payingToken,
              )

            and {
              own_ref == inputTank.output_reference,
              verify_paying_with_allowed_token(datum.allowedTokens, payingToken),
              validate_tank_output(
                inputTank,
                outputTank,
                inputTankAmount,
                feeAmount,
                receivers,
              ),
              validate_payment_output_oracle(
                outputPayment,
                outputPaymentAmount,
                feeAmount,
                payingToken,
                datum.tankOwner,
                receivers,
                oraclePriceFeed,
              ),
              isWhitelisted(self, datum.whitelistedAddresses),
            }
          }
          _ -> False
        }
    }
  }

  else(_) {
    fail
  }
}

fn validate_tank_output(
  inputTank: Input,
  outputTank: Output,
  inputTankAmount: Int,
  feeAmount: Int,
  receivers: Int,
) {
  let outputTankAmount = quantity_of(outputTank.value, "", "")

  and {
    check_dos_protection(outputTank.value),
    // verify that the output tank is equal than the input tank - fee (only ADA)
    outputTankAmount >= inputTankAmount - feeAmount - 1500000 * (
      receivers + 1
    ),
    // verify that the input tank datum is equal to the output tank datum
    inputTank.output.datum == outputTank.datum,
    outputTank.address == inputTank.output.address,
  }
}

fn validate_payment_output(
  outputPayment: Output,
  outputPaymentAmount: Int,
  feeAmount: Int,
  payingToken: CardanoToken,
  tankOwner: Address,
  receivers: Int,
) {
  and {
    ( feeAmount + 1500000 * receivers ) * payingToken.amount / payingToken.divider <= outputPaymentAmount,
    outputPayment.address == tankOwner,
    check_dos_protection(outputPayment.value),
  }
}

fn validate_payment_output_oracle(
  outputPayment: Output,
  outputPaymentAmount: Int,
  feeAmount: Int,
  _payingToken: CardanoToken,
  tankOwner: Address,
  receivers: Int,
  oraclePriceFeed: OraclePriceFeed,
) {
  when oraclePriceFeed is {
    Aggregated(aggregated_data) -> {
      expect Some(tokenPrice) =
        rational.new(
          aggregated_data.token_price_in_lovelaces,
          aggregated_data.denominator,
        )
      //This price is in lovelace
      expect Some(minTokenPayment) =
        rational.div(from_int(feeAmount + 1500000 * receivers), tokenPrice)
      and {
        rational.ceil(minTokenPayment) <= outputPaymentAmount,
        outputPayment.address == tankOwner,
        check_dos_protection(outputPayment.value),
      }
    }
    Pooled(pooled_data) -> {
      //Is this correct? tokenA is the liquidity pair and tokenB is the token itself
      expect Some(tokenPrice) =
        rational.new(pooled_data.token_a_amount, pooled_data.token_b_amount)
      expect Some(minTokenPayment) =
        rational.div(from_int(feeAmount + 1500000 * receivers), tokenPrice)
      and {
        rational.ceil(minTokenPayment) <= outputPaymentAmount,
        outputPayment.address == tankOwner,
        check_dos_protection(outputPayment.value),
      }
    }
    Dedicated(dedicated_data) -> {
      expect Some(tokenPrice) =
        rational.new(dedicated_data.token_price, dedicated_data.denominator)
      //This should work only if this oracle is providing lovelace price
      expect Some(minTokenPayment) =
        rational.div(from_int(feeAmount + 1500000 * receivers), tokenPrice)
      and {
        rational.ceil(minTokenPayment) <= outputPaymentAmount,
        outputPayment.address == tankOwner,
        check_dos_protection(outputPayment.value),
      }
    }
  }
}

fn verify_paying_with_allowed_token(
  allowedTokens: List<CardanoToken>,
  payingToken: CardanoToken,
) {
  list.has(allowedTokens, payingToken)
}

fn check_dos_protection(value: Value) {
  length(flatten(value)) <= 5
}

fn must_be_signed_by(transaction: Transaction, address: Address) {
  expect VerificationKey(hash) = address.payment_credential
  list.has(transaction.extra_signatories, hash)
}

fn isWhitelisted(transaction: Transaction, whitelistedAddresses: List<Address>) {
  if list.length(whitelistedAddresses) > 0 {
    list.any(
      whitelistedAddresses,
      fn(addr) { must_be_signed_by(transaction, addr) },
    )
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
