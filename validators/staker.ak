use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{Input, OutputReference, Transaction}

pub type Datum {
  owner: VerificationKeyHash,
}

pub type Redeemer {
  signer: Address,
}

//the process is simple, every user can mint an NFT, I can stake multiple times but no advantage
//to unstake I need to burn the NFT, I can unstake multiple times
//there is no need of datum, everything needed is stored in the address format

//To mint we check that the first output is in the staking contract and the right user is signing, only 1 NFT per time, and deposit checked
//To unstake and spend the utxo I just need to burn the NFT inside my staking address

//Users that get airdrop for whatever reason can get it

validator staker {
  spend(
    _datum: Option<Datum>,
    _redeemer: Redeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(input) =
      self.inputs
        |> transaction.find_input(own_ref)

    expect Script(contract) = input.output.address.payment_credential

    let inputs_from_contract = count_inputs(self.inputs, input)
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
                quantity_of(self.mint, contract, hash) == -1 * inputs_from_contract,
                list.has(self.extra_signatories, hash),
              },
            }
          }
          _ -> False
        }
    }
  }

  mint(redeemer: Redeemer, policy_id: PolicyId, tx: Transaction) {
    //if 1000 FLDT staked in the right address minta nello stesso output, il primo,redeeme signature inclusa
    let fldt_policy = #""
    let fldt_asset = #""
    let fldt_min_amount = 1000

    expect Some(stake_cred_signer) = redeemer.signer.stake_credential
    expect Inline(stake_key_hash) = stake_cred_signer
    expect VerificationKey(hash) = stake_key_hash

    expect Some(output_staking) = list.at(tx.outputs, 0)
    let contractCredential = Script(policy_id)

    let active_stake_address: Address =
      Address {
        payment_credential: contractCredential,
        stake_credential: redeemer.signer.stake_credential,
      }
    or {
      //Se minted value <0,
      and {
        dict.size(tokens(tx.mint, policy_id)) == 1,
        quantity_of(tx.mint, policy_id, hash) == -1,
        list.has(tx.extra_signatories, hash),
      },
      and {
        True,
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
      },
    }
  }

  else(_) {
    fail
  }
}

fn count_inputs(inputs: List<Input>, input: Input) {
  list.foldl(
    inputs,
    0,
    fn(n, total) {
      if n.output.address == input.output.address {
        total + 1
      } else {
        total
      }
    },
  )
}
