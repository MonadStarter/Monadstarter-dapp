// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/Campaign.sol";
import "./mocks/MockERC20.sol";

contract CampaignTest is Test {
    Campaign public campaign;
    MockERC20 public token;
    MockERC20 public payToken;
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

        // Deploy mock tokens
        token = new MockERC20("Campaign Token", "CTK");
        payToken = new MockERC20("Pay Token", "PTK");

        // Set up campaign parameters
        address _token = address(token);
        address _campaignOwner = owner;
        uint256[4] memory _stats = [100 ether, 1000 ether, 10000 ether, 500]; // softCap, hardCap, tokenSalesQty, feePcnt
        uint256[4] memory _dates = [
            block.timestamp,
            block.timestamp + 7 days,
            block.timestamp + 2 days,
            block.timestamp + 5 days
        ];
        bool _burnUnSold = false;
        uint256 _tokenLockTime = 30 days;
        uint256[5] memory _tierWeights = [10, 20, 30, 40, 50];
        uint256[5] memory _tierMinTokens = [100, 200, 300, 400, 500];
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

    function testInitialState() public {
        assertEq(campaign.campaignOwner(), owner);
        assertEq(campaign.token(), address(token));
        assertEq(campaign.softCap(), 100 ether);
        assertEq(campaign.hardCap(), 1000 ether);
        assertEq(campaign.tokenSalesQty(), 10000 ether);
        assertEq(campaign.feePcnt(), 500);
        assertEq(campaign.payToken(), address(payToken));
        assertEq(campaign.staker(), staker);
        assertEq(campaign.feeAddress(), feeAddress);
    }

    function testTierSetup() public {
        for (uint256 i = 1; i <= 5; i++) {
            (
                uint256 weight,
                uint256 minTokens,
                uint256 noOfParticipants
            ) = campaign.indexToTier(i);
            assertEq(weight, i * 10);
            assertEq(minTokens, i * 100);
            assertEq(noOfParticipants, 0);
        }
    }

    // Add more test functions here
}
