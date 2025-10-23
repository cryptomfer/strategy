## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

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

## Environment & Forks

### Copy env template

Create a local .env from the provided example and fill in RPCs and (optionally) fork blocks:

`shell
cp .env.example .env
# then edit .env to set at least:
# RPC_URL_ETHEREUM=...
# RPC_URL_BASE=...
# (optional) FORK_BLOCK_ETHEREUM=...
# (optional) FORK_BLOCK_BASE=...
`

### Run unit tests

`shell
forge test -vv
# or via Makefile
make test
`

### Run fork tests

Fork tests read RPC URLs and block numbers from env. Ensure .env has the values, then run:

`shell
forge test -vv --match-path test/integration/FactoryFork.t.sol
`

## CI RPCs via Secrets

The CI workflow at .github/workflows/ci.yml installs Foundry nightly and runs build + tests. It reads RPC URLs and fork blocks from repository Secrets:

- RPC_URL_ETHEREUM
- RPC_URL_BASE
- FORK_BLOCK_ETHEREUM (optional but recommended)
- FORK_BLOCK_BASE (optional but recommended)

Add them in GitHub: Settings ? Secrets and variables ? Actions ? New repository secret.
