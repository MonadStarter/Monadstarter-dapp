// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./../Staker.sol";
import {SafeERC20} from "./../SafeERC20.sol";
import "./IFactoryGetters.sol";

contract ReEntrancyGuard {
    bool internal locked;

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }
}

contract Campaign is ReEntrancyGuard {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    address public factory;
    address public campaignOwner;
    address public token;
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public tokenSalesQty;
    uint256 public feePcnt;
    uint256 public startDate;
    uint256 public endDate;
    uint256 public regEndDate;
    uint256 public tierSaleEndDate;
    uint256 public tokenLockTime;

    struct TierProfile {
        uint256 weight;
        uint256 minTokens;
        uint256 noOfParticipants;
    }
    mapping(uint256 => TierProfile) public indexToTier;
    uint256 public totalPoolShares;
    uint256 public sharePriceInFTM;
    bool private isSharePriceSet;

    struct UserProfile {
        bool isRegisterd;
        uint256 inTier;
    }
    mapping(address => UserProfile) public allUserProfile;

    // Config
    bool public burnUnSold;

    // Misc variables //
    uint256 public unlockDate;
    uint256 public collectedFTM;

    // States
    bool public tokenFunded;
    bool public finishUpSuccess;
    bool public cancelled;

    // Token claiming by users
    mapping(address => bool) public claimedRecords;
    bool public tokenReadyToClaim;

    // Map user address to amount invested in FTM //
    mapping(address => uint256) public participants;

    address public constant BURN_ADDRESS =
        address(0x000000000000000000000000000000000000dEaD);

    // Events
    event Registered(
        address indexed user,
        uint256 timeStamp,
        uint256 tierIndex
    );

    event Purchased(
        address indexed user,
        uint256 timeStamp,
        uint256 amountFTM,
        uint256 amountToken
    );

    event TokenClaimed(
        address indexed user,
        uint256 timeStamp,
        uint256 amountToken
    );

    event Refund(address indexed user, uint256 timeStamp, uint256 amountFTM);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory can call");
        _;
    }

    modifier onlyCampaignOwner() {
        require(msg.sender == campaignOwner, "Only campaign owner can call");
        _;
    }

    modifier onlyFactoryOrCampaignOwner() {
        require(
            msg.sender == factory || msg.sender == campaignOwner,
            "Only factory or campaign owner can call"
        );
        _;
    }

    constructor() public {
        factory = msg.sender;
    }

    /**
     * @dev Initialize  a new campaign.
     * @notice - Access control: External. Can only be called by the factory contract.
     */
    function initialize(
        address _token,
        address _campaignOwner,
        uint256[4] calldata _stats,
        uint256[4] calldata _dates,
        bool _burnUnSold,
        uint256 _tokenLockTime,
        uint256[6] calldata _tierWeights,
        uint256[6] calldata _tierMinTokens
    ) external {
        require(msg.sender == factory, "Only factory allowed to initialize");
        token = _token;
        campaignOwner = _campaignOwner;
        softCap = _stats[0];
        hardCap = _stats[1];
        tokenSalesQty = _stats[2];
        feePcnt = _stats[3];
        startDate = _dates[0];
        endDate = _dates[1];
        regEndDate = _dates[2];
        tierSaleEndDate = _dates[3];
        burnUnSold = _burnUnSold;
        tokenLockTime = _tokenLockTime;

        for (uint256 i = 0; i < _tierWeights.length; i++) {
            indexToTier[i + 1] = TierProfile(
                _tierWeights[i],
                _tierMinTokens[i],
                0
            );
        }
    }

    function isInRegistration() public view returns (bool) {
        uint256 timeNow = block.timestamp;
        return (timeNow >= startDate) && (timeNow < regEndDate);
    }

    function isInTierSale() public view returns (bool) {
        uint256 timeNow = block.timestamp;
        return (timeNow >= regEndDate) && (timeNow < tierSaleEndDate);
    }

    function isInFCFS() public view returns (bool) {
        uint256 timeNow = block.timestamp;
        return (timeNow >= tierSaleEndDate) && (timeNow < endDate);
    }

    function isInEnd() public view returns (bool) {
        uint256 timeNow = block.timestamp;
        return (timeNow >= endDate);
    }

    function currentPeriod() external view returns (uint256 period) {
        if (isInRegistration()) period = 0;
        else if (isInTierSale()) period = 1;
        else if (isInFCFS()) period = 2;
        else if (isInEnd()) period = 3;
    }

    function userRegistered(address account) public view returns (bool) {
        return allUserProfile[account].isRegisterd;
    }

    function userTier(address account) external view returns (uint256) {
        return allUserProfile[account].inTier;
    }

    function userAllocation(
        address account
    ) public view returns (uint256 maxInvest, uint256 maxTokensGet) {
        UserProfile memory usr = allUserProfile[account];
        TierProfile memory tier = indexToTier[usr.inTier];
        uint256 userShare = tier.weight;
        if (isSharePriceSet) {
            maxInvest = sharePriceInFTM.mul(userShare);
        } else {
            maxInvest = (hardCap.div(totalPoolShares)).mul(userShare);
        }
        maxTokensGet = calculateTokenAmount(maxInvest);
    }

    function userMaxInvest(address account) public view returns (uint256) {
        (uint256 inv, ) = userAllocation(account);
        return inv;
    }

    function userMaxTokens(address account) external view returns (uint256) {
        (, uint256 toks) = userAllocation(account);
        return toks;
    }

    /**
     * @dev Allows campaign owner to fund in his token.
     * @notice - Access control: External, OnlyCampaignOwner
     */
    function fundIn() external onlyCampaignOwner {
        require(!tokenFunded, "Campaign is already funded");
        uint256 amt = getCampaignFundInTokensRequired();
        require(amt > 0, "Invalid fund in amount");

        tokenFunded = true;
        ERC20(token).safeTransferFrom(msg.sender, address(this), amt);
    }

    // In case of a "cancelled" campaign, or softCap not reached,
    // the campaign owner can retrieve back his funded tokens.
    function fundOut() external onlyCampaignOwner {
        require(
            failedOrCancelled(),
            "Only failed or cancelled campaign can un-fund"
        );
        tokenFunded = false;
        ERC20 ercToken = ERC20(token);
        uint256 totalTokens = ercToken.balanceOf(address(this));
        sendTokensTo(campaignOwner, totalTokens);
    }

    /**
     * @dev To Register In The Campaign In Reg Period
     * @param _tierIndex - The tier index to participate in
     * @notice - Valid tier indexes are, 1, 2, 3 ... 6
     * @notice - Access control: Public
     */
    function registerForIDO(uint256 _tierIndex) external noReentrant {
        require(tokenFunded, "Campaign is not funded yet");
        address account = msg.sender;
        require(isInRegistration(), "Not In Registration Period");
        require(!userRegistered(account), "Already regisered");
        require(_tierIndex >= 1 && _tierIndex <= 6, "Invalid tier index");

        //TODO: user must stake for minimum required duration
        lockTokens(account, tokenLockTime); // Lock staked tokens

        require(
            _isEligibleForTier(account, _tierIndex),
            "Ineligible for the tier"
        );
        _register(account, _tierIndex);
    }

    function registerForIDOByFactory(
        address[] calldata _accounts,
        uint256[] calldata _tiers,
        uint256 _tokenLockTime
    ) external noReentrant onlyFactory {
        require(isInRegistration(), "Not In Registration Period");
        require(
            _accounts.length == _tiers.length,
            "Register: Invalid parameters"
        );

        for (uint256 i = 0; i < _accounts.length; i++) {
            address _account = _accounts[i];
            uint256 _tierIndex = _tiers[i];
            require(_tierIndex >= 1 && _tierIndex <= 6, "Invalid tier index");

            lockTokens(_account, _tokenLockTime);
            _revertEarlyRegistration(_account);
            require(
                _isEligibleForTier(_account, _tierIndex),
                "Ineligible for the tier"
            );
            _register(_account, _tierIndex);
        }
    }

    function _register(address _account, uint256 _tierIndex) private {
        TierProfile storage tier = indexToTier[_tierIndex];

        tier.noOfParticipants = (tier.noOfParticipants).add(1); // Update no. of participants
        totalPoolShares = totalPoolShares.add(tier.weight); // Update total shares
        allUserProfile[_account] = UserProfile(true, _tierIndex); // Update user profile

        emit Registered(_account, block.timestamp, _tierIndex);
    }

    //TODO: this should be based on stake duration not just min_tokens
    function _isEligibleForTier(
        address _account,
        uint256 _tierIndex
    ) private view returns (bool) {
        IFactoryGetters fact = IFactoryGetters(factory);
        address stakerAddress = fact.getStakerAddress();

        Staker stakerContract = Staker(stakerAddress);
        uint256 stakedBal = stakerContract.stakedBalance(_account); // Get the staked balance of user

        return indexToTier[_tierIndex].minTokens <= stakedBal;
    }

    function _revertEarlyRegistration(address _account) private {
        if (userRegistered(_account)) {
            TierProfile storage tier = indexToTier[
                allUserProfile[_account].inTier
            ];
            tier.noOfParticipants = (tier.noOfParticipants).sub(1);
            totalPoolShares = totalPoolShares.sub(tier.weight);
            allUserProfile[_account] = UserProfile(false, 0);
        }
    }

    //TODO: this is for native token, change for any ERC-20
    /**
     * @dev Allows registered user to buy token in tiers.
     * @notice - Access control: Public
     */
    function buyTierTokens() external payable noReentrant {
        require(tokenFunded, "Campaign is not funded yet");
        require(isLive(), "Campaign is not live");
        require(isInTierSale(), "Not in tier sale period");
        require(userRegistered(msg.sender), "Not regisered");

        if (!isSharePriceSet) {
            sharePriceInFTM = hardCap.div(totalPoolShares);
            isSharePriceSet = true;
        }

        // Check for over purchase
        require(msg.value != 0, "Value Can't be 0");
        require(msg.value <= getRemaining(), "Insufficent token left");
        uint256 invested = participants[msg.sender].add(msg.value);
        require(
            invested <= userMaxInvest(msg.sender),
            "Investment is more than allocated"
        );

        participants[msg.sender] = invested;
        collectedFTM = collectedFTM.add(msg.value);

        emit Purchased(
            msg.sender,
            block.timestamp,
            msg.value,
            calculateTokenAmount(msg.value)
        );
    }

    // TODO: this is also in msg.value
    /**
     * @dev Allows registered user to buy token in FCFS.
     * @notice - Access control: Public
     */
    function buyFCFSTokens() external payable noReentrant {
        require(tokenFunded, "Campaign is not funded yet");
        require(isLive(), "Campaign is not live");
        require(isInFCFS(), "Not in FCFS sale period");
        require(userRegistered(msg.sender), "Not regisered");

        // Check for over purchase
        require(msg.value != 0, "Value Can't be 0");
        require(msg.value <= getRemaining(), "Insufficent token left");
        uint256 invested = participants[msg.sender].add(msg.value);

        participants[msg.sender] = invested;
        collectedFTM = collectedFTM.add(msg.value);

        emit Purchased(
            msg.sender,
            block.timestamp,
            msg.value,
            calculateTokenAmount(msg.value)
        );
    }

    /**
     * @dev When a campaign reached the endDate, this function is called.
     * @dev Add liquidity to uniswap and burn the remaining tokens.
     * @dev Can be only executed when the campaign completes.
     * @dev Anyone can call. Only called once.
     * @notice - Access control: Public
     */
    function finishUp() external {
        require(!finishUpSuccess, "finishUp is already called");
        require(!isLive(), "Presale is still live");
        require(
            !failedOrCancelled(),
            "Presale failed or cancelled , can't call finishUp"
        );
        require(softCap <= collectedFTM, "Did not reach soft cap");
        finishUpSuccess = true;

        uint256 feeAmt = getFeeAmt(collectedFTM);
        uint256 unSoldAmtFTM = getRemaining();
        uint256 remainFTM = collectedFTM.sub(feeAmt);

        // Send fee to fee address
        if (feeAmt > 0) {
            (bool sentFee, ) = getFeeAddress().call{value: feeAmt}("");
            require(sentFee, "Failed to send Fee to platform");
        }

        // Send remain FTM to campaign owner
        (bool sentFTM, ) = campaignOwner.call{value: remainFTM}("");
        require(sentFTM, "Failed to send remain FTM to campaign owner");

        //TODO: Return to the owner
        // Calculate the unsold amount //
        if (unSoldAmtFTM > 0) {
            uint256 unsoldAmtToken = calculateTokenAmount(unSoldAmtFTM);
            // Burn or return UnSold token to owner
            sendTokensTo(
                burnUnSold ? BURN_ADDRESS : campaignOwner,
                unsoldAmtToken
            );
        }
    }

    /**
     * @dev Allow either Campaign owner or Factory owner to call this
     * @dev to set the flag to enable token claiming.
     * @dev This is useful when 1 project has multiple campaigns that
     * @dev to sync up the timing of token claiming.
     * @notice - Access control: External,  onlyFactoryOrCampaignOwner
     */
    function setTokenClaimable() external onlyFactoryOrCampaignOwner {
        require(finishUpSuccess, "Campaign not finished successfully yet");
        tokenReadyToClaim = true;
    }

    /**
     * @dev Allow users to claim their tokens.
     * @notice - Access control: External
     */
    function claimTokens() external noReentrant {
        require(tokenReadyToClaim, "Tokens not ready to claim yet");
        require(!claimedRecords[msg.sender], "You have already claimed");

        uint256 amtBought = getClaimableTokenAmt(msg.sender);
        if (amtBought > 0) {
            claimedRecords[msg.sender] = true;
            emit TokenClaimed(msg.sender, block.timestamp, amtBought);
            ERC20(token).safeTransfer(msg.sender, amtBought);
        }
    }

    /**
     * @dev Allows Participants to withdraw/refunds when campaign fails
     * @notice - Access control: Public
     */
    function refund() external {
        require(
            failedOrCancelled(),
            "Can refund for failed or cancelled campaign only"
        );

        uint256 investAmt = participants[msg.sender];
        require(investAmt > 0, "You didn't participate in the campaign");

        //TODO: Change this to work for ERC-20
        participants[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: investAmt}("");
        require(ok, "Failed to refund FTM to user");

        emit Refund(msg.sender, block.timestamp, investAmt);
    }

    /**
     * @dev To calculate the calimable token amount based on user's total invested FTM
     * @param _user - The user's wallet address
     * @return - The total amount of token
     * @notice - Access control: Public
     */
    function getClaimableTokenAmt(address _user) public view returns (uint256) {
        uint256 investAmt = participants[_user];
        return calculateTokenAmount(investAmt);
    }

    // Helpers //
    /**
     * @dev To send all XYZ token to either campaign owner or burn address when campaign finishes or cancelled.
     * @param _to - The destination address
     * @param _amount - The amount to send
     * @notice - Access control: Internal
     */
    function sendTokensTo(address _to, uint256 _amount) internal {
        // Security: Can only be sent back to campaign owner or burned //
        require(
            (_to == campaignOwner) || (_to == BURN_ADDRESS),
            "Can only be sent to campaign owner or burn address"
        );

        // Burn or return UnSold token to owner
        ERC20 ercToken = ERC20(token);
        ercToken.safeTransfer(_to, _amount);
    }

    /**
     * @dev To calculate the amount of fee in FTM
     * @param _amt - The amount in FTM
     * @return - The amount of fee in FTM
     * @notice - Access control: Internal
     */
    function getFeeAmt(uint256 _amt) internal view returns (uint256) {
        return _amt.mul(feePcnt).div(1e6);
    }

    /**
     * @dev To get the fee address
     * @return - The fee address
     * @notice - Access control: Internal
     */
    function getFeeAddress() internal view returns (address) {
        IFactoryGetters fact = IFactoryGetters(factory);
        return fact.getFeeAddress();
    }

    /**
     * @dev To check whether the campaign failed (softcap not met) or cancelled
     * @return - Bool value
     * @notice - Access control: Public
     */
    function failedOrCancelled() public view returns (bool) {
        if (cancelled) return true;

        return (block.timestamp >= endDate) && (softCap > collectedFTM);
    }

    /**
     * @dev To check whether the campaign is isLive? isLive means a user can still invest in the project.
     * @return - Bool value
     * @notice - Access control: Public
     */
    function isLive() public view returns (bool) {
        if (!tokenFunded || cancelled) return false;
        if ((block.timestamp < startDate)) return false;
        if ((block.timestamp >= endDate)) return false;
        if ((collectedFTM >= hardCap)) return false;
        return true;
    }

    /**
     * @dev Calculate amount of token receivable.
     * @param _FTMInvestment - Amount of FTM invested
     * @return - The amount of token
     * @notice - Access control: Public
     */
    function calculateTokenAmount(
        uint256 _FTMInvestment
    ) public view returns (uint256) {
        return _FTMInvestment.mul(tokenSalesQty).div(hardCap);
    }

    /**
     * @dev Gets remaining FTM to reach hardCap.
     * @return - The amount of FTM.
     * @notice - Access control: Public
     */
    function getRemaining() public view returns (uint256) {
        return (hardCap).sub(collectedFTM);
    }

    /**
     * @dev Set a campaign as cancelled.
     * @dev This can only be set before tokenReadyToClaim, finishUpSuccess, liquidityCreated .
     * @dev ie, the users can either claim tokens or get refund, but Not both.
     * @notice - Access control: Public, OnlyFactory
     */
    function setCancelled() external onlyFactory {
        require(!tokenReadyToClaim, "Too late, tokens are claimable");
        require(!finishUpSuccess, "Too late, finishUp called");

        cancelled = true;
    }

    /**
     * @dev Calculate and return the Token amount need to be deposit by the project owner.
     * @return - The amount of token required
     * @notice - Access control: Public
     */
    function getCampaignFundInTokensRequired() public view returns (uint256) {
        return tokenSalesQty;
    }

    // change tokenLockTime to take 4 enum options for our mumltipliers
    function lockTokens(
        address _user,
        uint256 _tokenLockTime
    ) internal returns (bool) {
        IFactoryGetters fact = IFactoryGetters(factory);
        address stakerAddress = fact.getStakerAddress();

        Staker stakerContract = Staker(stakerAddress);
        stakerContract.lock(_user, (block.timestamp).add(_tokenLockTime));
    }
}
