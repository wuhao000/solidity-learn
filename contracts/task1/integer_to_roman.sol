// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

contract IntegerToRoman {

    string[][] private units;

    constructor() {
        units.push(["I", "V", "X"]);
        units.push(["X", "L", "C"]);
        units.push(["C", "D", "M"]);
        units.push(["M", "", ""]);
    }

    function convert(uint input) external view returns (string memory) {
        string memory res = "";
        uint i = 0;
        while (input > 0) {
            res = string(abi.encodePacked(convertDigit(input % 10, units[i][0], units[i][1], units[i][2]), res));    
            i++;
            input /= 10;
        }
        return res;
    }

    function convertDigit(
        uint digit, 
        string memory unit,
        string memory unit5,
        string memory unit10
    ) internal pure returns (string memory) {
        if (digit == 9) {
            return string(abi.encodePacked(unit, unit10));
        } else if (digit >= 5) {
            string memory s = unit5;
            for (uint i = 0; i < digit - 5; i++) {
                s = string(abi.encodePacked(s, unit));
            }
            return s;
        } else if (digit == 4) {
            return string(abi.encodePacked(unit, unit5));
        } else {
            string memory s = "";
            for (uint i = 0; i < digit; i++) {
                s = string(abi.encodePacked(s, unit));
            }
            return s;
        }
    }
}
