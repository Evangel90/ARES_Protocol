// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract ARES_Control {

    address[] internal admins;
    mapping(address => bool) internal member;

    error NotMember(address account);

    modifier onlyAdmins(address _address){
        bool isAdmin = false;
        for(uint i = 0; i < admins.length; i++){
            if(admins[i] == _address){
                isAdmin = true;
                break;
            }
        }
        require(isAdmin, "Only admins can call this function");
        _;
    }

    modifier onlyMembers(address _address) {
        if (!member[_address]) revert NotMember(_address);
        _;
    }

    modifier onlyDAO() {
        bool isAuth = msg.sender == address(this);
        if (!isAuth) {
            for (uint i = 0; i < admins.length; i++) {
                if (admins[i] == msg.sender) {
                    isAuth = true;
                    break;
                }
            }
        }
        require(isAuth, "Unauthorized");
        _;
    }

    function addAdmin(address _address) public onlyAdmins(msg.sender) {
        admins.push(_address);
    }

    function addMembers(address _address) public onlyAdmins(msg.sender) {
        member[_address] = true;
    }

    function removeAdmin(address _address) public onlyAdmins(msg.sender) {
        for(uint i = 0; i < admins.length; i++){
            if(admins[i] == _address){
                admins[i] = admins[admins.length - 1];
                admins.pop();
                break;
            }
        }
    }

    function removeMembers(address _address) public onlyAdmins(msg.sender) {
        member[_address] = false;
    }
}