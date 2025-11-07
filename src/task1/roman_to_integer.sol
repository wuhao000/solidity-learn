pragma solidity ^0.8;

contract RomanToInteger {
    mapping(bytes1 => uint) map;

    constructor() {
        map["M"] = 1000;
        map["D"] = 500;
        map["C"] = 100;
        map["L"] = 50;
        map["X"] = 10;
        map["V"] = 5;
        map["I"] = 1;
    }

    function convert(
        string memory input
    ) external view returns (uint) {
        bytes memory b = bytes(input);
        uint last;
        uint res;
        for (uint i = 0; i < b.length; i++) {
            uint v = map[b[i]];
            res += v;
            if (last < v) {
                res -= (last * 2);
            }
            last = v;
        }

        return res;
    }
}
