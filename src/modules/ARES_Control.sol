// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../libraries/AccessControlLib.sol";

abstract contract ARES_Control {
    using AccessControlLib for AccessControlLib.Roles;
    AccessControlLib.Roles internal roles;

    modifier onlyAdmins(address _address){
        roles.checkAdmin(_address);
        _;
    }

    modifier onlyMembers(address _address) {
        roles.checkMember(_address);
        _;
    }

    modifier onlyDAO() {
        roles.checkDAO(msg.sender, address(this));
        _;
    }

    function addAdmin(address _address) public onlyAdmins(msg.sender) {
        roles.addAdmin(_address);
    }

    function addMembers(address _address) public onlyAdmins(msg.sender) {
        roles.addMember(_address);
    }

    function removeAdmin(address _address) public onlyAdmins(msg.sender) {
        roles.removeAdmin(_address);
    }

    function removeMembers(address _address) public onlyAdmins(msg.sender) {
        roles.removeMember(_address);
    }
}