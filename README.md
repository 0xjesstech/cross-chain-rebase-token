## Cross chain rebase token 

1.  A protocol that allows users to deposit into a vault and in return, receive rebase tokens that represent their underlying balance
2. Rebase token: balanceOf function is dynamic to show the changing balance with time. 
   -  Balance increases linearly with time 
   -  Mint tokens to our users every time they perform an action (minting, burning, transferring, or... bridging). so the state will not be updated for a users. balance until they perform an action, but they will have been accruing tokens 
3. Interest rate 
  - individually set an interest rate for each user based on some global interest rate of the protocol at the time the user deposits into the vault.
  - This global interest rate can only decrease to incentivize /reward early adopters.
  - Increase token adoption

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Prerequisites

Create an .env file and add the following with your RPC URLs.

```
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/<YOUR_RPC_URL>
ARB_SEPOLIA_RPC_URL=https://arb-sepolia.g.alchemy.com/v2/<YOUR_RPC_URL>
```

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
