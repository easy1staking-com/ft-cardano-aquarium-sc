use cardano/assets.{AssetName, PolicyId}

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
  CardanoSignature
  CardanoSpendScript
  CardanoWithdrawScript
  CardanoMintScript
}

pub type Authorization {
  method: AuthorizationMethod,
  hash: ByteArray,
}
