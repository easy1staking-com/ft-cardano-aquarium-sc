use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{InlineDatum, Input, OutputReference, Transaction}
use constants
use types/datum.{DatumParameters}
use types/redeemer.{RedeemerStaker}

//the process is simple, every user can mint an NFT, I can stake multiple times but no advantage
//to unstake I need to burn the NFT, I can unstake multiple times
//there is no need of datum, everything needed is stored in the address format

//To mint we check that the first output is in the staking contract and the right user is signing, only 1 NFT per time, and deposit checked
//To unstake and spend the utxo I just need to burn the NFT inside my staking address

//Users that get airdrop for whatever reason can get it

validator staker(
  params_contract_hash: ByteArray,
  fldt_policy: ByteArray,
  fldt_asset: ByteArray,
) {
  spend(
    _datum: Option<Data>,
    _redeemer: RedeemerStaker,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(input) =
      self.inputs
        |> transaction.find_input(own_ref)

    expect Script(contract) = input.output.address.payment_credential
    when input.output.address.stake_credential is {
      None -> False
      Some(stake_cred) ->
        when stake_cred is {
          Inline(a) -> {
            expect VerificationKey(hash) = a
            or {
              and {
                quantity_of(input.output.value, contract, hash) == 0,
                list.has(self.extra_signatories, hash),
              },
              and {
                list.has(self.extra_signatories, hash),
                quantity_of(self.mint, contract, hash) < 0,
              },
            }
          }
          _ -> False
        }
    }
  }

  mint(redeemer: RedeemerStaker, policy_id: PolicyId, tx: Transaction) {
    //if 1000 FLDT staked in the right address minta nello stesso output, il primo,redeeme signature inclusa
    expect Some(referenceInput) =
      list.at(tx.reference_inputs, redeemer.reference_index)
    expect InlineDatum(datum) = referenceInput.output.datum
    expect datum_params: DatumParameters = datum

    let fldt_min_amount = datum_params.min_to_stake

    expect Some(stake_cred_signer) = redeemer.signer.stake_credential
    expect Inline(stake_key_hash) = stake_cred_signer
    expect VerificationKey(hash) = stake_key_hash

    expect Some(output_staking) = list.at(tx.outputs, redeemer.output_staking)
    let contractCredential = Script(policy_id)

    let active_stake_address: Address =
      Address {
        payment_credential: contractCredential,
        stake_credential: redeemer.signer.stake_credential,
      }

    let inputs_from_contract = count_inputs(tx.inputs, policy_id)

    or {
      //Se minted value <0,
      and {
        dict.size(tokens(tx.mint, policy_id)) == 1,
        quantity_of(tx.mint, policy_id, hash) == -1 * inputs_from_contract,
        list.has(tx.extra_signatories, hash),
      },
      and {
        //First output goes to stake address correct
        output_staking.address == active_stake_address,
        //I must stake at least min amount
        quantity_of(output_staking.value, fldt_policy, fldt_asset) >= fldt_min_amount,
        //only 1 token of same policy
        dict.size(tokens(tx.mint, policy_id)) == 1,
        //I must send the NFT I send, each user has different NFT assetname 
        quantity_of(output_staking.value, policy_id, hash) == 1,
        //I am minting only 1 NFT
        quantity_of(tx.mint, policy_id, hash) == 1,
        //I am signing with staking hash
        list.has(tx.extra_signatories, hash),
        quantity_of(
          referenceInput.output.value,
          params_contract_hash,
          constants.config_asset_name,
        ) == 1,
      },
    }
  }

  else(_) {
    fail
  }
}

fn count_inputs(inputs: List<Input>, policy: ByteArray) {
  inputs
    |> list.count(
        fn(input) { input.output.address.payment_credential == Script(policy) },
      )
}
