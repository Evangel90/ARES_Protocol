// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract ARES_Auth {
    error InvalidSignature();
    error SignatureExpired();
    error InvalidSValue();

    struct TreasuryAction {
        address target;
        uint256 value;
        bytes data;
        uint256 nonce;
        uint256 deadline;
    }

    struct Vote {
        uint256 proposalId;
        uint256 nonce;
        uint256 deadline;
    }

    // EIP-712 TypeHashes
    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant ACTION_TYPEHASH = keccak256("TreasuryAction(address target,uint256 value,bytes data,uint256 nonce,uint256 deadline)");
    bytes32 private constant VOTE_TYPEHASH = keccak256("Vote(uint256 proposalId,uint256 nonce,uint256 deadline)");

    bytes32 public immutable DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            DOMAIN_TYPEHASH,
            keccak256(bytes("ARES Protocol")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
    }

    function verifyTreasuryAction(
        address signer,
        address target,
        uint256 value,
        bytes memory data,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 structHash = keccak256(abi.encode(
            ACTION_TYPEHASH,
            target,
            value,
            keccak256(data),
            nonces[signer],
            deadline
        ));
        _verify(signer, structHash, deadline, v, r, s);
    }

    function verifyVote(
        address signer,
        uint256 proposalId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 structHash = keccak256(abi.encode(
            VOTE_TYPEHASH,
            proposalId,
            nonces[signer],
            deadline
        ));
        _verify(signer, structHash, deadline, v, r, s);
    }

    function _verify(address signer, bytes32 structHash, uint256 deadline, uint8 v, bytes32 r, bytes32 s) internal {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) revert InvalidSValue();

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            structHash
        ));

        address recoveredAddress = ecrecover(digest, v, r, s);
        if (recoveredAddress == address(0) || recoveredAddress != signer) revert InvalidSignature();

        unchecked {
            nonces[signer]++;
        }
    }
}
