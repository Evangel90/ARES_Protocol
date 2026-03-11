// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title ARES Execution Engine
/// @notice Handles the queuing and execution of transactions with a timelock delay.
/// @dev Designed to be inherited by the DAO. Implements a queue-based execution architecture.
abstract contract ARES_Exec_Eng {
    // --- Errors ---
    error ExecutionNotReady(uint256 eta, uint256 currentTimestamp);
    error ExecutionExpired(uint256 eta, uint256 currentTimestamp);
    error TransactionAlreadyQueued(bytes32 txHash);
    error TransactionNotQueued(bytes32 txHash);
    error ExecutionFailed(bytes data);
    error ReentrancyGuardReentrantCall();
    error InvalidDelay();

    // --- Events ---
    event TransactionQueued(bytes32 indexed txHash, address indexed target, uint256 value, bytes data, uint256 eta);
    event TransactionExecuted(bytes32 indexed txHash, address indexed target, uint256 value, bytes data, uint256 actualExecutionTime);
    event TransactionCancelled(bytes32 indexed txHash);

    // --- Constants ---
    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant MAX_DELAY = 30 days;

    // --- State ---
    /// @notice Mapping of transaction hash to its Execution Time (ETA)
    mapping(bytes32 => uint256) public queuedTransactions;

    // --- Reentrancy Guard State ---
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Queues a transaction for execution after a delay.
     * @param target The contract address to call.
     * @param value The amount of ETH to send.
     * @param data The calldata to execute.
     * @param delay The delay in seconds before execution can occur.
     * @return txHash The unique hash of the queued transaction.
     */
    function _queue(
        address target,
        uint256 value,
        bytes memory data,
        uint256 delay
    ) internal returns (bytes32 txHash) {
        // Timestamp Manipulation Protection: Enforce min/max delay bounds
        if (delay < MIN_DELAY || delay > MAX_DELAY) revert InvalidDelay();

        uint256 eta = block.timestamp + delay;
        
        // Transaction Replacement Protection: Hash includes all parameters + eta
        txHash = keccak256(abi.encode(target, value, data, eta));

        if (queuedTransactions[txHash] != 0) revert TransactionAlreadyQueued(txHash);

        queuedTransactions[txHash] = eta;
        emit TransactionQueued(txHash, target, value, data, eta);
    }

    /**
     * @dev Executes a queued transaction.
     * @notice Can be called by anyone after the delay has passed and before the grace period expires.
     */
    function execute(
        address target,
        uint256 value,
        bytes memory data,
        uint256 eta
    ) public payable nonReentrant returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, data, eta));
        uint256 queuedEta = queuedTransactions[txHash];

        if (queuedEta == 0) revert TransactionNotQueued(txHash);

        // Timestamp & Expiration Checks
        if (block.timestamp < queuedEta) revert ExecutionNotReady(queuedEta, block.timestamp);
        if (block.timestamp > queuedEta + GRACE_PERIOD) revert ExecutionExpired(queuedEta, block.timestamp);

        // Replay Protection: Remove from queue BEFORE execution (Checks-Effects-Interactions)
        delete queuedTransactions[txHash];

        // Execute
        (bool success, bytes memory returnData) = target.call{value: value}(data);
        if (!success) revert ExecutionFailed(returnData);

        emit TransactionExecuted(txHash, target, value, data, block.timestamp);
        return returnData;
    }

    function _cancel(bytes32 txHash) internal {
        if (queuedTransactions[txHash] == 0) revert TransactionNotQueued(txHash);
        delete queuedTransactions[txHash];
        emit TransactionCancelled(txHash);
    }
}