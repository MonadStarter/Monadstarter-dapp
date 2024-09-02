// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/most_contracts/Campaign.sol";
import "../contracts/most_contracts/BTC.sol";
import "../contracts/most_contracts/MOST.sol";
import "../contracts/most_contracts/USDC.sol";
import "forge-std/console.sol";
contract CampaignTest is Test {
    Staker public staker;
    Campaign public campaign;
    MOST public stakeToken;
    BTC public payToken;
    USDC public usdcToken;

    address public owner;
    address public user1;
    address public user2;
    address public feeAddress;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        feeAddress = address(0x4);

        // Deploy tokens
        stakeToken = new MOST(10000 ** 18);
        payToken = new BTC(10000 ** 18);
        usdcToken = new USDC(10000 ** 18);

        staker = new Staker(address(stakeToken));

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        stakeToken.transfer(user1, 1000 ether);
        stakeToken.transfer(user2, 1000 ether);

        usdcToken.transfer(user1, 1000 ether);
        usdcToken.transfer(user2, 1000 ether);

        // Set up campaign parameters
        address _token = address(usdcToken);
        address _campaignOwner = owner;
        uint256[4] memory _stats = [
            uint256(100 ether),
            uint256(1000 ether),
            uint256(1000 ether),
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
        uint256[5] memory _tierWeights = [
            uint256(10),
            uint256(20),
            uint256(30),
            uint256(40),
            uint256(50)
        ];
        uint256[5] memory _tierMinTokens = [
            uint256(100),
            uint256(200),
            uint256(300),
            uint256(400),
            uint256(500)
        ];
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
            address(staker),
            feeAddress
        );
    }

    function _setUpUserWithStake(
        address user,
        uint256 amount,
        uint256 duration
    ) public {
        vm.prank(user);
        stakeToken.approve(address(staker), amount);
        vm.prank(user);
        staker.stake(amount, duration);
    }

    function _fundIn() public {
        uint256 fundAmount = 1000 ether;
        payToken.mint(owner, fundAmount);
        payToken.approve(address(campaign), fundAmount);
        campaign.fundIn();
    }

    function testConstructor() public view {
        // Test campaign owner
        assertEq(campaign.campaignOwner(), owner, "Campaign owner mismatch");

        // Test stats
        assertEq(campaign.softCap(), 100 ether, "Soft cap mismatch");
        assertEq(campaign.hardCap(), 1000 ether, "Hard cap mismatch");
        assertEq(
            campaign.tokenSalesQty(),
            10000 ether,
            "Token sales quantity mismatch"
        );
        assertEq(campaign.feePcnt(), 500, "Fee percentage mismatch");

        // Test dates
        assertEq(campaign.startDate(), block.timestamp, "Start date mismatch");
        assertEq(
            campaign.endDate(),
            block.timestamp + 7 days,
            "End date mismatch"
        );
        assertEq(
            campaign.regEndDate(),
            block.timestamp + 2 days,
            "Registration end date mismatch"
        );
        assertEq(
            campaign.tierSaleEndDate(),
            block.timestamp + 5 days,
            "Tier sale end date mismatch"
        );

        // Test other parameters
        assertEq(campaign.burnUnSold(), false, "Burn unsold flag mismatch");
        assertEq(campaign.tokenLockTime(), 30 days, "Token lock time mismatch");
        assertEq(
            address(campaign.payToken()),
            address(payToken),
            "Paytoken address mismatch"
        );
        assertEq(campaign.staker(), address(staker), "Staker address mismatch");
        assertEq(campaign.feeAddress(), feeAddress, "Fee address mismatch");

        // Test tier weights and min tokens
        for (uint256 i = 1; i <= 5; i++) {
            (uint256 weight, uint256 minTokens, ) = campaign.indexToTier(i);
            assertEq(weight, i * 10, "Tier weight mismatch");
            assertEq(minTokens, i * 100, "Tier min tokens mismatch");
        }
    }

    function testIsInRegistration() public {
        assertTrue(
            campaign.isInRegistration(),
            "Should be in registration period"
        );

        // Move time to just before regEndDate
        vm.warp(block.timestamp + 2 days - 1);
        assertTrue(
            campaign.isInRegistration(),
            "Should still be in registration period"
        );

        // Move time to regEndDate
        vm.warp(block.timestamp + 1);
        assertFalse(
            campaign.isInRegistration(),
            "Should not be in registration period"
        );
    }

    function testIsInTierSale() public {
        assertFalse(
            campaign.isInTierSale(),
            "Should not be in tier sale period"
        );

        // Move time to regEndDate
        vm.warp(block.timestamp + 2 days);
        assertTrue(campaign.isInTierSale(), "Should be in tier sale period");

        // Move time to just before tierSaleEndDate
        vm.warp(block.timestamp + 3 days - 1);
        assertTrue(
            campaign.isInTierSale(),
            "Should still be in tier sale period"
        );

        // Move time to tierSaleEndDate
        vm.warp(block.timestamp + 1);
        assertFalse(
            campaign.isInTierSale(),
            "Should not be in tier sale period"
        );
    }

    function testIsInFCFS() public {
        assertFalse(campaign.isInFCFS(), "Should not be in FCFS period");

        // Move time to tierSaleEndDate
        vm.warp(block.timestamp + 5 days);
        assertTrue(campaign.isInFCFS(), "Should be in FCFS period");

        // Move time to just before endDate
        vm.warp(block.timestamp + 2 days - 1);
        assertTrue(campaign.isInFCFS(), "Should still be in FCFS period");

        // Move time to endDate
        vm.warp(block.timestamp + 1);
        assertFalse(campaign.isInFCFS(), "Should not be in FCFS period");
    }

    function testIsInEnd() public {
        assertFalse(campaign.isInEnd(), "Should not be in end period");

        // Move time to endDate
        vm.warp(block.timestamp + 7 days);
        assertTrue(campaign.isInEnd(), "Should be in end period");
    }

    // function testCurrentPeriod() public {
    //     assertEq(
    //         campaign.currentPeriod(),
    //         0,
    //         "Should be in registration period"
    //     );

    //     vm.warp(block.timestamp + 2 days);
    //     assertEq(campaign.currentPeriod(), 1, "Should be in tier sale period");

    //     vm.warp(block.timestamp + 3 days);
    //     assertEq(campaign.currentPeriod(), 2, "Should be in FCFS period");

    //     vm.warp(block.timestamp + 2 days);
    //     assertEq(campaign.currentPeriod(), 3, "Should be in end period");
    // }

    function testFundIn() public {
        uint256 fundAmount = 1000 ether;

        // Mint tokens to this contract
        payToken.mint(address(this), fundAmount);

        // Approve the campaign to spend tokens
        payToken.approve(address(campaign), fundAmount);

        // Fund the campaign
        campaign.fundIn();

        assertTrue(campaign.tokenFunded(), "Campaign should be funded");
        assertEq(
            payToken.balanceOf(address(campaign)),
            fundAmount,
            "Campaign should have received tokens"
        );
    }

    function testFundInRevert() public {
        uint256 fundAmount = 10000 ether;
        payToken.mint(address(this), fundAmount);
        payToken.approve(address(campaign), fundAmount);
        campaign.fundIn();

        vm.expectRevert(CampaignNotFunded.selector);
        campaign.fundIn();
    }

    function testRegisterForIDO() public {
        _fundIn();

        //user 1 regerstering for IDO
        _setUpUserWithStake(user1, 250_000, 30 days);
        vm.prank(user1);
        campaign.registerForIDO();
        assertTrue(
            campaign.userRegistered(user1),
            "User1 should be registered"
        );
        assertEq(campaign.userTier(user1), 3, "User1 should be in tier 3");

        //user 2 regerstering for IDO
        _setUpUserWithStake(user2, 500_001, 30 days);
        vm.prank(user2);
        campaign.registerForIDO();
        assertTrue(
            campaign.userRegistered(user2),
            "User2 should be registered"
        );
        assertEq(campaign.userTier(user2), 4, "User2 should be in tier 4");
    }

    function testBuyTierTokens() public {
        _fundIn();

        vm.startPrank(user1);
        campaign.registerForIDO();

        vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

        uint256 buyAmount = 100 ether;
        payToken.mint(user1, buyAmount);
        payToken.approve(address(campaign), buyAmount);
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();

        assertEq(
            campaign.participants(user1),
            buyAmount,
            "User1 should have invested 100 ether"
        );
    }

    // function testBuyFCFSTokens() public {
    //     uint256 fundAmount = 10000 ether;
    //     token.mint(address(this), fundAmount);
    //     token.approve(address(campaign), fundAmount);
    //     campaign.fundIn();

    //     vm.startPrank(user1);
    //     campaign.registerForIDO();
    //     vm.warp(block.timestamp + 5 days + 1); // Move to FCFS period

    //     uint256 buyAmount = 100 ether;
    //     payToken.mint(user1, buyAmount);
    //     payToken.approve(address(campaign), buyAmount);
    //     campaign.buyFCFSTokens(buyAmount);
    //     vm.stopPrank();

    //     assertEq(campaign.participants(user1), buyAmount, "User1 should have invested 100 ether");
    // }

    // function testFinishUp() public {
    //     uint256 fundAmount = 10000 ether;
    //     token.mint(address(this), fundAmount);
    //     token.approve(address(campaign), fundAmount);
    //     campaign.fundIn();

    //     vm.startPrank(user1);
    //     campaign.registerForIDO();
    //     vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

    //     uint256 buyAmount = 200 ether;
    //     payToken.mint(user1, buyAmount);
    //     payToken.approve(address(campaign), buyAmount);
    //     campaign.buyTierTokens(buyAmount);
    //     vm.stopPrank();

    //     vm.warp(block.timestamp + 5 days); // Move to end period
    //     campaign.finishUp();

    //     assertTrue(campaign.finishUpSuccess(), "Campaign should be finished successfully");
    // }

    // function testSetTokenClaimable() public {
    //     uint256 fundAmount = 10000 ether;
    //     token.mint(address(this), fundAmount);
    //     token.approve(address(campaign), fundAmount);
    //     campaign.fundIn();

    //     vm.startPrank(user1);
    //     campaign.registerForIDO();
    //     vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

    //     uint256 buyAmount = 200 ether;
    //     payToken.mint(user1, buyAmount);
    //     payToken.approve(address(campaign), buyAmount);
    //     campaign.buyTierTokens(buyAmount);
    //     vm.stopPrank();

    //     vm.warp(block.timestamp + 5 days); // Move to end period
    //     campaign.finishUp();
    //     campaign.setTokenClaimable();

    //     assertTrue(campaign.tokenReadyToClaim(), "Tokens should be claimable");
    // }

    // function testClaimTokens() public {
    //     uint256 fundAmount = 10000 ether;
    //     token.mint(address(this), fundAmount);
    //     token.approve(address(campaign), fundAmount);
    //     campaign.fundIn();

    //     vm.startPrank(user1);
    //     campaign.registerForIDO();
    //     vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

    //     uint256 buyAmount = 200 ether;
    //     payToken.mint(user1, buyAmount);
    //     payToken.approve(address(campaign), buyAmount);
    //     campaign.buyTierTokens(buyAmount);

    //     vm.warp(block.timestamp + 5 days); // Move to end period
    //     vm.stopPrank();

    //     campaign.finishUp();
    //     campaign.setTokenClaimable();

    //     vm.prank(user1);
    //     campaign.claimTokens();

    //     uint256 expectedTokens = campaign.calculateTokenAmount(buyAmount);
    //     assertEq(token.balanceOf(user1), expectedTokens, "User1 should have received the correct amount of tokens");
    // }

    // function testRefund() public {
    //     uint256 fundAmount = 10000 ether;
    //     token.mint(address(this), fundAmount);
    //     token.approve(address(campaign), fundAmount);
    //     campaign.fundIn();

    //     vm.startPrank(user1);
    //     campaign.registerForIDO();
    //     vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

    //     uint256 buyAmount = 50 ether; // Less than softCap
    //     payToken.mint(user1, buyAmount);
    //     payToken.approve(address(campaign), buyAmount);
    //     campaign.buyTierTokens(buyAmount);

    //     vm.warp(block.timestamp + 5 days); // Move to end period
    //     vm.stopPrank();

    //     campaign.setCancelled();

    //     vm.prank(user1);
    //     campaign.refund();

    //     assertEq(payToken.balanceOf(user1), buyAmount, "User1 should have received a full refund");
    // }
}
