// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import './ARES_Vault.sol';
import '../modules/ARES_Auth.sol';
import '../modules/ARES_Exec_Eng.sol';
import '../modules/ARES_Distributor.sol';
import '../modules/ARES_Control.sol';
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "../interfaces/IERC20.sol";
import "../libraries/AccessControlLib.sol";

contract ARES_DAO is ARES_Control, ARES_Auth, ARES_Exec_Eng, ARES_Distributor {
    using AccessControlLib for AccessControlLib.Roles;
    enum ActionType { TRANSFER, CALL, UPGRADE }
    enum CommitPhase { COMMITTED, DENIED, ACCEPTED }

    uint public MIN_QUORUM = 3;
    uint256 public TIMELOCKDELAY = 2 days;
    bytes32 public merkleRoot;
    
    ARES_Vault public vault;
    IERC20 public aresToken;

    // --- Economic Defenses ---
    uint256 public constant PROPOSAL_STAKE = 1000 * 10**18;
    mapping(uint256 => address) public proposalProposer;

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

    constructor(address[] memory _admins, address _vault) {
        for(uint i = 0; i < _admins.length; i++) {
            roles.addAdmin(_admins[i]);
        }
        vault = ARES_Vault(_vault);
        aresToken = vault.aresToken();
    }

    function proposeTransfer(address token, address recipient, uint amount, string memory description) public {
        // Fix: Pass the 3 arguments required by ARES_Vault.protectedWithdraw (token, recipient, amount)
        bytes memory data = abi.encodeWithSignature("protectedWithdraw(address,address,uint256)", token, recipient, amount);
        createProposal(ActionType.TRANSFER, address(vault), 0, data, description);
    }

    function proposeCall(address target, bytes memory data, string memory description) public {
        createProposal(ActionType.CALL, target, 0, data, description);
    }

    function proposeUpgrade(address newImplementation, string memory description) public {
        bytes memory data = abi.encodeWithSignature("upgradeTo(address)", newImplementation);
        createProposal(ActionType.UPGRADE, address(vault), 0, data, description);
    }

    function createProposal(ActionType _type, address target, uint value, bytes memory data, string memory description) internal {
        require(aresToken.transferFrom(msg.sender, address(this), PROPOSAL_STAKE), "Stake failed");
        proposalProposer[proposals.length] = msg.sender;

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
        require(aresToken.transfer(proposalProposer[proposalId], PROPOSAL_STAKE), "Stake refund failed");

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
        
        require(aresToken.transfer(proposalProposer[proposalId], PROPOSAL_STAKE), "Stake refund failed");
        emit ProposalStatusChanged(proposalId, CommitPhase.DENIED);
    }

    function setDistributionRoot(bytes32 _newRoot) external onlyAdmins(msg.sender) {
        _updateDistributionRoot(_newRoot);
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata proof) external {
        _processClaim(index, account, amount, proof);
        vault.distribute(account, amount);
    }
    
}