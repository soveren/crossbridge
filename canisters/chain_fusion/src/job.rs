// mod calculate_result;
mod submit_result;

use std::fmt;
use ethers_core::types::{Address, U256};
use evm_rpc_canister_types::LogEntry;
use ic_cdk::println;
use submit_result::submit_result;

use crate::{
    // job::calculate_result::fibonacci,
    state::{mutate_state, LogSource},
};

pub async fn job(event_source: LogSource, event: LogEntry) {
    mutate_state(|s| s.record_processed_log(event_source.clone()));
    // because we deploy the canister with topics only matching
    // NewJob events we can safely assume that the event is a NewJob.
    let new_job_event = NewJobEvent::from(event);
    println!("<<<NEW JOB>>>: {new_job_event:?}");

    // TODO calculate amount out, based on value_in and coprocessor_balances over networks
    // TODO read dst chain balance and calculate amount out
    let value_out = new_job_event.value_in / 2; // for now we just divide the value_in by 2
    // we write the result back to the evm smart contract, creating a signature
    // on the transaction with chain key ecdsa and sending it to the evm via the
    // evm rpc canister
    submit_result(new_job_event.job_id, new_job_event.to_chain_id, new_job_event.receiver_address, value_out).await;
    println!("Successfully ran job #{:?}", &new_job_event.job_id);
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct NewJobEvent {
    pub from_chain_id: U256,
    pub job_id: U256,
    pub transaction_hash: U256,
    pub log_index: U256,
    pub coprocessor_balance: U256,
    pub to_chain_id: U256,
    pub receiver_address: Address,
    pub value_in: U256
}

impl fmt::Debug for NewJobEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("NewJobEvent")
            .field("from_chain_id", &self.from_chain_id)
            .field("job_id", &self.job_id)
            .field("transaction_hash", &self.transaction_hash)
            .field("log_index", &self.log_index)
            .field("coprocessor_balance", &self.coprocessor_balance)
            .field("to_chain_id", &self.to_chain_id)
            .field("receiver_address", &self.receiver_address)
            .field("value_in", &self.value_in)
            .finish()
    }
}

fn u256_to_address(value: U256) -> Address {
    // Convert U256 to a 32-byte array
    let mut bytes = [0u8; 32];
    value.to_big_endian(&mut bytes);

    // Extract the lower 20 bytes for the Ethereum address
    // Ethereum addresses are 20 bytes long, so we skip the first 12 bytes
    let address_bytes: [u8; 20] = bytes[12..].try_into().expect("slice with incorrect length");

    Address::from(address_bytes)
}

impl From<LogEntry> for NewJobEvent {
    fn from(entry: LogEntry) -> NewJobEvent {
        // you can read more about event signatures [here](https://docs.alchemy.com/docs/deep-dive-into-eth_getlogs#what-are-event-signatures)
        // set job id as U256 from entry.transactionHash
        let from_chain_id = U256::from(111); // TODO fill in the correct chain id from service
        let transaction_hash = U256::from_str_radix(&entry.transactionHash.expect("no transactionHash"), 16).expect("transactionHash should be valid");
        let log_index =U256::from_big_endian(&entry.logIndex.expect("no logIndex").0.to_bytes_be());
        let job_id = transaction_hash + log_index;
        let to_chain_id = U256::from_str_radix(&entry.topics[1], 16).expect("chain_id should be valid");
        let receiver_address_u256 = U256::from_str_radix(&entry.topics[2], 16).expect("receiver_address should be valid");
        let receiver_address = u256_to_address(receiver_address_u256);
        let value_in = U256::from_str_radix(&entry.topics[3], 16).expect("value_in should be valid");
        let coprocessor_balance = U256::from_str_radix(&entry.data, 16).expect("coprocessor_balance should be valid");

        NewJobEvent { from_chain_id, job_id, transaction_hash, log_index, coprocessor_balance, to_chain_id, receiver_address, value_in }
    }
}
