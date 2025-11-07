// SPDX-License-Identifier: MIT
pragma solidity ^0.8;


contract Find {

  function find(int[] memory arr, int target) public pure returns (int) {
    uint cursor = arr.length / 2;
    uint length = arr.length / 2;
    for (; length > 0;) {
      if (arr[cursor] == target) {
        return int(cursor);
      } else {
        if (arr[cursor] > target) {
          cursor -= length / 2;
        } else {
          cursor += length / 2;
        }
        length /= 2;
      }
    }
    return -1;
  }

  function find() public pure returns (int) {
    int[] memory arr = new int[](3);
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    return find(arr, 4);
  }

  function find1() public pure returns (int) {
    int[] memory arr = new int[](4);
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    arr[3] = 4;
    return find(arr, 4);
  }

  function find2() public pure returns (int) {
    int[] memory arr = new int[](5);
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    arr[3] = 4;
    arr[4] = 5;
    return find(arr, 4);
  }

  function find3() public pure returns (int) {
    int[] memory arr = new int[](6);
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    arr[3] = 4;
    arr[4] = 5;
    arr[5] = 5;
    return find(arr, 4);
  }


  function find4() public pure returns (int) {
    int[] memory arr = new int[](7);
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    arr[3] = 4;
    arr[4] = 5;
    arr[5] = 5;
    arr[6] = 6;
    return find(arr, 4);
  }

  function find5() public pure returns (int) {
    int[] memory arr = new int[](8);
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    arr[3] = 4;
    arr[4] = 5;
    arr[5] = 5;
    arr[6] = 6;
    arr[7] = 7;
    return find(arr, 4);
  }

  function find6() public pure returns (int) {
    int[] memory arr = new int[](9);
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    arr[3] = 4;
    arr[4] = 5;
    arr[5] = 5;
    arr[6] = 6;
    arr[7] = 7;
    arr[8] = 8;
    return find(arr, 4);
  }

}