// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

contract Merge {


  function merge(int[] memory a1, int[] memory a2) external pure returns (int[] memory) {
    uint len = a1.length + a2.length;
    int[] memory res = new int[](len);
    uint i = 0;
    uint j = 0;
    for (uint m = 0; m < len; m++) {
      if (i < a1.length && j < a2.length) {
        if (a1[i] <= a2[j]) {
          res[m] = a1[i];
          i++;
        } else if (a2[j] < a1[i]) {
          res[m] = a2[j];
          j++;
        }
      } else if (i < a1.length) {
        for (uint n = i; n < a1.length; n++) {
          res[m] = a1[n];
          m++;
        }
      } else if (j < a2.length) {
        for (uint n = j; n < a2.length; n++) {
          res[m] = a2[n];
          m++;
        }
      }
    }
    return res;
  }


}