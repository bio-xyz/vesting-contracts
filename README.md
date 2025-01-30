## Smart Contracts

### TokenVesting Contract

The base vesting contract that implements core vesting functionality and virtual token features.

#### Features
- **Vesting Schedule Management**:
  - Configurable start time, cliff period, and duration
  - Customizable slice periods for gradual token release
  - Optional revocability per schedule
  - Admin controls for schedule management

- **Virtual Token Implementation**:
  - ERC20-compatible interface
  - Non-transferable by design
  - Balance represents vested tokens
  - Automatic balance updates on vesting events

- **Access Control**:
  - `DEFAULT_ADMIN_ROLE`: Can manage vesting schedules and contract settings
  - `VESTING_CREATOR_ROLE`: Can create new vesting schedules

#### Inheritance
- OpenZeppelin's AccessControlDefaultAdminRules
- OpenZeppelin's ReentrancyGuard
- OpenZeppelin's Pausable
- IERC20Metadata

#### Key Functions
- `createVestingSchedule()`: Creates new vesting schedules
- `release()`: Releases vested tokens to beneficiaries
- `revoke()`: Allows admin to revoke revocable schedules
- `withdraw()`: Enables admin to withdraw unused tokens

#### Security Features
- Reentrancy protection on critical functions
- Pausable functionality for emergency stops
- Role-based access control
- Comprehensive input validation

### TokenVestingMerkle Contract

Extends TokenVesting with Merkle tree functionality for efficient schedule distribution.

#### Features
- **Merkle Tree Integration**:
  - Efficient proof verification
  - Prevention of double-claiming
  - Batch schedule distribution support

#### Inheritance
- TokenVesting

#### Key Functions
- `claimSchedule()`: Claims vesting schedule using Merkle proof
- `updateMerkleRoot()`: Updates the Merkle root
- `scheduleClaimed()`: Checks if a schedule has been claimed

### TokenVestingMerklePurchasable Contract

Extends TokenVestingMerkle with purchasing capabilities.

#### Features
- **Purchase Mechanism**:
  - ETH payments for vesting schedules
  - Configurable cost per vToken
  - Customizable payment receiver

#### Inheritance
- TokenVestingMerkle

#### Key Functions
- `claimSchedule()`: Claims schedule with payment
- `setVTokenCost()`: Updates the cost per vToken
- `setPaymentReceiver()`: Sets payment receiver address

### Deprecated Contracts

Located in `src/deprecated/`:

#### MultiTokenVesting
- Enables querying vesting balances across multiple contracts
- Supports external vesting contract integration

#### MultiTokenVestingMerklePurchasable
- Combines MultiTokenVesting and TokenVestingMerklePurchasable
- Supports cross-contract schedule verification

## Key Features

- **Flexible Vesting Schedules**: Configure start time, cliff period, duration, and release intervals
- **Access Control**: Role-based permissions for administrative functions
- **Safety Features**: Includes reentrancy protection and pausable functionality
- **Virtual Token**: ERC20-compatible representation of vested tokens (non-transferable)
- **Merkle Tree Support**: Efficient distribution of vesting schedules
- **Purchase Options**: Optional ETH payment for vesting schedule creation

## Test Coverage

The smart contracts have been thoroughly tested with comprehensive coverage across all active contracts:

### Core Contracts
- **TokenVesting.sol**:
  - Lines: 97.96% (96/98)
  - Statements: 98.48% (130/132)
  - Branches: 95.45% (21/22)
  - Functions: 95.45% (21/22)

- **TokenVestingMerkle.sol**:
  - Lines: 100% (16/16)
  - Statements: 100% (13/13)
  - Branches: 100% (2/2)
  - Functions: 100% (4/4)

- **TokenVestingMerklePurchasable.sol**:
  - Lines: 100% (29/29)
  - Statements: 93.55% (29/31)
  - Branches: 66.67% (4/6)
  - Functions: 100% (6/6)

### Test Suite Summary
- Total Tests: 54
- Passing Tests: 54
- Failed Tests: 0
- Skipped Tests: 0

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

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

