use ethers_core::{types::U256};
use ethers_core::abi::{Address, Token};
use evm_rpc_canister_types::{SendRawTransactionStatus, EVM_RPC, RpcServices, EvmRpcCanister};

use ic_evm_utils::eth_send_raw_transaction::{contract_interaction, ContractDetails, get_data, get_function, IntoChainId, send_raw_transaction};
use ic_evm_utils::evm_signer::sign_eip1559_transaction;
use ic_evm_utils::fees::{estimate_transaction_fees, FeeEstimates};
use crate::state::{mutate_state, read_state, State};
use ic_cdk::api::management_canister::ecdsa::EcdsaKeyId;
use std::str::FromStr;
use ethers_core::types::Eip1559TransactionRequest;

pub async fn contract_interaction_with_value(
    contract_details: ContractDetails<'_>,
    gas: Option<U256>,
    rpc_services: RpcServices,
    nonce: U256,
    key_id: EcdsaKeyId,
    derivation_path: Vec<Vec<u8>>,
    evm_rpc: EvmRpcCanister,
    value: U256,
) -> SendRawTransactionStatus {
    let function = get_function(&contract_details);
    let data = get_data(function, &contract_details);

    let FeeEstimates {
        max_fee_per_gas,
        max_priority_fee_per_gas,
    } = estimate_transaction_fees(9, rpc_services.clone(), evm_rpc.clone()).await;

    // assemble the transaction
    let tx = Eip1559TransactionRequest {
        to: Some(
            Address::from_str(&contract_details.contract_address)
                .expect("should be a valid address")
                .into(),
        ),
        gas,
        data: Some(data.into()),
        nonce: Some(nonce),
        max_priority_fee_per_gas: Some(max_priority_fee_per_gas),
        max_fee_per_gas: Some(max_fee_per_gas),
        chain_id: Some(rpc_services.chain_id()),
        from: Default::default(),
        value: Some(value),
        access_list: Default::default(),
    };

    // sign the transaction using chain key signatures
    let tx = sign_eip1559_transaction(tx, key_id, derivation_path).await;

    // send the transaction via the EVM RPC canister
    send_raw_transaction(tx, rpc_services, evm_rpc).await
}

pub async fn submit_result(job_id: U256, receiver_address: Address, value_out: U256) {
    // TODO rebuild to use transfer_eth instead of contract_interaction
    // get necessary global state
    let contract_address = &read_state(State::get_logs_addresses)[0];
    let rpc_services = read_state(State::rpc_services);
    let nonce = read_state(State::nonce);
    let key_id = read_state(State::key_id);

    let abi_json = r#"
   [
    {
      "type": "function",
      "name": "deliver",
      "inputs": [
        {
          "name": "jobId",
          "type": "uint256",
          "internalType": "uint256"
        },
        {
          "name": "receiver",
          "type": "address",
          "internalType": "address payable"
        }
      ],
      "outputs": [],
      "stateMutability": "payable"
    }
   ]
   "#;

    let abi =
        serde_json::from_str::<ethers_core::abi::Contract>(abi_json).expect("should serialise");

    let contract_details = ContractDetails {
        contract_address: contract_address.clone(),
        abi: &abi,
        function_name: "deliver",
        args: &[Token::Uint(job_id), Token::Address(receiver_address)],
    };

    // set the gas
    let gas = Some(U256::from(5000000));

    // interact with the contract, this calls `eth_sendRawTransaction` under the hood
    let status = contract_interaction_with_value(
        contract_details,
        gas,
        rpc_services,
        nonce,
        key_id,
        vec![],
        EVM_RPC,
        value_out,
    )
    .await;

    // if the transaction
    match status {
        SendRawTransactionStatus::Ok(transaction_hash) => {
            ic_cdk::println!("Success {transaction_hash:?}");
            mutate_state(|s| {
                s.nonce += U256::from(1);
            });
        }
        SendRawTransactionStatus::NonceTooLow => {
            ic_cdk::println!("Nonce too low");
        }
        SendRawTransactionStatus::NonceTooHigh => {
            ic_cdk::println!("Nonce too high");
        }
        SendRawTransactionStatus::InsufficientFunds => {
            ic_cdk::println!("Insufficient funds");
        }
    }
}
