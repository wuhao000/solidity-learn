// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

contract Voting {
    mapping(address => uint8) private tickects;
    mapping(address => bool) private voted;
    mapping(address => bool) private voterMapping;
    address[] addresses;

    constructor(address[] memory voters) {
        addresses = voters;
        for (uint i = 0; i < voters.length; i++) {
            voterMapping[voters[i]] = true;
        }
    }

    function vote(address target) external {
        require(msg.sender != target, "You cannot vote for yourself!");
        require(voterMapping[msg.sender], "You are not valid voter!");
        require(!voted[msg.sender], "You have already voted!"); 
        tickects[target] += 1;
        voted[msg.sender] = true;
    }

    function getVotes(address addr) public view returns(uint8) {
        return tickects[addr];
    }

    function resetVotes() external {
        for (uint i = 0; i < addresses.length; i++) {
            tickects[addresses[i]] = 0;
            voted[addresses[i]] = false;
        }
    }
}