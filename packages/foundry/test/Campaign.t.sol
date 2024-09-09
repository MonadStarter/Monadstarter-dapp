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
    MOST public stakeTokenMOST;
    BTC public campaignTokenBTC;
    USDC public payTokenUSDC;

    address public owner;
    address public user1;
    address public user2;
    address public feeAddress;

    uint256 public softcap;
    uint256 public hardcap;
    uint256 public tokenSalesQuantity;
    uint256 public fee;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        feeAddress = address(0x4);

        // Deploy tokens
        stakeTokenMOST = new MOST(10000 ** 18);
        campaignTokenBTC = new BTC(10000 ** 18);
        payTokenUSDC = new USDC(10000 ** 18);

        staker = new Staker(address(stakeTokenMOST));

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        stakeTokenMOST.transfer(user1, 1000 ether);
        stakeTokenMOST.transfer(user2, 1000 ether);

        payTokenUSDC.transfer(user1, 1000 ether);
        payTokenUSDC.transfer(user2, 1000 ether);

        softcap = uint256(100_000);
        hardcap = uint256(1000 ether);
        tokenSalesQuantity = uint256(1000 ether);
        fee = uint256(500);

        // Set up campaign parameters
        address _token = address(campaignTokenBTC);
        address _campaignOwner = owner;
        uint256[4] memory _stats = [softcap, hardcap, tokenSalesQuantity, fee];
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
        address _payToken = address(payTokenUSDC);

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
        stakeTokenMOST.approve(address(staker), amount);
        vm.prank(user);
        staker.stake(amount, duration);
    }

    function _fundIn() public {
        uint256 fundAmount = 1000 ether;
        campaignTokenBTC.mint(owner, fundAmount);
        campaignTokenBTC.approve(address(campaign), fundAmount);
        campaign.fundIn();
    }

    function _registerUserForCampaign(
        address user,
        uint256 amount,
        uint256 duration
    ) public {
        _setUpUserWithStake(user, amount, duration);
        vm.prank(user);
        campaign.registerForIDO();
    }

    function testConstructor() public view {
        // Test campaign owner
        assertEq(campaign.campaignOwner(), owner, "Campaign owner mismatch");

        // Test stats
        assertEq(campaign.softCap(), softcap, "Soft cap mismatch");
        assertEq(campaign.hardCap(), 1000 ether, "Hard cap mismatch");
        assertEq(
            campaign.tokenSalesQty(),
            1000 ether,
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
            address(campaign.token()),
            address(campaignTokenBTC),
            "campaignToken address mismatch"
        );
        assertEq(
            address(campaign.payToken()),
            address(payTokenUSDC),
            "payToken address mismatch"
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
        campaignTokenBTC.mint(address(this), fundAmount);

        // Approve the campaign to spend tokens
        campaignTokenBTC.approve(address(campaign), fundAmount);

        // Fund the campaign
        campaign.fundIn();

        assertTrue(campaign.tokenFunded(), "Campaign should be funded");
        assertEq(
            campaignTokenBTC.balanceOf(address(campaign)),
            fundAmount,
            "Campaign should have received tokens"
        );
    }

    function testFundInRevert() public {
        uint256 fundAmount = 10000 ether;
        campaignTokenBTC.mint(address(this), fundAmount);
        campaignTokenBTC.approve(address(campaign), fundAmount);
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

    function testUserAllocation() public {
        //check allocaiton for tier 4 when no-one other than 1 user has invested
        //in this case, maxInvest should be hardcap and maxTokenGet should be all tokens
        // because they are the only participant
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);

        (uint256 maxInvest, uint256 maxTokenGet) = campaign.userAllocation(
            user1
        );
        assertEq(
            maxInvest,
            hardcap,
            "Invalid maxInvest check user allocation function"
        );
        assertEq(
            maxTokenGet,
            tokenSalesQuantity,
            "Invalid tokenSalesQuantity check user allocation function"
        );

        // a new participant enters the arena, joins 1st tear
        _registerUserForCampaign(user2, 54_000, 90 days);
        (uint256 maxInvest1, uint256 maxTokenGet1) = campaign.userAllocation(
            user1
        );
        (uint256 maxInvest2, uint256 maxTokenGet2) = campaign.userAllocation(
            user2
        );
        //now user 1 gets 80% and user 2 gets the rest
        assertEq(
            maxInvest1,
            (hardcap * 80) / 100,
            "Invalid maxInvest check user allocation function"
        );
        assertEq(
            maxTokenGet1,
            (tokenSalesQuantity * 80) / 100,
            "Invalid maxInvest check user allocation function"
        );

        assertEq(
            maxInvest2,
            (hardcap * 20) / 100,
            "Invalid maxInvest check user allocation function"
        );
        assertEq(
            maxTokenGet2,
            (tokenSalesQuantity * 20) / 100,
            "Invalid maxInvest check user allocation function"
        );
    }

    function testBuyTierTokens() public {
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);

        vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

        (uint256 maxInvest, ) = campaign.userAllocation(user1);
        uint256 buyAmount = maxInvest / 2;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();

        assertEq(
            campaign.participants(user1),
            buyAmount,
            "User1 should have invested half of their max allocation"
        );
    }

    function testBuyFCFSTokens() public {
        _fundIn();
        vm.warp(block.timestamp + 5 days + 1); // Move to FCFS period

        uint256 buyAmount = 50 ether;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);
        campaign.buyFCFSTokens(buyAmount);
        vm.stopPrank();

        assertEq(
            campaign.participants(user1),
            buyAmount,
            "User1 should have invested 50 ether in FCFS"
        );
    }

    function testFinishUp() public {
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);
        _registerUserForCampaign(user2, 2500000, 90 days);

        vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

        uint256 buyAmount = softcap;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days + 1); // Move to end period

        uint256 ownerUSDCBalance = payTokenUSDC.balanceOf(owner);
        uint256 ownerBTCBalance = campaignTokenBTC.balanceOf(owner);

        vm.prank(owner);
        campaign.finishUp();
        vm.prank(owner);
        campaign.setTokenClaimable();

        vm.prank(user1);
        campaign.claimTokens();
        uint256 userBTCBalance = campaignTokenBTC.balanceOf(user1);

        assertTrue(
            campaign.finishUpSuccess(),
            "Campaign should be finished successfully"
        );

        uint256 feeCalc = (500 * (buyAmount)) / 10000;

        assertEq(
            payTokenUSDC.balanceOf(feeAddress),
            feeCalc,
            "fee calculation is messed up"
        );
        assertEq(
            payTokenUSDC.balanceOf(owner),
            ownerUSDCBalance + (buyAmount - feeCalc)
        );
        assertEq(
            campaignTokenBTC.balanceOf(owner),
            ownerBTCBalance + (tokenSalesQuantity - userBTCBalance)
        );
    }

    function testSetTokenClaimable() public {
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);

        vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

        uint256 buyAmount = softcap;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days + 1); // Move to end period

        vm.prank(owner);
        campaign.finishUp();

        vm.prank(owner);
        campaign.setTokenClaimable();

        assertTrue(campaign.tokenReadyToClaim(), "Tokens should be claimable");
    }

    function testClaimTokens() public {
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);

        vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

        uint256 buyAmount = softcap;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days + 1); // Move to end period

        vm.prank(owner);
        campaign.finishUp();

        vm.prank(owner);
        campaign.setTokenClaimable();

        uint256 expectedTokens = campaign.getClaimableTokenAmt(user1);

        vm.prank(user1);
        campaign.claimTokens();

        assertEq(
            campaignTokenBTC.balanceOf(user1),
            expectedTokens,
            "User1 should have received the correct amount of tokens"
        );
    }

    function testRefund() public {
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);

        vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

        uint256 buyAmount = 5 ether; // Less than softcap
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days + 1); // Move to end period

        vm.prank(owner);
        campaign.setCancelled();

        uint256 balanceBefore = payTokenUSDC.balanceOf(user1);

        vm.prank(user1);
        campaign.refund();

        assertEq(
            payTokenUSDC.balanceOf(user1),
            balanceBefore + buyAmount,
            "User1 should have received a refund"
        );
    }

    function testSetCancelled() public {
        _fundIn();

        vm.prank(owner);
        campaign.setCancelled();

        assertTrue(campaign.cancelled(), "Campaign should be cancelled");
    }

    function testFailFundInTwice() public {
        _fundIn();

        vm.expectRevert(CampaignNotFunded.selector);
        _fundIn();
    }

    function testFailRegisterAfterRegPeriod() public {
        _fundIn();
        vm.warp(block.timestamp + 2 days + 1); // Move past registration period

        vm.expectRevert("Not In Registration Period");
        _registerUserForCampaign(user1, 500_000, 90 days);
    }

    function testFailBuyTierTokensBeforeTierSale() public {
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);

        uint256 buyAmount = 10 ether;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);

        vm.expectRevert("Not in tier sale period");
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();
    }

    function testFailBuyFCFSTokensBeforeFCFSPeriod() public {
        _fundIn();

        uint256 buyAmount = 10 ether;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);

        vm.expectRevert("Not in FCFS sale period");
        campaign.buyFCFSTokens(buyAmount);
        vm.stopPrank();
    }

    function testFailFinishUpBeforeEnd() public {
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);

        vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

        uint256 buyAmount = softcap;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();

        vm.expectRevert("Presale is still live");
        vm.prank(owner);
        campaign.finishUp();
    }

    function testFailClaimTokensBeforeClaimable() public {
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);

        vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

        uint256 buyAmount = softcap;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days + 1); // Move to end period

        vm.prank(owner);
        campaign.finishUp();

        vm.expectRevert("Tokens not ready to claim yet");
        vm.prank(user1);
        campaign.claimTokens();
    }

    function testFailRefundBeforeCancellation() public {
        _fundIn();
        _registerUserForCampaign(user1, 500_000, 90 days);

        vm.warp(block.timestamp + 2 days + 1); // Move to tier sale period

        uint256 buyAmount = 5 ether;
        payTokenUSDC.mint(user1, buyAmount);
        vm.startPrank(user1);
        payTokenUSDC.approve(address(campaign), buyAmount);
        campaign.buyTierTokens(buyAmount);
        vm.stopPrank();

        vm.expectRevert("Can refund for failed or cancelled campaign only");
        vm.prank(user1);
        campaign.refund();
    }
}
