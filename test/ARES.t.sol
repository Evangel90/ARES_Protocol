// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/core/ARES_DAO.sol";
import "../src/core/ARES_Vault.sol";
import "../src/modules/ARES_Token.sol";
import "../src/modules/ARES_Auth.sol";
import "../src/libraries/AccessControlLib.sol";
import "../src/libraries/ExecutionLib.sol";

contract ARESTest is Test {
    ARES_DAO dao;
    ARES_Vault vault;
    ARES_Token token;

    address admin = makeAddr("admin");
    address proposer = makeAddr("proposer");
    address recipient = makeAddr("recipient");

    // Voters
    address[] voters;
    bytes32[] leaves;
    bytes32 merkleRoot;

    // Voter 1 keys for EIP-712
    uint256 voter1Pk = 0xA11CE;
    address voter1 = vm.addr(voter1Pk);

    // Voter 2 & 3 keys
    uint256 voter2Pk = 0xB22DF;
    address voter2 = vm.addr(voter2Pk);
    uint256 voter3Pk = 0xC33E0;
    address voter3 = vm.addr(voter3Pk);

    function setUp() public {
        // 1. Setup Admins
        address[] memory admins = new address[](1);
        admins[0] = admin;

        // 2. Deploy Vault
        vm.prank(admin);
        vault = new ARES_Vault(admins);
        token = vault.aresToken();

        // 3. Deploy DAO
        vm.prank(admin);
        dao = new ARES_DAO(admins, address(vault));

        // 4. Link DAO & Permissions
        vm.startPrank(admin);
        vault.setDAO(address(dao));
        // Workaround: ARES_Vault.protectedWithdraw uses onlyDAO modifier which checks msg.sender == address(this) || isAdmin.
        // Since DAO is a separate contract, it fails address(this) check. We must add DAO as admin for now.
        vault.addAdmin(address(dao));
        vm.stopPrank();

        // 5. Setup Voters & Merkle Tree
        voters.push(voter1);
        voters.push(voter2);
        voters.push(voter3);
        voters.push(makeAddr("voter4"));

        // Create leaves: keccak256(abi.encodePacked(address))
        for (uint i = 0; i < voters.length; i++) {
            leaves.push(keccak256(abi.encodePacked(voters[i])));
        }

        // Generate Root (Simple fixed-pair construction for testing)
        // Note: Real world use OZ MerkleProof compatible generation
        merkleRoot = _getMerkleRoot(leaves);

        vm.prank(admin);
        dao.setMerkleRoot(merkleRoot);

        // 6. Fund Proposer for Staking
        deal(address(token), proposer, 10000 * 10**18);
    }

    // --- Helper Functions for Merkle Tree ---
    // Simple tree for 4 leaves: Root = H(H(L0, L1), H(L2, L3))
    function _getMerkleRoot(bytes32[] memory _leaves) internal pure returns (bytes32) {
        bytes32 h01 = _hashPair(_leaves[0], _leaves[1]);
        bytes32 h23 = _hashPair(_leaves[2], _leaves[3]);
        return _hashPair(h01, h23);
    }

    function _getProof(bytes32[] memory _leaves, uint256 index) internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        if (index == 0) {
            proof[0] = _leaves[1];
            proof[1] = _hashPair(_leaves[2], _leaves[3]);
        } else if (index == 1) {
            proof[0] = _leaves[0];
            proof[1] = _hashPair(_leaves[2], _leaves[3]);
        } else if (index == 2) {
            proof[0] = _leaves[3];
            proof[1] = _hashPair(_leaves[0], _leaves[1]);
        } else if (index == 3) {
            proof[0] = _leaves[2];
            proof[1] = _hashPair(_leaves[0], _leaves[1]);
        }
        return proof;
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _passProposal(uint256 proposalId) internal {
        bytes32 domainSeparator = dao.DOMAIN_SEPARATOR();
        bytes32 voteTypeHash = keccak256("Vote(uint256 proposalId,uint256 nonce,uint256 deadline)");
        uint256 deadline = block.timestamp + 10 hours;

        // Voter 1
        {
            uint256 nonce = dao.nonces(voter1);
            bytes32 structHash = keccak256(abi.encode(voteTypeHash, proposalId, nonce, deadline));
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1Pk, digest);
            dao.voteBySig(voter1, proposalId, deadline, v, r, s, _getProof(leaves, 0));
        }
        // Voter 2 & 3 (Just using Voter 1 logic repeated for simplicity of helper if keys were same, but here they differ)
        {
            uint256 nonce = dao.nonces(voter2);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter2Pk, keccak256(abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(voteTypeHash, proposalId, nonce, deadline)))));
            dao.voteBySig(voter2, proposalId, deadline, v, r, s, _getProof(leaves, 1));
        }
        {
            uint256 nonce = dao.nonces(voter3);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter3Pk, keccak256(abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(voteTypeHash, proposalId, nonce, deadline)))));
            dao.voteBySig(voter3, proposalId, deadline, v, r, s, _getProof(leaves, 2));
        }
    }

    // --- Tests ---

    function test_ProposalExecutionFlow() public {
        uint256 transferAmount = 100 * 10**18;
        uint256 proposalStake = dao.PROPOSAL_STAKE();

        bytes32 domainSeparator = dao.DOMAIN_SEPARATOR();
        bytes32 voteTypeHash = keccak256("Vote(uint256 proposalId,uint256 nonce,uint256 deadline)");
        uint256 deadline = block.timestamp + 1 hours;

        // 1. Create Proposal
        vm.startPrank(proposer);
        token.approve(address(dao), proposalStake);
        dao.proposeTransfer(address(token), recipient, transferAmount, "Test Transfer");
        vm.stopPrank();

        // Verify stake taken
        assertEq(token.balanceOf(address(dao)), proposalStake);

        // 2. Vote (Need 3 votes for MIN_QUORUM)
        // Voter 1
        {
            uint256 nonce = dao.nonces(voter1);
            bytes32 structHash = keccak256(abi.encode(voteTypeHash, 0, nonce, deadline));
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1Pk, digest);
            dao.voteBySig(voter1, 0, deadline, v, r, s, _getProof(leaves, 0));
        }
        // Voter 2
        {
            uint256 nonce = dao.nonces(voter2);
            bytes32 structHash = keccak256(abi.encode(voteTypeHash, 0, nonce, deadline));
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter2Pk, digest);
            dao.voteBySig(voter2, 0, deadline, v, r, s, _getProof(leaves, 1));
        }
        // Voter 3
        {
            uint256 nonce = dao.nonces(voter3);
            bytes32 structHash = keccak256(abi.encode(voteTypeHash, 0, nonce, deadline));
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter3Pk, digest);
            dao.voteBySig(voter3, 0, deadline, v, r, s, _getProof(leaves, 2));
        }

        // 3. Queue Proposal
        dao.queueProposal(0);

        // 4. Execute before timelock (Should Fail)
        vm.expectRevert(); 
        dao.executeProposal(0);

        // 5. Warp Time
        vm.warp(block.timestamp + dao.TIMELOCKDELAY() + 1);

        // 6. Execute Success
        uint256 preBalance = token.balanceOf(recipient);
        dao.executeProposal(0);
        uint256 postBalance = token.balanceOf(recipient);

        // Checks
        assertEq(postBalance - preBalance, transferAmount, "Recipient did not receive tokens");
        assertEq(token.balanceOf(proposer), 10000 * 10**18, "Stake not refunded");
        
        // Verify Daily Limit state in Vault
        assertEq(vault.dailySpent(), transferAmount);
    }

    function test_VoteBySig() public {
        uint256 proposalId = 0;
        
        // Create Proposal
        vm.startPrank(proposer);
        token.approve(address(dao), dao.PROPOSAL_STAKE());
        dao.proposeTransfer(address(token), recipient, 50 ether, "Gasless Vote Test");
        vm.stopPrank();

        // Prepare EIP-712 Signature for Voter 1
        uint256 nonce = dao.nonces(voter1); // Should be 0
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 domainSeparator = dao.DOMAIN_SEPARATOR();
        bytes32 voteTypeHash = keccak256("Vote(uint256 proposalId,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(voteTypeHash, proposalId, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1Pk, digest);

        // Submit Vote via a Relayer (random address)
        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        dao.voteBySig(voter1, proposalId, deadline, v, r, s, _getProof(leaves, 0));

        // Check Vote Count
        (,,,,,,,uint256 voteCount,,) = dao.proposals(0);
        assertEq(voteCount, 1);
        assertEq(dao.nonces(voter1), 1);
    }

    function test_DenyProposal() public {
        uint256 proposalStake = dao.PROPOSAL_STAKE();

        // 1. Create Proposal
        vm.startPrank(proposer);
        token.approve(address(dao), proposalStake);
        dao.proposeCall(address(0xdead), bytes(""), "Proposal to be denied");
        vm.stopPrank();

        // 2. Vote to acceptance
        _passProposal(0);

        // 3. Queue it
        dao.queueProposal(0);

        // 4. Admin denies it
        vm.prank(admin);
        dao.denialProposal(0);

        // Check stake refunded
        assertEq(token.balanceOf(proposer), 10000 * 10**18, "Stake not refunded on denial");

        // 5. Try to execute (should fail as it was cancelled)
        vm.warp(block.timestamp + dao.TIMELOCKDELAY() + 1);
        vm.expectRevert();
        dao.executeProposal(0);
    }

    function test_ClaimDistribution() public {
        // 1. Setup distribution
        address claimer = makeAddr("claimer");
        uint256 claimAmount = 500 ether;
        bytes32[] memory claimLeaves = new bytes32[](4);
        claimLeaves[0] = keccak256(abi.encodePacked(uint256(0), claimer, claimAmount));
        claimLeaves[1] = bytes32(0);
        claimLeaves[2] = bytes32(0);
        claimLeaves[3] = bytes32(0);
        bytes32 claimRoot = _getMerkleRoot(claimLeaves);
        vm.prank(admin);
        dao.setDistributionRoot(claimRoot);

        // 2. Claim
        bytes32[] memory proof = _getProof(claimLeaves, 0);
        dao.claim(0, claimer, claimAmount, proof);
        assertEq(token.balanceOf(claimer), claimAmount);

        // 3. Double claim should fail
        vm.expectRevert(ARES_Distributor.AlreadyClaimed.selector);
        dao.claim(0, claimer, claimAmount, proof);
    }

    function test_AddRemoveAdmin() public {
        address newAdmin = makeAddr("newAdmin");
        
        vm.prank(admin);
        dao.addAdmin(newAdmin);

        // New admin should be able to set merkle root
        vm.prank(newAdmin);
        dao.setMerkleRoot(bytes32(uint256(1)));
        
        // Remove admin
        vm.prank(admin);
        dao.removeAdmin(newAdmin);

        // Old admin should fail
        vm.prank(newAdmin);
        vm.expectRevert(AccessControlLib.OnlyAdmins.selector);
        dao.setMerkleRoot(bytes32(uint256(2)));
    }

    function test_VaultDeposit() public {
        uint256 amount = 100 ether;
        deal(address(token), proposer, amount);
        
        vm.startPrank(proposer);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
        vm.stopPrank();

        // Initial mint (550M) + deposit
        assertEq(token.balanceOf(address(vault)), 550000000 * 10**18 + amount);
    }

    function test_UpgradeVault() public {
        address newImpl = makeAddr("newImpl");
        
        vm.prank(admin);
        vault.upgradeVault(newImpl);
        
        assertEq(vault.currentVaultAddress(), newImpl);
        assertTrue(vault.upgraded());

        // Try to upgrade again
        vm.prank(admin);
        vm.expectRevert("Vault has already been upgraded");
        vault.upgradeVault(makeAddr("anotherImpl"));
    }

    function test_ExecutionExpired() public {
        vm.startPrank(proposer);
        token.approve(address(dao), dao.PROPOSAL_STAKE());
        dao.proposeCall(address(0), "", "Expire Test");
        vm.stopPrank();

        _passProposal(0);
        dao.queueProposal(0);

        // Warp past Grace Period
        uint256 eta = block.timestamp + dao.TIMELOCKDELAY();
        vm.warp(eta + ExecutionLib.GRACE_PERIOD + 1);

        vm.expectRevert(abi.encodeWithSelector(ExecutionLib.ExecutionExpired.selector, eta, block.timestamp));
        dao.executeProposal(0);
    }

    function test_VerifyTreasuryAction() public {
        bytes32 domainSeparator = dao.DOMAIN_SEPARATOR();
        bytes32 actionTypeHash = keccak256("TreasuryAction(address target,uint256 value,bytes data,uint256 nonce,uint256 deadline)");
        
        address target = address(token);
        uint256 value = 0;
        bytes memory data = "";
        uint256 nonce = dao.nonces(voter1);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(abi.encode(
            actionTypeHash,
            target,
            value,
            keccak256(data),
            nonce,
            deadline
        ));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1Pk, digest);

        // Call Verify
        dao.verifyTreasuryAction(voter1, target, value, data, deadline, v, r, s);
        
        // Nonce should increment
        assertEq(dao.nonces(voter1), nonce + 1);
    }

    function test_SignatureExpired() public {
        uint256 proposalId = 0;
        bytes32 domainSeparator = dao.DOMAIN_SEPARATOR();
        bytes32 voteTypeHash = keccak256("Vote(uint256 proposalId,uint256 nonce,uint256 deadline)");
        
        uint256 deadline = block.timestamp - 1; // Expired
        uint256 nonce = dao.nonces(voter1);

        bytes32 structHash = keccak256(abi.encode(voteTypeHash, proposalId, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1Pk, digest);

        // Expect revert
        vm.expectRevert(ARES_Auth.SignatureExpired.selector);
        dao.voteBySig(voter1, proposalId, deadline, v, r, s, _getProof(leaves, 0));
    }

    function test_Vault_ProtectedWithdraw_Auth() public {
        // Vault has admins[0] = admin, and we added dao as admin in setup.
        
        // 1. Try calling from random address (Should Revert)
        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert(AccessControlLib.Unauthorized.selector);
        vault.protectedWithdraw(address(token), recipient, 100);

        // 2. Try calling from Admin (Should Succeed)
        vm.prank(admin);
        vault.protectedWithdraw(address(token), recipient, 100); 
    }
}