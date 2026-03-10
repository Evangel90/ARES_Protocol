// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ARES_Control.sol";
import "./ARES_Token.sol";
import "../interfaces/IERC20.sol";

contract ARES_Vault is ARES_Control {
    ARES_Token public aresToken;
    bool public upgraded = false;
    address public currentVaultAddress;

    constructor(address[] memory initialAdmins) {
        admins = initialAdmins;

        aresToken = new ARES_Token();

        aresToken.mint(address(this), 550000000 * 10**18);
    }

    function deposit(address token, uint amount) external{
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Deposit failed");
    }

    function withdraw(address token, address recipient, uint256 amount) public onlyAdmins(msg.sender) {
        bool success = IERC20(token).transfer(recipient, amount);
        require(success, "Withdrawal failed");
    }

    //reimplement this function to allow for consensus first before upgrading the vault
    function upgradeVault(address newImplementation) public onlyAdmins(msg.sender) {
        require(!upgraded, "Vault has already been upgraded");
        upgraded = true;
        currentVaultAddress = newImplementation;
    }

}