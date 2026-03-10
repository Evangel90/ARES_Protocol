// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract ARES_Vault {
    
    struct Contributor{
        address contributorAddress;
        uint amountContributed;
    }

    receive() external payable {
        require(msg.value > 0, "Must send some ether");
    }
}