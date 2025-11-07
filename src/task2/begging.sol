pragma solidity ^0.8;

contract BeggingContract {
    uint256 public constant DAY_SECONDS = 86400;
    uint256 public constant HOUR_SECONDS = 3600;
    uint256 public constant MINUTE_SECONDS = 60;

    uint256 public startSecond;
    uint256 public endSecond;

    mapping(address => uint256) private donates;

    event Donate(address addr, uint256 amount);

    address[3] public rank;

    address private _owner;

    constructor() {
        _owner = msg.sender;
    }

    modifier isOnlyOwner() {
        require(msg.sender == _owner, "Only owner can do this");
        _;
    }

    function _canDonate() private view returns (bool) {
        // 起止时间相同则表示不限制
        if (startSecond == endSecond) {
            return true;
        } else {
            uint256 daySeconds = block.timestamp % DAY_SECONDS;
            if (startSecond < endSecond) {
                return daySeconds >= startSecond && daySeconds <= endSecond;
            } else {
                return daySeconds >= startSecond || daySeconds <= endSecond;
            }
        }
    }

    /**
     * 捐款
     */
    function donate() external payable {
        require(msg.sender != _owner, "The owner does not need to donate.");
        require(msg.value > 0, "no zero donation");
        require(_canDonate(), "not within the donation period.");
        donates[msg.sender] += msg.value;
        emit Donate(msg.sender, msg.value);
        _updateRank();
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
     * 设置时间限制
     */
    function setLimit(uint256 _startHour, uint256 _startMinute, uint256 _endHour, uint256 _endMinute)
        external
        isOnlyOwner
    {
        require(
            _startHour >= 0 && _startHour <= 23 && _startMinute >= 0 && _startMinute <= 59 && _endHour >= 0
                && _endHour <= 23 && _endMinute >= 0 && _endMinute <= 59,
            "invalid time value"
        );
        startSecond = _startHour * 3600 + _startMinute * 60;
        endSecond = _endHour * 3600 + _endMinute * 60;
    }

    function _updateRank() private {
        uint256 total = donates[msg.sender];
        if (total > donates[rank[0]]) {
            rank[2] = rank[1];
            rank[1] = rank[0];
            rank[0] = msg.sender;
        } else if (total > donates[rank[1]]) {
            rank[2] = rank[1];
            rank[1] = msg.sender;
        } else if (total > donates[rank[2]]) {
            rank[2] = msg.sender;
        }
    }

    /**
     * 获取指定捐款人的捐款额度
     */
    function getDonation(address donor) public view returns (uint256) {
        return donates[donor];
    }
}
