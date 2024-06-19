use aiken/list.{length}
use aiken/transaction.{Input, Output, ScriptContext, Spend, Transaction}
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
}

type Redeemer {
  Consume { payingToken: CardanoToken, inputTankIndex: Int }
  ConsumeAll { payingToken: CardanoToken, inputTankIndex: Int }
  Withdraw
}

validator {
  fn acquariumValidator(datum: Datum, redeemer: Redeemer, ctx: ScriptContext) {
    let ownScriptHash = get_own_hash(ctx.purpose, ctx.transaction.inputs)
    when ctx.purpose is {
      Spend(currentInput) ->
        when redeemer is {
          Consume(payingToken, inputTankIndex) -> {
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
              ),
              validate_payment_output(
                outputPayment,
                outputPaymentAmount,
                feeAmount,
                payingToken,
                datum.tankOwner,
              ),
            }
          }

          ConsumeAll(payingToken, inputTankIndex) -> {
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
              ),
            }
          }

          Withdraw -> must_be_signed_by(ctx.transaction, datum.tankOwner)
        }
      _ -> False
    }
  }
}

fn validate_tank_output(
  inputTank: Input,
  outputTank: Output,
  inputTankAmount: Int,
  feeAmount: Int,
) {
  let outputTankAmount = quantity_of(outputTank.value, "", "")
  and {
    check_dos_protection(outputTank.value),
    // verify that the output tank is equal than the input tank - fee (only ADA)
    outputTankAmount >= inputTankAmount - feeAmount,
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
) {
  and {
    feeAmount * payingToken.amount / payingToken.divider <= outputPaymentAmount,
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
