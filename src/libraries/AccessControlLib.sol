// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library AccessControlLib {
    struct Roles {
        address[] admins;
        mapping(address => bool) members;
    }

    error NotMember(address account);
    error OnlyAdmins();
    error Unauthorized();

    function addAdmin(Roles storage roles, address account) internal {
        roles.admins.push(account);
    }

    function removeAdmin(Roles storage roles, address account) internal {
        address[] storage admins = roles.admins;
        for(uint i = 0; i < admins.length; i++){
            if(admins[i] == account){
                admins[i] = admins[admins.length - 1];
                admins.pop();
                break;
            }
        }
    }

    function addMember(Roles storage roles, address account) internal {
        roles.members[account] = true;
    }

    function removeMember(Roles storage roles, address account) internal {
        roles.members[account] = false;
    }

    function checkAdmin(Roles storage roles, address account) internal view {
        bool isAdmin = false;
        address[] storage admins = roles.admins;
        for(uint i = 0; i < admins.length; i++){
            if(admins[i] == account){
                isAdmin = true;
                break;
            }
        }
        if (!isAdmin) revert OnlyAdmins();
    }

    function checkMember(Roles storage roles, address account) internal view {
        if (!roles.members[account]) revert NotMember(account);
    }
    
    function checkDAO(Roles storage roles, address account, address dao) internal view {
        bool isAuth = account == dao;
        if (!isAuth) {
            address[] storage admins = roles.admins;
            for (uint i = 0; i < admins.length; i++) {
                if (admins[i] == account) {
                    isAuth = true;
                    break;
                }
            }
        }
        if (!isAuth) revert Unauthorized();
    }
}