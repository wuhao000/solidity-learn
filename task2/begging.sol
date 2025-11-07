pragma solidity ^0.8;


contract BeggingContract {

    mapping(address => uint256) private donates;

    address private _owner;

    constructor() {
        _owner = msg.sender;
    }

    modifier isOnlyOwner {
        require(msg.sender == _owner, "Only owner can do this");
        _;
    }

    /**
     * 捐款
     */
    function donate() external payable {
        require(msg.sender != _owner, "The owner does not need to donate.");
        require(msg.value > 0, "no zero donation");
        donates[msg.sender] += msg.value;
    }

    /**
     * 提款（仅限合约所有人）
     */
    function withdraw() public isOnlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "contract balance should not be 0");
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "transfer failed");
    }

    /**
     * 获取指定捐款人的捐款额度
     */
    function getDonation(address donor) public view returns (uint256) {
        return donates[donor];
    }

}