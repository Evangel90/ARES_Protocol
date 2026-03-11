// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../libraries/ExecutionLib.sol";

/// @title ARES Execution Engine
/// @notice Handles the queuing and execution of transactions with a timelock delay.
/// @dev Designed to be inherited by the DAO. Implements a queue-based execution architecture.
abstract contract ARES_Exec_Eng {
    using ExecutionLib for ExecutionLib.State;
    error ReentrancyGuardReentrantCall();

    // --- State ---
    ExecutionLib.State internal executionState;

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

    function queuedTransactions(bytes32 txHash) public view returns (uint256) {
        return executionState.queuedTransactions[txHash];
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
        return executionState.queue(target, value, data, delay);
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
        return executionState.execute(target, value, data, eta);
    }

    function _cancel(bytes32 txHash) internal {
        executionState.cancel(txHash);
    }
}