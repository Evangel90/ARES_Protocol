// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library ExecutionLib {
    error ExecutionNotReady(uint256 eta, uint256 currentTimestamp);
    error ExecutionExpired(uint256 eta, uint256 currentTimestamp);
    error TransactionAlreadyQueued(bytes32 txHash);
    error TransactionNotQueued(bytes32 txHash);
    error ExecutionFailed(bytes data);
    error InvalidDelay();

    event TransactionQueued(bytes32 indexed txHash, address indexed target, uint256 value, bytes data, uint256 eta);
    event TransactionExecuted(bytes32 indexed txHash, address indexed target, uint256 value, bytes data, uint256 actualExecutionTime);
    event TransactionCancelled(bytes32 indexed txHash);

    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant MAX_DELAY = 30 days;

    struct State {
        mapping(bytes32 => uint256) queuedTransactions;
    }

    function queue(State storage self, address target, uint256 value, bytes memory data, uint256 delay) internal returns (bytes32 txHash) {
        if (delay < MIN_DELAY || delay > MAX_DELAY) revert InvalidDelay();
        
        uint256 eta = block.timestamp + delay;
        txHash = keccak256(abi.encode(target, value, data, eta));

        if (self.queuedTransactions[txHash] != 0) revert TransactionAlreadyQueued(txHash);

        self.queuedTransactions[txHash] = eta;
        emit TransactionQueued(txHash, target, value, data, eta);
    }

    function cancel(State storage self, bytes32 txHash) internal {
        if (self.queuedTransactions[txHash] == 0) revert TransactionNotQueued(txHash);
        delete self.queuedTransactions[txHash];
        emit TransactionCancelled(txHash);
    }

    function execute(State storage self, address target, uint256 value, bytes memory data, uint256 eta) internal returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, data, eta));
        uint256 queuedEta = self.queuedTransactions[txHash];
        if (queuedEta == 0) revert TransactionNotQueued(txHash);
        if (block.timestamp < queuedEta) revert ExecutionNotReady(queuedEta, block.timestamp);
        if (block.timestamp > queuedEta + GRACE_PERIOD) revert ExecutionExpired(queuedEta, block.timestamp);
        delete self.queuedTransactions[txHash];
        (bool success, bytes memory returnData) = target.call{value: value}(data);
        if (!success) revert ExecutionFailed(returnData);
        emit TransactionExecuted(txHash, target, value, data, block.timestamp);
        return returnData;
    }
}