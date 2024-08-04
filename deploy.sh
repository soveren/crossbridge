#!/bin/bash
forge build || exit 1
cargo build --release --target wasm32-unknown-unknown --package chain_fusion || exit 1

function kill_process_on_port() {
  # Find process IDs listening on port 8545 (anvil)
  anvil=$(lsof -t -i:$1)

  # Check if any PIDs were found
  if [ -z "$anvil" ]; then
      echo "Anvil not running."
  else
      # Kill the processes
      kill $anvil && echo "Terminated running Anvil process."
      sleep 3
  fi
}

kill_process_on_port 8545
kill_process_on_port 9545
kill_process_on_port 7545
# start anvil with slots in an epoch send to 1 for faster finalised blocks
anvil --slots-in-an-epoch 1 &
anvil --slots-in-an-epoch 1 -p 9545 --chain-id 9999 &
anvil --slots-in-an-epoch 1 -p 7545 --chain-id 7777 &

# kill caddyserver
caddy stop
# start caddyserver
caddy start
dfx stop
# Find process IDs listening on port 4943 (dfx)
dfx=$(lsof -t -i:4943)
# Check if any PIDs were found
if [ -z "$dfx" ]; then
    echo "dfx not running."
else
    # Kill the processes
    kill $dfx && echo "Terminating running dfx instance."
    sleep 3
fi
dfx start --clean --background
dfx ledger fabricate-cycles --icp 10000 --canister $(dfx identity get-wallet)
dfx deploy evm_rpc
dfx canister create --with-cycles 10_000_000_000_000 chain_fusion
# because the local smart contract deployment is deterministic, we can hardcode the
# the `get_logs_address` here. in our case we are listening for NewJob events,
# you can read more about event signatures [here](https://docs.alchemy.com/docs/deep-dive-into-eth_getlogs#what-are-event-signatures)
dfx canister install --wasm target/wasm32-unknown-unknown/release/chain_fusion.wasm chain_fusion --argument '(
  record {
    chains = vec {
        record {
          31337 : nat;
          variant {
            Custom = record {
              chainId = 31_337 : nat64;
              services = vec { record { url = "https://localhost:8546"; headers = null } };
            }
          }
        };
        record {
          9999 : nat;
          variant {
            Custom = record {
              chainId = 9999 : nat64;
              services = vec { record { url = "https://localhost:9546"; headers = null } };
            }
          }
        };
        record {
          7777 : nat;
          variant {
            Custom = record {
              chainId = 7777 : nat64;
              services = vec { record { url = "https://localhost:7546"; headers = null } };
            }
          }
        }
      };
    ecdsa_key_id = record {
      name = "dfx_test_key";
      curve = variant { secp256k1 };
    };
    get_logs_topics = opt vec {
      vec {
        "0xef20696aab2ce9892f7f57a105f3ab3c1fc1f81ac582ebdedb5eb28789a0f516";
      };
    };
    last_scraped_block_number = 0: nat;
    rpc_services = variant {
      Custom = record {
        chainId = 31_337 : nat64;
        services = vec { record { url = "https://localhost:8546"; headers = null } };
      }
    };
    rpc_service = variant {
      Custom = record {
        url = "https://localhost:8546";
        headers = null;
      }
    };
    get_logs_addresses = vec { "0x5FbDB2315678afecb367f032d93F642f64180aa3" };
    block_tag = variant { Latest = null };
  },
)'
# sleep for 3 seconds to allow the evm address to be generated
sleep 3
# safe the chain_fusion canisters evm address
export EVM_ADDRESS=$(dfx canister call chain_fusion get_evm_address | awk -F'"' '{print $2}')
echo "EVM_ADDRESS=$EVM_ADDRESS"
# deploy the contract passing the chain_fusion canisters evm address to receive the fees and create a couple of new jobs
forge script script/Coprocessor.s.sol:MyScript --fork-url http://localhost:8545 --broadcast --sig "run(address)" $EVM_ADDRESS
forge script script/Coprocessor.s.sol:MyScript --fork-url http://localhost:9545 --broadcast --sig "run(address)" $EVM_ADDRESS
forge script script/Coprocessor.s.sol:MyScript --fork-url http://localhost:7545 --broadcast --sig "run(address)" $EVM_ADDRESS

# Top up coprocessor canister address
cast send --from 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC $EVM_ADDRESS --value 2000ether --rpc-url http://127.0.0.1:9545 --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
cast send --from 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC $EVM_ADDRESS --value 2000ether --rpc-url http://127.0.0.1:7545 --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

#cast send 0x5fbdb2315678afecb367f032d93f642f64180aa3 "bridge(uint)" 9999 --private-key=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d --value 3ether
#cast b 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url http://127.0.0.1:9545
