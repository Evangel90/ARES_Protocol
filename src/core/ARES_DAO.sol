// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../modules/ARES_Vault.sol';

contract ARES_DAO is ARES_Vault{
    enum ActionType { TRANSFER, CALL, UPGRADE }
    enum CommitPhase { COMMITTED, DENIED, ACCEPTED }

    uint public MIN_QUORUM = 3;
    uint256 public TIMELOCKDELAY = 2 days;

    mapping (uint => mapping (address => bool)) public Voted;

    struct Proposal {
        uint proposalId;
        ActionType actionType;
        CommitPhase commitPhase;
        string description;
        address target;
        uint value;
        bytes data;
        uint voteCount;
        uint executionTime;
        bool executed;
    }

    Proposal[] public proposals;

    event ProposalStatusChanged(uint indexed proposalId, CommitPhase indexed phase);
    event ProposalExecuted(uint indexed proposalId, uint indexed timeExecuted);

    constructor(address[] memory _admins) ARES_Vault(_admins) {}

    function proposeTransfer(address token, address recipient, uint amount, string memory description) public {
        bytes memory data = abi.encodeWithSignature("withdraw(address,address,uint256)", token, recipient, amount);
        createProposal(ActionType.TRANSFER, currentVaultAddress, amount, data, description);
    }

    function proposeCall(address target, bytes memory data, string memory description) public {
        createProposal(ActionType.CALL, target, 0, data, description);
    }

    function proposeUpgrade(address newImplementation, string memory description) public {
        bytes memory data = abi.encodeWithSignature("upgradeTo(address)", newImplementation);
        createProposal(ActionType.UPGRADE, currentVaultAddress, 0, data, description);
    }

    function createProposal(ActionType _type, address target, uint value, bytes memory data, string memory description) internal {
        proposals.push(Proposal({
            proposalId: proposals.length,
            actionType: _type,
            commitPhase: CommitPhase.COMMITTED,
            description: description,
            target: target,
            value: value,
            data: data,
            voteCount: 0,
            executionTime: block.timestamp + TIMELOCKDELAY,
            executed: false
        }));
        emit ProposalStatusChanged(proposals.length - 1, CommitPhase.COMMITTED);
    }

    function vote(uint proposalId) public {
        require(proposalId < proposals.length, "Invalid proposal ID");
        require(!Voted[proposalId][msg.sender], "Already voted");
        require(proposals[proposalId].commitPhase == CommitPhase.COMMITTED, "Only proposal's in commit phase can be voted on");
        Voted[proposalId][msg.sender] = true;
        proposals[proposalId].voteCount++;
        if(proposals[proposalId].voteCount >= MIN_QUORUM){
            proposals[proposalId].commitPhase = CommitPhase.ACCEPTED;
            emit ProposalStatusChanged(proposalId, CommitPhase.ACCEPTED);
        }
    }

    function executeProposal(uint proposalId) public {
        Proposal storage p = proposals[proposalId];
        require(proposalId < proposals.length, "Invalid proposal ID");
        require(p.executionTime != 0, "Not committed");
        require(block.timestamp >= p.executionTime, "Timelock active");
        require(!p.executed, "Already executed");
        require(p.commitPhase == CommitPhase.ACCEPTED, "Only accepted proposals can be executed");
        require(p.voteCount > MIN_QUORUM, "Not enough votes");

        p.executed = true;

        (bool success, ) = p.target.call{value: p.value}(p.data);
        require(success, "Transaction failed");

        emit ProposalExecuted(proposalId, block.timestamp);
    }

    function denialProposal(uint proposalId) public onlyAdmins(msg.sender) {
        require(proposalId < proposals.length, "Invalid proposal ID");
        require(!proposals[proposalId].executed, "Cannot deny executed proposal");

        proposals[proposalId].commitPhase = CommitPhase.DENIED;
        emit ProposalStatusChanged(proposalId, CommitPhase.DENIED);
    }
}