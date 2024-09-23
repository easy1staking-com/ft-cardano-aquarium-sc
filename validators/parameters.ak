use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{OutputReference, Transaction}

//Fluid owner address is the only that can mint or destory reference inputs
const owner = #"1c471b31ea0b04c652bd8f76b239aea5f57139bdc5a2b28ab1e69175"

pub type DatumParameters {
  min_to_stake: Int,
}

pub type Redeemer {
  signer: Address,
}

//this contract allows to fluid project to update the parameters regarding min amount to stake

validator parameters {
  spend(
    _datum: Option<DatumParameters>,
    _redeemer: Redeemer,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    list.has(self.extra_signatories, owner)
  }

  mint(redeemer: Redeemer, policy_id: PolicyId, tx: Transaction) {
    expect Some(output_parameters) = list.at(tx.outputs, 0)
    let contractCredential = Script(policy_id)

    expect Some(stake_cred_signer) = redeemer.signer.stake_credential
    expect Inline(stake_key_hash) = stake_cred_signer
    expect VerificationKey(hash) = stake_key_hash

    let active_parameters_address: Address =
      Address {
        payment_credential: contractCredential,
        stake_credential: redeemer.signer.stake_credential,
      }
    or {
      //Se minted value <0,
      and {
        dict.size(tokens(tx.mint, policy_id)) == 1,
        quantity_of(tx.mint, policy_id, hash) == -1,
        list.has(tx.extra_signatories, owner),
      },
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
      },
    }
  }

  else(_) {
    fail
  }
}
