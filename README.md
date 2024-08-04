# Heart Bridge 
> Permissionless Joined Liquidity AMM Native Cross Bridge

[Small Demo Video](https://youtu.be/dqytDV9VKvc)

## Table of Contents


## Overview

Heart Bridge - is the cross bridge based on ICP Chain Fusion. 
It gives ability swap native tokens from one chain to another with minimal time and fees.

### Permissionless 
Users do not need approval for bridging tokens, adding or removing liquidity.

### AMM (Automated Market Maker)
Like Uniswap, but not for ERC20 tokens, for Networks.

### Joined Liquidity
But, in comparison with Uniswap, we do not need to have separate pairs and liquidity pools 
for each destination (i.e. BSC-Polygon (BNB/MATIC), BSC-Fantom (BNB/FTM): 
all destinations served from one pool at each network. 

It looks like DEX multi-token pool joined by math.
Math is inspired by [Caval.re Multiswap](https://caval.re/) and under research and development.

### Native
Bridge supports native tokens only to decrease swap fees and avoid token owner manipulations 
(for example almost all stable coins can be blocked, 
and if bridge contract will be blocked it can stop all bridge  traffic with this token). 

Our bridge can not be locked.

### Cross Bridge
It is not specific network-to-network bridge - this is cross bridge, 
so you will be able to swap from/to any networks, supported by ChainFusion.

For Stage 1 is only EVM-compatible networks will be supported. 

### Why Use Heart Bridge?
- Truly decentralized 
- Cheap (as we use simple smart contracts and native transfers only)
- Fast (Events not only scraped by timer, but will be pushed by Websocket Notifier 
- (see [this article](https://internetcomputer.org/blog/features/websockets-poc))
- It is good for users, traders, market makers, arbitrageurs


## Getting Started

To deploy the project locally, run `./deploy.sh` from the project root. This script will:

-   Start 3 `anvil` networks
-   Start `dfx`
-   Deploy the EVM contract to 3 networks
-   Deploy the coprocessor canister

Check the `deploy.sh` script comments for detailed deployment steps.

### Manual Setup

Ensure the following are installed on your system:

-   [Node.js](https://nodejs.org/en/) `>= 21`
-   [Foundry](https://github.com/foundry-rs/foundry)
-   [Caddy](https://caddyserver.com/docs/install#install)
-   [DFX](https://internetcomputer.org/docs/current/developer-docs/build/install-upgrade-remove) `>= 0.18`

Run these commands in a new, empty project directory:

```sh
git clone https://github.com/soveren/crossbridge.git
cd crossbridge
```

## Architecture

This starter project involves multiple canisters working together to process events emitted by an EVM smart contract. The contracts involved are:

-   **EVM Smart Contract**: (on each supported network) Emits events such as `Bridge` when specific functions are called. 
-   **Chain Fusion Canister (`chain_fusion`)**: Listens to events emitted by the EVM smart contract, processes them, and sends the results back to the EVM smart contract.
-   **EVM RPC Canister**: Facilitates communication between the Internet Computer and EVM-based blockchains by making RPC calls to interact with the EVM smart contract.

### EVM Smart Contract

The `contracts/Coprocessor.sol` contract emits a `NewJob` event when the `newJob` function is called, transferring ETH to the `chain_fusion` canister to pay it for job processing and transaction fees (this step is optional and can be customized to fit your use case).

```solidity
/// @dev Bridge the value to another chain
/// @param toChainId The chain id to bridge to
function bridge(uint toChainId)
external payable  {
    coprocessor.transfer(msg.value);
    emit Bridge(toChainId, msg.sender, msg.value, coprocessor.balance);
}
```

The `deliver` function writes processed results back to the contract:

```solidity
function deliver(uint jobId, address payable receiver) external payable  {
    require(msg.sender == coprocessor);
    receiver.transfer(msg.value);
    emit Delivery(jobId, receiver, msg.value, coprocessor.balance);
}
```

For local deployment, see the `deploy.sh` script and `script/Coprocessor.s.sol`.

### Chain Fusion Canister

The `chain_fusion` canister listens to `Bridge` events by periodically calling the `eth_getLogs` RPC method via the [EVM RPC canister](https://github.com/internet-computer-protocol/evm-rpc-canister). Upon receiving an event, it processes the job and sends the results back to the EVM smart contract via the EVM RPC canister, signing the transaction with threshold ECDSA.



## CLI

If you want to check that the `chain_fusion` canister really processed the events, you can either look at the logs output by running `./deploy.sh` – 
keep an eye open for the `<<<NEW JOB>>>` or `Successfully ran job` message – or you can call the EVM contract to get the results of the jobs. To do this, run:

```sh

Note for now that the Chain Fusion Canister only scrapes logs every 15 seconds, so you may need to wait a minute before seeing the new bridge job processed.
In the future, we will have [Notifier service](https://internetcomputer.org/blog/features/websockets-poc) 
to initiate transfers immediately.   

### Networks

We run 3 networks locally:
1. chainId 31337 : https://localhost:8546
2. chainId 9999 : https://localhost:9546
3. chainId 7777 : https://localhost:7546

### Transfers
To chainId 9999
```sh
cast send 0x5fbdb2315678afecb367f032d93f642f64180aa3 "bridge(uint)" 9999 --value 9ether --private-key=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

To chainId 7777
```sh
cast send 0x5fbdb2315678afecb367f032d93f642f64180aa3 "bridge(uint)" 7777  --value 7ether --private-key=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

For now, while swap math is not implemented, bridge just transfers 1/2 of value to the destination chain.
Job id is constructed from tx hash and log index to avoid additional storage and gas costs.

Unfortunatelly, for now you can transfer only from chainId 31337 as logs are not yet scraped from other networks. It is main next feature to do. 

### Check balance
You can check balance of the Coprocessor contract on each network by running:
```sh
cast b 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url https://localhost:8546
cast b 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url https://localhost:9546
cast b 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url https://localhost:7546
```

# What's next?
1. Scrape events from all enabled networks
2. Finish and connect multi pool math
3. Connect deposit / withdraw functions for liquidity providers
4. Batch transfers
5. Cover all by tests, tests, tests
6. Develop minimal UI
7. Deploy to production networks in BETA stage
8. Tests, tests and tests
