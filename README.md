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

forge script test/Stargate.t.sol:StargateIntegerDivisionTest --rpc-url http://localhost:8545 --broadcast -vvvv --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --via-ir --gas-price 10000000

```shell
forge script test/FlashLoanAave.t.sol:DeployAndFlashLoanAave \
  --rpc-url http://localhost:8545 \
  --broadcast -vvvv \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \


forge script test/FlashLoanUniswap.t.sol:DeployAndFlashLoanUniswap \
  --rpc-url http://localhost:8545 \
  --broadcast -vvvv \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \


forge script test/UniswapSwap-v3.t.sol:DeployAndSwapUniswapV3 \
  --rpc-url http://localhost:8545 \
  --broadcast -vvvv \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \

forge script test/UniswapSwap-v2.t.sol:DeployAndSwapUniswapV2 \
  --rpc-url http://localhost:8545 \
  --broadcast -vvvv \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \

forge script test/UniswapSwap-CombinedSwap.t.sol:DeployAndExecuteSwaps \
  --rpc-url http://localhost:8545 \
  --broadcast -vvvv \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \

forge script test/DeployAndFlashLoanMorphoUniswap.t.sol:DeployAndFlashLoanMorphoUniswap \
  --rpc-url http://localhost:8545 \
  --broadcast -vvvv \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \


forge script test/DeployAndFlashLoanMorpho.t.sol:DeployAndFlashLoanMorpho \
  --rpc-url http://localhost:8545 \
  --broadcast -vvvv \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \


forge script test/Stargate.t.sol:StargateIntegerDivisionTest \
  --rpc-url http://localhost:8545 \
  --broadcast -vvvv \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \


forge script test/DeployMorphoVulberability.t.sol:DeployMorphoVulberability \
  --rpc-url http://localhost:8545 \
  --broadcast -vvvv \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \

```
