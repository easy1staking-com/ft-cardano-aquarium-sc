use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Address, Script}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}

//Fluid owner address is the only that can mint or destory reference inputs
const owner = #"1c471b31ea0b04c652bd8f76b239aea5f57139bdc5a2b28ab1e69175"

pub type DatumParameters {
  min_to_stake: Int,
}

pub type Redeemer {
  signer: Address,
}

//this contract allows to fluid project to update the parameters regarding min amount to stake
//the contract is parametric and can mint only once

validator parameters(tx0: ByteArray, index0: Int) {
  spend(
    _datum: Option<DatumParameters>,
    _redeemer: Redeemer,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect Some(input_contract) = find_input(tx.inputs, own_ref)
    expect Some(output_contract) = list.at(tx.outputs, 0)
    expect InlineDatum(datum) = output_contract.datum
    //value can be anything but the type must be Datum Parameters
    expect _datum_params: DatumParameters = datum

    expect Script(contract) = input_contract.output.address.payment_credential

    and {
      input_contract.output.value == output_contract.value,
      input_contract.output.address == output_contract.address,
      list.has(tx.extra_signatories, owner),
      quantity_of(input_contract.output.value, contract, "parameters") == 1,
    }
  }

  mint(redeemer: Redeemer, policy_id: PolicyId, tx: Transaction) {
    expect Some(output_parameters) = list.at(tx.outputs, 0)
    let contractCredential = Script(policy_id)

    let one_time_utxo = OutputReference(tx0, index0)
    //we won't use input_present, we just need it to be there, otherwise error
    expect Some(_input_present) = find_input(tx.inputs, one_time_utxo)

    let active_parameters_address: Address =
      Address {
        payment_credential: contractCredential,
        stake_credential: redeemer.signer.stake_credential,
      }
    and {
      True,
      //First output goes to stake address correct
      output_parameters.address == active_parameters_address,
      //only 1 token of same policy
      dict.size(tokens(tx.mint, policy_id)) == 1,
      //I must send the NFT I send, each user has different NFT assetname 
      quantity_of(output_parameters.value, policy_id, "parameters") == 1,
      //I am minting only 1 NFT
      quantity_of(tx.mint, policy_id, "parameters") == 1,
      //I am signing with staking hash
      list.has(tx.extra_signatories, owner),
    }
  }

  else(_) {
    fail
  }
}
