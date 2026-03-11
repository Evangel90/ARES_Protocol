// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library BitmapLib {
    struct Map {
        mapping(uint256 => uint256) _slots;
    }

    function isClaimed(Map storage map, uint256 index) internal view returns (bool) {
        uint256 bucket = index / 256;
        uint256 mask = uint256(1) << (index % 256);
        return (map._slots[bucket] & mask) == mask;
    }

    function setClaimed(Map storage map, uint256 index) internal {
        uint256 bucket = index / 256;
        uint256 mask = uint256(1) << (index % 256);
        map._slots[bucket] |= mask;
    }
}