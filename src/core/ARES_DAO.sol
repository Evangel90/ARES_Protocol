// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../modules/ARES_Vault.sol';
import '../modules/ARES_Auth.sol';
import '../modules/ARES_Exec_Eng.sol';
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract ARES_DAO is ARES_Vault, ARES_Auth, ARES_Exec_Eng {
    enum ActionType { TRANSFER, CALL, UPGRADE }
    enum CommitPhase { COMMITTED, DENIED, ACCEPTED }

    uint public MIN_QUORUM = 3;
    uint256 public TIMELOCKDELAY = 2 days;
    bytes32 public merkleRoot;

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
            executionTime: 0,
            executed: false
        }));
        emit ProposalStatusChanged(proposals.length - 1, CommitPhase.COMMITTED);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyAdmins(msg.sender) {
        merkleRoot = _merkleRoot;
    }

    // function vote(uint proposalId, bytes32[] calldata proof) public {
    //     bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
    //     require(MerkleProof.verify(proof, merkleRoot, leaf), "Not a valid voter");
    //     _castVote(msg.sender, proposalId);
    // }

    function voteBySig(address signer, uint proposalId, uint deadline, uint8 v, bytes32 r, bytes32 s, bytes32[] calldata proof) public {
        bytes32 leaf = keccak256(abi.encodePacked(signer));
        require(MerkleProof.verify(proof, merkleRoot, leaf), "Not a valid voter");
        verifyVote(signer, proposalId, deadline, v, r, s);
        _castVote(signer, proposalId);
    }

    function _castVote(address voter, uint proposalId) internal {
        require(proposalId < proposals.length, "Invalid proposal ID");
        require(!Voted[proposalId][voter], "Already voted");
        require(proposals[proposalId].commitPhase == CommitPhase.COMMITTED, "Only proposal's in commit phase can be voted on");
        Voted[proposalId][voter] = true;
        proposals[proposalId].voteCount++;
        if(proposals[proposalId].voteCount >= MIN_QUORUM){
            proposals[proposalId].commitPhase = CommitPhase.ACCEPTED;
            emit ProposalStatusChanged(proposalId, CommitPhase.ACCEPTED);
        }
    }

    function queueProposal(uint proposalId) public {
        Proposal storage p = proposals[proposalId];
        require(proposalId < proposals.length, "Invalid proposal ID");
        require(p.commitPhase == CommitPhase.ACCEPTED, "Proposal must be accepted");
        require(p.executionTime == 0, "Proposal already queued");

        uint256 eta = block.timestamp + TIMELOCKDELAY;
        p.executionTime = eta;

        _queue(p.target, p.value, p.data, TIMELOCKDELAY);
    }

    function executeProposal(uint proposalId) public {
        Proposal storage p = proposals[proposalId];
        require(proposalId < proposals.length, "Invalid proposal ID");
        require(p.executionTime != 0, "Proposal not queued");
        require(!p.executed, "Already executed");

        execute(p.target, p.value, p.data, p.executionTime);
        p.executed = true;

        emit ProposalExecuted(proposalId, block.timestamp);
    }

    function denialProposal(uint proposalId) public onlyAdmins(msg.sender) {
        require(proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage p = proposals[proposalId];
        require(!p.executed, "Cannot deny executed proposal");

        p.commitPhase = CommitPhase.DENIED;
        
        // If the proposal was already queued, we must cancel it in the Execution Engine
        // to prevent it from being executed via the public execute() function.
        if (p.executionTime != 0) {
            bytes32 txHash = keccak256(abi.encode(p.target, p.value, p.data, p.executionTime));
            _cancel(txHash);
            p.executionTime = 0;
        }
        
        emit ProposalStatusChanged(proposalId, CommitPhase.DENIED);
    }
}