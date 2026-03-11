## Protocol Specification

ARES Protocol governs the lifecycle of on-chain actions through a structured, secure, and time-locked process. This lifecycle ensures that all actions are subject to community approval and a mandatory cooling-off period before execution, providing robust defenses against malicious proposals and economic attacks.

The lifecycle consists of five distinct phases:

1.  **Proposal Creation**
2.  **Approval**
3.  **Queueing**
4.  **Execution**
5.  **Cancellation**

---

#### 1. Proposal Creation

A proposal is a formal request to execute an on-chain action, such as transferring funds from the treasury, calling a function on another contract, or upgrading the system.

*   **Initiation**: Any user can initiate a proposal by calling one of the `propose<Action>` functions (e.g., `proposeTransfer`, `proposeCall`).
*   **Economic Staking (Anti-Griefing)**: To prevent spam and frivolous proposals, the proposer must lock a predetermined amount of ARES tokens (`PROPOSAL_STAKE`) in the DAO contract. This stake is held until the proposal is either executed or cancelled.
*   **State Transition**: Upon creation, a `Proposal` struct is stored on-chain with its status set to `COMMITTED`, making it eligible for voting. An event (`ProposalStatusChanged`) is emitted to notify off-chain listeners.

#### 2. Approval

Once a proposal is created, it enters the approval phase where eligible members of the DAO cast their votes.

*   **Eligibility (Anti-Flash Loan)**: Voting rights are determined by a Merkle allowlist. A user must provide a cryptographic proof to verify their address was included in the off-chain snapshot when the Merkle root was generated. This mechanism prevents flash-loan-based governance attacks, as token balance at the time of voting is irrelevant.
*   **Voting Mechanism**: The primary method for voting is `voteBySig`, which utilizes the **EIP-712** standard for typed, structured data signing. This provides several key benefits:
    *   **Gasless Voting**: Voters can sign a message off-chain (for free), and a third-party "relayer" can submit the signature to the blockchain, paying the gas on the voter's behalf.
    *   **User Safety**: Wallets display the vote data in a human-readable format, ensuring users know exactly what they are authorizing.
    *   **Replay Protection**: The signature includes a unique `nonce` and is bound to the specific contract and chain (`DOMAIN_SEPARATOR`), preventing it from being re-used in other contexts.
*   **State Transition**: When the number of votes for a proposal reaches the `MIN_QUORUM`, its status is automatically transitioned to `ACCEPTED`. An event (`ProposalStatusChanged`) is emitted.

#### 3. Queueing

An `ACCEPTED` proposal does not execute immediately. It must first be placed into a time-locked execution queue.

*   **Initiation**: Anyone can call the `queueProposal` function for an `ACCEPTED` proposal.
*   **Timelock ETA**: The contract calculates the earliest possible execution time (`eta`) by adding the mandatory `TIMELOCKDELAY` (e.g., 2 days) to the current block timestamp.
*   **Transaction Hashing**: A unique hash of the proposal's target, value, data, and its `eta` is generated and stored in the execution queue (`ARES_Exec_Eng`). This prevents any modification to the proposal after it has been queued.

#### 4. Execution

After the `TIMELOCKDELAY` has passed, the proposal becomes eligible for execution.

*   **Initiation**: Anyone can call the `executeProposal` function to trigger the queued transaction.
*   **Verification**: The system performs several critical checks:
    *   It ensures the timelock period has passed (`block.timestamp >= eta`).
    *   It ensures the proposal has not expired (i.e., is within the `GRACE_PERIOD`).
    *   It ensures the proposal has not already been executed.
*   **State Transition**: The transaction is removed from the queue *before* the external call is made to prevent re-entrancy attacks. The action is then executed. Upon successful execution, the proposal is marked as `executed`, and the original proposer's stake is refunded.

#### 5. Cancellation

A proposal can be cancelled by an administrator at any point before it is executed. This serves as a final safeguard against malicious or flawed proposals that may have passed the voting phase.

*   **Initiation**: An address with administrative privileges calls the `denialProposal` function.
*   **State Transition**: The proposal's status is set to `DENIED`.
*   **Queue Invalidation**: If the proposal had already been queued for execution, it is explicitly removed from the `ARES_Exec_Eng` queue. This is a critical step to ensure a vetoed proposal cannot be executed by directly calling the public `execute` function.
*   **Stake Refund**: The proposer's stake is immediately refunded.

