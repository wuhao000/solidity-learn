// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

contract ReverseString {


    function reverse(string calldata str) external pure returns(string memory res) {
        bytes memory org = bytes(str);
        uint len = org.length;
        bytes memory n = new bytes(len);
        for (uint i = 0; i < len; i++) {
            n[i] = org[len - 1 - i];
        }
        return string(n);
    }

}