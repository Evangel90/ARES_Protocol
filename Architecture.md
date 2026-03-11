# ARES Protocol Architecture

## System Architecture

The ARES Protocol implements a decoupled governance architecture designed to separate decision-making logic from asset storage. The system is primarily composed of two discrete smart contracts: **ARES_DAO** and **ARES_Vault**.

### The Core Components

1.  **ARES_DAO (Governance Layer)**:
    This contract acts as the protocol's brain. It aggregates voting logic, proposal lifecycle management, and execution orchestration. It is constructed by composing several abstract modules (`ARES_Auth`, `ARES_Exec_Eng`, `ARES_Distributor`) into a single deployment. This aggregation allows the DAO to handle everything from EIP-712 signature verification to Merkle airdrop claims within a shared storage context, reducing inter-contract call overhead for governance operations.

2.  **ARES_Vault (Asset Layer)**:
    This contract serves as the treasury. It operates independently of the DAO's deployment cycle, ensuring that governance logic upgrades do not require migrating assets. The Vault holds the `ARES` token supply and enforces economic security policies, such as daily withdrawal limits. It maintains a pointer (`address public dao`) to the current governance contract, authorizing it to trigger fund distributions or withdrawals.

## Module Separation

The codebase utilizes a modular mixin pattern. Rather than deploying a web of interacting micro-services, the DAO inherits functionality from abstract contracts and libraries. This flattens the architecture for gas efficiency while keeping code logic distinct.

### Abstract Modules

*   **ARES_Exec_Eng (Execution Engine)**:
    Inherited by the DAO, this module manages the time-locked execution queue. It implements the "Checks-Effects-Interactions" pattern to prevent re-entrancy during proposal execution. By isolating this logic, the DAO delegates the complex state management of `queuedTransactions` (hashing, ETA calculation, expiration) to a specialized component using `ExecutionLib`.

*   **ARES_Auth (Authentication)**:
    This module provides the cryptographic layer for off-chain voting. It implements EIP-712 structured data hashing to verify signatures for `voteBySig`. It manages nonces per user, preventing replay attacks without requiring on-chain transaction history for every vote.

*   **ARES_Distributor (Distribution)**:
    Handles the logic for mass token distribution. It utilizes a Bitmap library (`BitmapLib`) to track claimed indices efficiently (using 1 bit per user). This module allows the DAO to function as a Merkle Distributor without needing a separate airdrop contract.

*   **ARES_Control (Access Control)**:
    A base layer inherited by both the DAO and the Vault. It utilizes `AccessControlLib` to standardize role management (`admins`, `members`) across the system.

### Libraries

*   **AccessControlLib**: Encapsulates storage layout and logic for role management.
*   **ExecutionLib**: Encapsulates the storage and state transitions for the proposal queue.
*   **BitmapLib**: Low-level bit manipulation for efficient boolean tracking.

## Security Boundaries

The protocol enforces security through strict privilege separation and temporal boundaries.

### 1. The DAO-Vault Boundary
The Vault does not trust the DAO implicitly. Instead, it exposes specific entry points (`protectedWithdraw`, `distribute`) guarded by the `onlyDAO` modifier.
*   **Authorization**: The Vault checks `msg.sender == dao`. This ensures that funds can only move if the DAO contract successfully executes a passed proposal or triggers a valid airdrop claim.
*   **Rate Limiting**: Even if the DAO authorizes a withdrawal, the Vault enforces its own `DAILY_LIMIT` (circuit breaker). This creates a hard security boundary that governance cannot bypass instantaneously.

### 2. The Voting-Execution Boundary
There is a deliberate "air gap" between a passed vote and execution:
*   **Timelock**: A proposal reaching `ACCEPTED` status cannot modify state immediately. It must be hashed and placed in the `ARES_Exec_Eng` queue for a minimum `TIMELOCKDELAY`.
*   **Immutability**: The queue stores a hash of the execution data. This guarantees that the parameters approved by voters (target, value, calldata) are bit-for-bit identical to what is eventually executed.

### 3. Economic Boundary (Staking)
The system creates a boundary against spam via `PROPOSAL_STAKE`. Write access to the proposal array is gated behind a token lock. This ensures that only actors with "skin in the game" can trigger the governance machinery, protecting the protocol from griefing attacks.

## Trust Assumptions

While the architecture minimizes trust, specific actors and off-chain processes retain privileged positions.

### Administrative Trust
The `admins` role possesses significant power, breaking the "code is law" paradigm in favor of safety rails:
*   **Veto Power**: Admins can call `denialProposal` to cancel a malicious proposal even after it has passed the voting phase. The community trusts admins to use this only for protecting the protocol, not for censorship.
*   **Emergency Access**: Admins can bypass the voting process to call `protectedWithdraw` (up to the daily limit) and `setDAO`. This assumes admins will not collude to drain the daily allowance.
*   **Upgradability**: The admins control the `upgradeVault` function. The system assumes admins will not deploy a malicious implementation that steals funds.

### Off-Chain Data Integrity
The system relies on the correctness of data generated off-chain:
*   **Merkle Roots**: Both voting eligibility (`merkleRoot`) and token distribution (`distributionRoot`) are set by admins. The smart contract cannot verify if the tree construction includes all legitimate users. The community must trust the off-chain scripts and the admins who commit these roots.
*   **Timestamps**: The `ARES_Exec_Eng` relies on `block.timestamp`. The system assumes that miners/validators will not manipulate timestamps to a degree that would significantly impact the 2-day timelock or grace periods.