use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{Input}

pub type Asset {
  policyId: PolicyId,
  assetName: AssetName,
}

pub type CardanoToken {
  policyId: PolicyId,
  assetName: AssetName,
  amount: Int,
  divider: Int,
  oracle: Option<Asset>,
}

pub type AuthorizationMethod {
  CardanoSignature { hash: ByteArray }
  CardanoSpendScript { hash: ByteArray }
  CardanoWithdrawScript { hash: ByteArray }
  CardanoMintScript { hash: ByteArray }
}

pub type Authorization {
  CardanoSignatureAuth {
    hash: ByteArray,
    extra_signatories: List<VerificationKeyHash>,
  }
  CardanoSpendScriptAuth { hash: ByteArray, transaction_inputs: List<Input> }
  CardanoWithdrawScriptAuth {
    hash: ByteArray,
    withdrawals: Pairs<Credential, Int>,
  }
  CardanoMintScriptAuth { hash: ByteArray, transaction_mint: Value }
}
