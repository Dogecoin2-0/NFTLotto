// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AdvancedNFTLottery is VRFConsumerBase, Ownable {
    IERC20 public token;
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public lotteryEndTime;
    uint256 public entryFee;
    uint256 public maxTicketsPerWallet;
    mapping(address => uint256) public ticketsBought;
    address[] public participants;
    address public recentWinner;
    uint256 public randomness;
    bool public lotteryOpen = false;
    uint256 public referralReward = 5;  // 5% reward
    mapping(address => address) public referrals;

    // Events
    event LotteryEntered(address indexed participant, uint256 amount);
    event RequestedRandomness(bytes32 requestId);
    event WinnerPicked(address indexed winner);

    constructor(
        address _vrfCoordinator,
        address _linkToken,
        bytes32 _keyHash,
        uint256 _fee
    )
        VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        token = IERC20(0x3780E00D4c60887AF38345cCd44f7617dBFB10A0); // Doge2 Token Address
        keyHash = _keyHash;
        fee = _fee;
        entryFee = 100 * 10**18;  // 100 tokens, assuming 18 decimals
        maxTicketsPerWallet = 10;
    }

    function startLottery(uint256 _duration, uint256 _entryFee, uint256 _maxTickets) public onlyOwner {
        require(!lotteryOpen, "Lottery is already open");
        lotteryOpen = true;
        lotteryEndTime = block.timestamp + _duration;
        entryFee = _entryFee;
        maxTicketsPerWallet = _maxTickets;
        participants = new address[];
    }

    function enterLottery(uint256 _ticketCount, address _referrer) public {
        require(lotteryOpen, "Lottery is not open");
        require(block.timestamp < lotteryEndTime, "Lottery has ended");
        require(_ticketCount <= maxTicketsPerWallet, "Exceeds maximum tickets per wallet");
        require(ticketsBought[msg.sender] + _ticketCount <= maxTicketsPerWallet, "Ticket limit exceeded");
        uint256 totalCost = entryFee * _ticketCount;
        require(token.transferFrom(msg.sender, address(this), totalCost), "Payment failed");

        for (uint i = 0; i < _ticketCount; i++) {
            participants.push(msg.sender);
        }
        ticketsBought[msg.sender] += _ticketCount;
        emit LotteryEntered(msg.sender, _ticketCount);

        if (_referrer != address(0) && _referrer != msg.sender) {
            uint256 referralBonus = totalCost * referralReward / 100;
            require(token.transfer(_referrer, referralBonus), "Referral bonus failed");
            referrals[msg.sender] = _referrer;
        }
    }

    function endLottery() public onlyOwner {
        require(lotteryOpen, "Lottery is not open");
        require(block.timestamp >= lotteryEndTime, "Lottery is still ongoing");
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");

        lotteryOpen = false;
        bytes32 requestId = requestRandomness(keyHash, fee);
        emit RequestedRandomness(requestId);
    }

    function fulfillRandomness(bytes32 /* requestId */, uint256 _randomness) internal override {
        require(!lotteryOpen, "Lottery is not ended");
        require(_randomness > 0, "Random-not-found");

        randomness = _randomness;
        uint256 winnerIndex = randomness % participants.length;
        recentWinner = participants[winnerIndex];
        uint256 prizePool = token.balanceOf(address(this));
        require(token.transfer(recentWinner, prizePool), "Prize transfer failed");
        emit WinnerPicked(recentWinner);
    }

    function setReferralReward(uint256 _newReward) public onlyOwner {
        referralReward = _newReward;
    }

    function withdrawLink() external onlyOwner {
        require(LINK.transfer(msg.sender, LINK.balanceOf(address(this))), "Failed to transfer LINK");
    }

    function withdrawTokens(address _tokenAddr) external onlyOwner {
        IERC20 _token = IERC20(_tokenAddr);
        require(_token.transfer(msg.sender, _token.balanceOf(address(this))), "Failed to transfer tokens");
    }
}
