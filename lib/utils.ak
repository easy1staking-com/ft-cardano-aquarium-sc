use aiken/collection/list
use cardano/transaction.{Input, Output, ScriptPurpose, Spend}
use cardano/address.{Address, Script,}

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
