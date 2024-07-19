mod calculate_result;
mod submit_result;

use std::fmt;

use ethers_core::types::U256;
use ethers_core::types::U128;
use evm_rpc_canister_types::LogEntry;
use ic_cdk::println;
use submit_result::submit_result;

use crate::{
    job::calculate_result::fibonacci,
    state::{mutate_state, LogSource},
};

pub async fn job(event_source: LogSource, event: LogEntry) {
    mutate_state(|s| s.record_processed_log(event_source.clone()));
    // because we deploy the canister with topics only matching
    // NewJob events we can safely assume that the event is a NewJob.
    let new_job_event = NewJobEvent::from(event);
    println!("<<<NEW JOB>>>: {new_job_event:?}");

    // this calculation would likely exceed an ethereum blocks gas limit
    // but can easily be calculated on the IC
    let result = fibonacci(20);
    // we write the result back to the evm smart contract, creating a signature
    // on the transaction with chain key ecdsa and sending it to the evm via the
    // evm rpc canister
    submit_result(result.to_string(), new_job_event.job_id).await;
    println!("Successfully ran job #{:?}", &new_job_event.job_id);
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct NewJobEvent {
    pub job_id: U256,
    pub coprocessor_balance: U256,
    pub chain_id: U256,
    pub receiver_address: String,
    pub value_in: U256
}

impl fmt::Debug for NewJobEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("NewJobEvent")
            .field("job_id", &self.job_id)
            .field("coprocessor_balance", &self.coprocessor_balance)
            .field("chain_id", &self.chain_id)
            .field("receiver_address", &self.receiver_address)
            .field("value_in", &self.value_in)
            .finish()
    }
}

impl From<LogEntry> for NewJobEvent {
    fn from(entry: LogEntry) -> NewJobEvent {
        println!("NewJobEvent entry.topics.len: {:?}", entry.topics.len());
        // you can read more about event signatures [here](https://docs.alchemy.com/docs/deep-dive-into-eth_getlogs#what-are-event-signatures)
        let joined_id = U256::from_str_radix(&entry.topics[1], 16).expect("the token id should be valid");
        let job_id = joined_id & U256::from(U128::max_value());
        let chain_id = joined_id >> 128;
        let receiver_address = entry.topics[2].clone();
        let value_in = U256::from_str_radix(&entry.topics[3], 16).expect("the token value_in should be valid");
        let coprocessor_balance = U256::from_str_radix(&entry.data, 16).expect("the token coprocessor_balance should be valid");

        NewJobEvent { job_id, coprocessor_balance, chain_id, receiver_address, value_in }
    }
}
