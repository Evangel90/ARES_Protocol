// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "../libraries/BitmapLib.sol";

/// @title ARES Distributor Module
/// @notice Implements a scalable Merkle-based airdrop system with Bitmap state tracking.
abstract contract ARES_Distributor {
    // --- Errors ---
    error AlreadyClaimed();
    error InvalidProof();
    using BitmapLib for BitmapLib.Map;

    // --- Events ---
    event Claimed(uint256 index, address indexed account, uint256 amount);
    event DistributionRootUpdated(bytes32 indexed newRoot);

    // --- State ---
    bytes32 public distributionRoot;
    
    // Packed booleans: each uint256 holds 256 claim bits.
    // This is gas-efficient for tracking thousands of claims.
    BitmapLib.Map private _claimedBitMap;

    /**
     * @notice Checks if a specific index has already been claimed.
     */
    function isClaimed(uint256 index) public view returns (bool) {
        return _claimedBitMap.isClaimed(index);
    }

    /**
     * @notice Marks an index as claimed internally.
     */
    function _setClaimed(uint256 index) private {
        _claimedBitMap.setClaimed(index);
    }

    /**
     * @notice Verifies the proof and marks the claim as processed in storage.
     */
    function _processClaim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata proof
    ) internal {
        if (isClaimed(index)) revert AlreadyClaimed();

        // Leaf structure: keccak256(abi.encodePacked(index, account, amount))
        bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        
        if (!MerkleProof.verify(proof, distributionRoot, leaf)) revert InvalidProof();

        _setClaimed(index);
        emit Claimed(index, account, amount);
    }

    function _updateDistributionRoot(bytes32 _newRoot) internal {
        distributionRoot = _newRoot;
        emit DistributionRootUpdated(_newRoot);
    }
}
