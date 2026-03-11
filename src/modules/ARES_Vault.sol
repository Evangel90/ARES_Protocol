// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ARES_Control.sol";
import "./ARES_Token.sol";
import "../interfaces/IERC20.sol";
import "../libraries/AccessControlLib.sol";

contract ARES_Vault is ARES_Control {
    using AccessControlLib for AccessControlLib.Roles;
    ARES_Token public aresToken;
    bool public upgraded = false;
    address public currentVaultAddress;
    uint256 public constant DAILY_LIMIT = 50000 * 10**18;
    uint256 public dailySpent;
    uint256 public lastResetTime;
    address public dao;

    constructor(address[] memory initialAdmins) {
        for(uint i = 0; i < initialAdmins.length; i++) {
            roles.addAdmin(initialAdmins[i]);
        }

        aresToken = new ARES_Token();

        aresToken.mint(address(this), 550000000 * 10**18);
    }

    function setDAO(address _dao) external onlyAdmins(msg.sender) {
        dao = _dao;
    }

    function deposit(address token, uint amount) external{
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Deposit failed");
    }

    // function withdraw(address token, address recipient, uint256 amount) public onlyAdmins(msg.sender) {
    //     bool success = IERC20(token).transfer(recipient, amount);
    //     require(success, "Withdrawal failed");
    // }

    //reimplement this function to allow for consensus first before upgrading the vault
    function upgradeVault(address newImplementation) public onlyAdmins(msg.sender) {
        require(!upgraded, "Vault has already been upgraded");
        upgraded = true;
        currentVaultAddress = newImplementation;
    }

    function protectedWithdraw(address token, address recipient, uint256 amount) public onlyDAO {

        if (block.timestamp >= lastResetTime + 1 days) {
            dailySpent = 0;
            lastResetTime = block.timestamp;
        }
        
        require(dailySpent + amount <= DAILY_LIMIT, "Daily limit exceeded");
        dailySpent += amount;
        
        require(IERC20(token).transfer(recipient, amount), "Transfer failed");
    }

    function distribute(address recipient, uint256 amount) external {
        require(msg.sender == dao, "Only DAO");
        require(aresToken.transfer(recipient, amount), "Transfer failed");
    }
}