// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/most_contracts/Campaign.sol";
import "../contracts/most_contracts/BTC.sol";
import "../contracts/most_contracts/MOST.sol";
import "forge-std/console.sol";
contract CampaignTest is Test {
    Campaign public campaign;
    MOST public token;
    BTC public payToken;
    address public owner;
    address public user1;
    address public user2;
    address public staker;
    address public feeAddress;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        staker = address(0x3);
        feeAddress = address(0x4);

        // Deploy tokens
        token = new MOST(10 ** 12);
        payToken = new BTC(10 ** 12);

        // Set up campaign parameters
        address _token = address(token);
        address _campaignOwner = owner;
        uint256[4] memory _stats = [
            uint256(100 ether),
            uint256(1000 ether),
            uint256(10000 ether),
            uint256(500)
        ];
        // softCap, hardCap, tokenSalesQty, feePcnt
        uint256[4] memory _dates = [
            uint256(block.timestamp),
            uint256(block.timestamp + 7 days),
            uint256(block.timestamp + 2 days),
            uint256(block.timestamp + 5 days)
        ];
        bool _burnUnSold = false;
        uint256 _tokenLockTime = 30 days;
        //need to change these
        uint8[5] memory _tierWeights = [10, 20, 30, 40, 50];
        uint16[5] memory _tierMinTokens = [100, 200, 300, 400, 500];
        address _payToken = address(payToken);

        // Deploy campaign contract
        campaign = new Campaign(
            _token,
            _campaignOwner,
            _stats,
            _dates,
            _burnUnSold,
            _tokenLockTime,
            _tierWeights,
            _tierMinTokens,
            _payToken,
            staker,
            feeAddress
        );
    }
}
