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

//----------- CHARLIE 3 LIBRARY -----------------
pub type PriceMap =
  Pairs<Int, Int>

/// Represents different types of price data
pub type PriceData {
  /// Placeholder for shared data across multiple oracles
  SharedData
  /// Placeholder for extended data with additional information
  ExtendedData
  /// Generic data structure for price information
  GenericData { price_map: PriceMap }
}

/// Represents the main oracle datum structure
pub type OracleDatum {
  price_data: PriceData,
}

//For each token we support from charlie3 we get have a PolicyId from charlie3 and also a decimals of the token 
pub type CharlieTokenSpecs =
  Pairs<PolicyId, Pairs<AssetName, (PolicyId, Int)>>
