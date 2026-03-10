// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract ARES_DAO {
    struct Proposal {
        uint proposalId;
        string description;
        uint requestedAmount;
        address targetAddress;
        uint voteCount;
    }

    mapping (uint => Proposal) public proposalsMap;
    Proposal[] public proposals;

    function createProposal(string memory _description, uint _requestedAmount, address _targetAddress) public {
        proposals.push(Proposal(proposals.length, _description, _requestedAmount, _targetAddress, 0));
        proposalsMap[proposals.length - 1] = Proposal(proposals.length - 1, _description, _requestedAmount, _targetAddress, 0);
    }

    function vote(uint _proposalId) public {
        require(_proposalId < proposals.length, "Invalid proposal ID");
        proposals[_proposalId].voteCount++;
    }
}