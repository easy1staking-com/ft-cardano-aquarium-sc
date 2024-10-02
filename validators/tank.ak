use aiken/collection/list.{length}
use aiken/interval.{Finite}
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId, Value, flatten, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}

pub type CardanoToken {
  policyId: PolicyId,
  assetName: AssetName,
  amount: Int,
  divider: Int,
}

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
  ScheduledTransaction { inputTankIndex: Int, batcher: Address }
}

validator tank(stakingContract: ByteArray) {
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
            }
          }

          Withdraw -> must_be_signed_by(self, datum.tankOwner)
          //Schedule mette come primo output il pagamento, come secondo eventualmente quello di ritorno alla tank
          ScheduledTransaction(inputTankIndex, batcher) -> {
            expect Some(outputScheduled) = list.at(self.outputs, inputTankIndex)
            expect Some(outputChange) =
              list.at(self.outputs, inputTankIndex + 1)
            expect Some(inputTank) =
              list.at(
                get_inputs_from_sc(self.inputs, ownScriptHash),
                inputTankIndex,
              )

            expect Some(referenceInput) = list.at(self.reference_inputs, 0)
            let inputTankAmount = quantity_of(inputTank.output.value, "", "")
            //add index validation
            let outputPaymentAmount =
              quantity_of(
                outputScheduled.value,
                datum.scheduledAmount.policyId,
                datum.scheduledAmount.assetName,
              )

            expect Some(stake_cred_signer) = batcher.stake_credential
            expect Inline(stake_key_hash) = stake_cred_signer
            expect VerificationKey(hash) = stake_key_hash
            and {
              own_ref == inputTank.output_reference,
              validate_scheduled_output(
                outputScheduled,
                outputPaymentAmount,
                datum.scheduledAmount,
                datum.destionationaAddress,
              ),
              isWhitelisted(self, datum.whitelistedAddresses),
              validate_change_output(
                datum,
                outputChange,
                inputTankAmount,
                datum.scheduledAmount.amount + datum.reward.amount,
              ),
              validate_time(self, datum.executionTime),
              list.has(self.extra_signatories, hash),
              referenceInput.output.address.stake_credential == batcher.stake_credential,
              quantity_of(referenceInput.output.value, stakingContract, hash) == 1,
            }
          }
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

fn validate_change_output(
  datum: Datum,
  outputPayment: Output,
  starting: Int,
  amountAway: Int,
) {
  if amountAway == starting {
    True
  } else {
    expect InlineDatum(output_datum) = outputPayment.datum
    expect parsed_datum: Datum = output_datum

    let newAmount =
      CardanoToken { policyId: "", assetName: "", amount: 0, divider: 1000000 }

    let newDatum =
      Datum {
        allowedTokens: datum.allowedTokens,
        tankOwner: datum.tankOwner,
        whitelistedAddresses: datum.whitelistedAddresses,
        executionTime: datum.executionTime,
        destionationaAddress: datum.tankOwner,
        scheduledAmount: newAmount,
        reward: newAmount,
      }

    let outputAmountToTank = quantity_of(outputPayment.value, "", "")

    and {
      parsed_datum == newDatum,
      check_dos_protection(outputPayment.value),
      outputAmountToTank >= starting - amountAway,
    }
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
