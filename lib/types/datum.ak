use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address}
use types/general.{CardanoToken}

pub type DatumParameters {
  min_to_stake: Int,
  owner: ByteArray,
  address_rewards: Address,
  min_ada: Int,
}

pub type DatumStaker {
  owner: VerificationKeyHash,
}

//Each utxo has it's datum and can be used as Babel Fee OR as scheduled tx
//Each utxo can contain only 1 scheduled tx, meaning that multiple schedule txs are different utxos
//we'll be adding some ADA more in the scheduled utxo to cover fees of the batcher
pub type DatumTank {
  allowedTokens: List<CardanoToken>,
  tankOwner: Address,
  whitelistedAddresses: List<Address>,
  executionTime: Int,
  destionationaAddress: Address,
  scheduledAmount: CardanoToken,
  reward: CardanoToken,
}
