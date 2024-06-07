// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Staker.sol";
import "./IFactoryGetters.sol";


//TODO: Remove dependency on factory, remove factory function calls, add staker contract address
// Update initialize and constructor
contract Campaign is ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

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
    uint256 public tokenLockTime; // probably don't need this
    IERC20 public payToken;

    //TODO: also have max number of participants
    struct TierProfile {
        uint256 weight;
        uint256 minTokens;
        uint256 noOfParticipants;
    }
    mapping(uint256 => TierProfile) public indexToTier;
    uint256 public totalPoolShares; //TODO:what does this mean
    uint256 public sharePriceInFTM; //TODO:what does this mean 
    bool private isSharePriceSet; //TODO:what does this mean
    address[] public participantsList;

    //TODO: can be in staker contract
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

    // Map user address to amount invested in FTM or any ERC-20 //
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

    modifier onlyCampaignOwner() {
        require(msg.sender == campaignOwner, "Only campaign owner can call");
        _;
    }

    constructor() {
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
        uint256[5] calldata _tierWeights,
        uint256[5] calldata _tierMinTokens,
        address _payToken
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
        tokenLockTime = _tokenLockTime; //TODO: might not need this, users should be able to specify this or we can pull from staker contract
        payToken = IERC20(_payToken);

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

    //TODO: Move to staker
    function userTier(address account) external view returns (uint256) {
        return allUserProfile[account].inTier;
    }

    function userAllocation(
        address account
    ) public view returns (uint256 maxInvest, uint256 maxTokensGet) {
        UserProfile memory usr = allUserProfile[account];
        TierProfile memory tier = indexToTier[usr.inTier];
        uint256 userShare = tier.weight //TODO: add user multiplier here
        if (isSharePriceSet) {
            maxInvest = sharePriceInFTM * userShare;
        } else {
            maxInvest = (hardCap / totalPoolShares) * (userShare);
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
        IERC20(token).safeTransferFrom(msg.sender, address(this), amt);
    }

    // In case of a "cancelled" campaign, or softCap not reached,
    // the campaign owner can retrieve back his funded tokens.
    function fundOut() external onlyCampaignOwner {
        require(
            failedOrCancelled(),
            "Only failed or cancelled campaign can un-fund"
        );
        tokenFunded = false;
        IERC20 ercToken = IERC20(token);
        uint256 totalTokens = ercToken.balanceOf(address(this));
        sendTokensTo(campaignOwner, totalTokens);
    }

    /**
     * @dev To Register In The Campaign In Reg Period
     * @param _tierIndex - The tier index to participate in
     * @notice - Valid tier indexes are, 1, 2, 3 ... 6
     * @notice - Access control: Public
     //TODO: probably don't need tierIndex, automatically set tier based on number of staked tokens by user
     */
    function registerForIDO(uint256 _tierIndex) external nonReentrant {
        address account = msg.sender;

        require(tokenFunded, "Campaign is not funded yet");
        require(isInRegistration(), "Not In Registration Period");
        require(!userRegistered(account), "Already regisered");
        require(_tierIndex >= 1 && _tierIndex <= 6, "Invalid tier index");

        //TODO: not needed, tokens are automatically locked when staking
        lockTokens(account, tokenLockTime); // Lock staked tokens
        require(
            _isEligibleForTier(account, _tierIndex),
            "Ineligible for the tier"
        );
        _register(account, _tierIndex);
    }

    //TODO: not really sure what this is doing
    function _register(address _account, uint256 _tierIndex) private {
        TierProfile storage tier = indexToTier[_tierIndex];

        
        tier.noOfParticipants = (tier.noOfParticipants) + 1; // Update no. of participants
        totalPoolShares = totalPoolShares + tier.weight; // Update total shares
        allUserProfile[_account] = UserProfile(true, _tierIndex); // Update user profile

        emit Registered(_account, block.timestamp, _tierIndex);
    }


    //TODO: not needed, directly get the highest tier a account is eligible for
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

    //TODO:what does this do, it's not called anywhere
    function _revertEarlyRegistration(address _account) private {
        if (userRegistered(_account)) {
            TierProfile storage tier = indexToTier[
                allUserProfile[_account].inTier
            ];
            tier.noOfParticipants = tier.noOfParticipants - 1;
            totalPoolShares = totalPoolShares - tier.weight;
            allUserProfile[_account] = UserProfile(false, 0);
        }
    }

    /**
     * @dev Allows registered user to buy token in tiers.
     * @notice - Access control: Public
     */
    function buyTierTokens(uint256 value) external nonReentrant {
        payToken.safeTransferFrom(msg.sender, address(this), value);

        require(tokenFunded, "Campaign is not funded yet");
        require(isLive(), "Campaign is not live");
        require(isInTierSale(), "Not in tier sale period");
        require(userRegistered(msg.sender), "Not regisered");

        if (!isSharePriceSet) {
            sharePriceInFTM = hardCap / totalPoolShares;
            isSharePriceSet = true;
        }

        // Check for over purchase
        require(value != 0, "Value Can't be 0");
        require(value <= getRemaining(), "Insufficent token left");
        uint256 invested = participants[msg.sender] + value;
        require(
            invested <= userMaxInvest(msg.sender),
            "Investment is more than allocated"
        );

        if (participants[msg.sender] == 0) {
            participantsList.push(msg.sender);
        }
        participants[msg.sender] = invested;
        collectedFTM = collectedFTM + value;

        emit Purchased(
            msg.sender,
            block.timestamp,
            value,
            calculateTokenAmount(value)
        );
    }

    /**
     * @dev Allows registered user to buy token in FCFS.
     * @notice - Access control: Public
     */
    function buyFCFSTokens(uint256 value) external nonReentrant {
        payToken.safeTransferFrom(msg.sender, address(this), value);

        require(tokenFunded, "Campaign is not funded yet");
        require(isLive(), "Campaign is not live");
        require(isInFCFS(), "Not in FCFS sale period");
        // require(userRegistered(msg.sender), "Not regisered");

        // Check for over purchase
        require(value != 0, "Value Can't be 0");
        require(value <= getRemaining(), "Insufficent token left");
        if (participants[msg.sender] == 0) {
            participantsList.push(msg.sender);
        }
        uint256 invested = participants[msg.sender] + value;

        participants[msg.sender] = invested;

        collectedFTM = collectedFTM + value;

        emit Purchased(
            msg.sender,
            block.timestamp,
            value,
            calculateTokenAmount(value)
        );
    }

    /**
     * @dev When a campaign reached the endDate, this function is called.
     * @dev Can be only executed when the campaign completes.
     * @dev Only called once.
     * @notice - Access control: CampaignOwner
     //TODO: Anyone should be able to call this
     */
    function finishUp() external onlyCampaignOwner {
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
        uint256 remainFTM = collectedFTM - feeAmt;

        // Send fee to fee address
        if (feeAmt > 0) {
            payToken.safeTransfer(getFeeAddress(), feeAmt);
        }

        payToken.safeTransfer(campaignOwner, remainFTM);

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
    function setTokenClaimable() external onlyCampaignOwner {
        require(finishUpSuccess, "Campaign not finished successfully yet");
        tokenReadyToClaim = true;
    }

    /**
     * @dev Allow users to claim their tokens.
     * @notice - Access control: External
     */
    function claimTokens() external nonReentrant {
        require(tokenReadyToClaim, "Tokens not ready to claim yet");
        require(!claimedRecords[msg.sender], "You have already claimed");

        uint256 amtBought = getClaimableTokenAmt(msg.sender);
        if (amtBought > 0) {
            claimedRecords[msg.sender] = true;
            emit TokenClaimed(msg.sender, block.timestamp, amtBought);
            IERC20(token).safeTransfer(msg.sender, amtBought);
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

        participants[msg.sender] = 0;
        payToken.safeTransfer(msg.sender, investAmt);

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
        IERC20 ercToken = IERC20(token);
        ercToken.safeTransfer(_to, _amount);
    }

    /**
     * @dev To calculate the amount of fee in FTM
     * @param _amt - The amount in FTM
     * @return - The amount of fee in FTM
     * @notice - Access control: Internal
     */
    function getFeeAmt(uint256 _amt) internal view returns (uint256) {
        return (_amt * feePcnt) / (1e6);
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
        return (_FTMInvestment * tokenSalesQty) / hardCap;
    }

    /**
     * @dev Gets remaining FTM to reach hardCap.
     * @return - The amount of FTM.
     * @notice - Access control: Public
     */
    function getRemaining() public view returns (uint256) {
        return hardCap - collectedFTM;
    }

    /**
     * @dev Set a campaign as cancelled.
     * @dev This can only be set before tokenReadyToClaim, finishUpSuccess.
     * @dev ie, the users can either claim tokens or get refund, but Not both.
     * @notice - Access control: Public, OnlyFactory
     */
    function setCancelled() external onlyCampaignOwner {
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

    // TODO: Staker contract does not support this anymore
    function lockTokens(
        address _user,
        uint256 _tokenLockTime
    ) internal returns (bool) {
        // IFactoryGetters fact = IFactoryGetters(factory);
        // address stakerAddress = fact.getStakerAddress();

        // Staker stakerContract = Staker(stakerAddress);
        // stakerContract.lock(_user, (block.timestamp + _tokenLockTime));

        return true;
    }

    function getParticipantsLength() external view returns (uint256) {
        return participantsList.length;
    }
}
