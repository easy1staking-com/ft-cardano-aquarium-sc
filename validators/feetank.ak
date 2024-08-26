use aiken/cbor
use aiken/list.{length}
use aiken/time.{PosixTime}
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, Transaction,
}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value.{AssetName, PolicyId, Value, flatten, quantity_of}
use utils.{get_inputs_from_sc, get_own_hash}

type CardanoToken {
  policyId: PolicyId,
  assetName: AssetName,
  amount: Int,
  divider: Int,
}

type Datum {
  allowedTokens: List<CardanoToken>,
  tankOwner: Address,
  whitelistedAddresses: List<Address>,
  exectutionTime: PosixTime,
  destionationaAddress: Address,
  scheduledAmount: CardanoToken,
  reward: CardanoToken,
}

type Redeemer {
  Consume { payingToken: CardanoToken, inputTankIndex: Int, receivers: Int }
  ConsumeAll { payingToken: CardanoToken, inputTankIndex: Int, receivers: Int }
  Withdraw
  ScheduledTransaction { inputTankIndex: Int }
}

validator {
  fn acquariumValidator(datum: Datum, redeemer: Redeemer, ctx: ScriptContext) {
    let ownScriptHash = get_own_hash(ctx.purpose, ctx.transaction.inputs)
    when ctx.purpose is {
      Spend(currentInput) ->
        when redeemer is {
          Consume(payingToken, inputTankIndex, receivers) -> {
            expect Some(inputTank) =
              list.at(
                get_inputs_from_sc(ctx.transaction.inputs, ownScriptHash),
                inputTankIndex,
              )
            let inputTankAsOutput = inputTank.output

            expect Some(outputTank) =
              list.at(ctx.transaction.outputs, inputTankIndex)
            expect Some(outputPayment) =
              list.at(ctx.transaction.outputs, inputTankIndex + 1)

            // calculate fee of transaction (ADA)
            let feeAmount = quantity_of(ctx.transaction.fee, "", "")

            let outputPaymentAmount =
              quantity_of(
                outputPayment.value,
                payingToken.policyId,
                payingToken.assetName,
              )

            let inputTankAmount = quantity_of(inputTankAsOutput.value, "", "")

            and {
              currentInput == inputTank.output_reference,
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
              isWhitelisted(ctx.transaction, datum.whitelistedAddresses),
            }
          }

          ConsumeAll(payingToken, inputTankIndex, receivers) -> {
            expect Some(inputTank) =
              list.at(
                get_inputs_from_sc(ctx.transaction.inputs, ownScriptHash),
                inputTankIndex,
              )
            let inputTankAsOutput = inputTank.output

            expect Some(outputPayment) =
              list.at(ctx.transaction.outputs, inputTankIndex)

            // calculate fee of transaction (ADA)
            let feeAmount = quantity_of(ctx.transaction.fee, "", "")

            let outputPaymentAmount =
              quantity_of(
                outputPayment.value,
                payingToken.policyId,
                payingToken.assetName,
              )

            let inputTankAmount = quantity_of(inputTankAsOutput.value, "", "")

            and {
              currentInput == inputTank.output_reference,
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
              isWhitelisted(ctx.transaction, datum.whitelistedAddresses),
            }
          }

          Withdraw -> must_be_signed_by(ctx.transaction, datum.tankOwner)
          //Schedule mette come primo output il pagamento, come secondo eventualmente quello di ritorno alla tank
          ScheduledTransaction(inputTankIndex) -> {
            expect Some(outputScheduled) =
              list.at(ctx.transaction.outputs, inputTankIndex)
            expect Some(outputChange) =
              list.at(ctx.transaction.outputs, inputTankIndex + 1)
            expect Some(inputTank) =
              list.at(
                get_inputs_from_sc(ctx.transaction.inputs, ownScriptHash),
                inputTankIndex,
              )
            let inputTankAmount = quantity_of(inputTank.output.value, "", "")
            //add index validation
            let outputPaymentAmount =
              quantity_of(
                outputScheduled.value,
                datum.scheduledAmount.policyId,
                datum.scheduledAmount.assetName,
              )
            and {
              currentInput == inputTank.output_reference,
              validate_scheduled_output(
                outputScheduled,
                outputPaymentAmount,
                datum.scheduledAmount,
                datum.destionationaAddress,
              ),
              isWhitelisted(ctx.transaction, datum.whitelistedAddresses),
              validate_change_output(
                datum,
                outputChange,
                inputTankAmount,
                datum.scheduledAmount.amount + datum.reward.amount,
              ),
            }
          }
        }
      //verifica che sia davvero a quell'index l'input
      // Controlla se almeno uno è firmato
      _ -> False
    }
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
  trace @"Ada going back into tank wrong or wrong datum or wrong address of tank"
  trace cbor.diagnostic(outputTankAmount)
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
  trace @"payment output wrong"
  trace cbor.diagnostic(receivers)
  trace cbor.diagnostic(feeAmount)
  trace cbor.diagnostic(payingToken.amount / payingToken.divider)
  trace cbor.diagnostic(outputPaymentAmount)

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
  trace @"token not allowed"
  list.has(allowedTokens, payingToken)
}

fn check_dos_protection(value: Value) {
  trace @"dos protection"
  length(flatten(value)) <= 5
}

fn must_be_signed_by(transaction: Transaction, address: Address) {
  expect VerificationKeyCredential(hash) = address.payment_credential
  list.has(transaction.extra_signatories, hash)
}

fn isWhitelisted(transaction: Transaction, whitelistedAddresses: List<Address>) {
  trace @"whitelist wrong"
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
        exectutionTime: datum.exectutionTime,
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
