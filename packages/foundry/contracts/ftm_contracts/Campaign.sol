// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Staker.sol";


//TODO: Remove dependency on factory, remove factory function calls, add staker contract address
// Update initialize and constructor
error NotCampaignOwner(address account);
error CampaignNotFunded();
error InvalidAmount(uint256 amt);
error CampaignNotRevoked();
error CampaignRegistrationError();
error UserRegistrationError();
error CampaignNotLive();
error NotInFCFS();
error PresaleCancelled();
error SoftcapNotReached();
error InPresale();
error CampaignOver();
error CampaignNotOver();
error NotClaimable();
error ClaimedAlready(address account);


contract Campaign is ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    address public campaignOwner;
    address public token; //campaignToken
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
    address public staker;
    address public feeAddress; //multisig of zk starter

    //TODO: also have max number of participants
    struct TierProfile {
        uint256 weight;
        uint256 minTokens;
        uint256 noOfParticipants;
    }
    mapping(uint256 => TierProfile) public indexToTier;
    uint256 public totalPoolShares; //TODO:what does this mean
    uint256 public sharePriceInFTM; 
    bool private isSharePriceSet; 
    address[] public participantsList;

    //TODO: can be in staker contract
    struct UserProfile {
        bool isRegisterd;
        uint256 inTier;
        uint256 multiplier;
    }
    mapping(address => UserProfile) public allUserProfile;

    // Config
    bool public burnUnSold;//TODO: we don't need this option

    // Misc variables //
    uint256 public unlockDate;
    uint256 public collectedToken;

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
        if (msg.sender != campaignOwner){
            revert NotCampaignOwner(msg.sender);
        }
        _;
    }

    constructor (
        address _token,
        address _campaignOwner,
        uint256[4] calldata _stats,
        uint256[4] calldata _dates,
        bool _burnUnSold, //TODO: we don't need this option
        uint256 _tokenLockTime,
        uint256[5] calldata _tierWeights,
        uint256[5] calldata _tierMinTokens,
        address _payToken,
        address _staker
        address _feeAddress,
    ) external {
        //require(msg.sender == factory, "Only factory allowed to initialize");
        token = _token; //campaignToken
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
        staker = _staker;
        feeAddress = _feeAddress;
        for (uint256 i = 0; i < _tierWeights.length; i++) {
            indexToTier[i + 1] = TierProfile(
                _tierWeights[i],
                _tierMinTokens[i],
                0
            );
        }
    }

    /**
     * @dev Initialize  a new campaign.
     * @notice - Access control: External. Can only be called by the factory contract.
     */
    // function initialize(
    //     address _token,
    //     address _campaignOwner,
    //     uint256[4] calldata _stats,
    //     uint256[4] calldata _dates,
    //     bool _burnUnSold,
    //     uint256 _tokenLockTime,
    //     uint256[5] calldata _tierWeights,
    //     uint256[5] calldata _tierMinTokens,
    //     address _payToken
    // ) external {
    //     require(msg.sender == factory, "Only factory allowed to initialize");
    //     token = _token;
    //     campaignOwner = _campaignOwner;
    //     softCap = _stats[0];
    //     hardCap = _stats[1];
    //     tokenSalesQty = _stats[2];
    //     feePcnt = _stats[3];
    //     startDate = _dates[0];
    //     endDate = _dates[1];
    //     regEndDate = _dates[2];
    //     tierSaleEndDate = _dates[3];
    //     burnUnSold = _burnUnSold;
    //     tokenLockTime = _tokenLockTime; //TODO: might not need this, users should be able to specify this or we can pull from staker contract
    //     payToken = IERC20(_payToken);

    //     for (uint256 i = 0; i < _tierWeights.length; i++) {
    //         indexToTier[i + 1] = TierProfile(
    //             _tierWeights[i],
    //             _tierMinTokens[i],
    //             0
    //         );
    //     }
    // }

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

    //REVIEW: Check this
    function userAllocation(
        address account
    ) public view returns (uint256 maxInvest, uint256 maxTokensGet) {
        UserProfile memory usr = allUserProfile[account];
        TierProfile memory tier = indexToTier[usr.inTier];
        uint256 userShare = (tier.weight * usr.multiplier) / 100;
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
        if (tokenFunded){
            revert CampaignNotFunded();
        }
        uint256 amt = getCampaignFundInTokensRequired();
        if (amount <= 0){
            revert InvalidAmount(amt)
        }
        //require(amt > 0, "Invalid fund in amount");

        tokenFunded = true;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amt);
    }

    // In case of a "cancelled" campaign, or softCap not reached,
    // the campaign owner can retrieve back his funded tokens.
    function fundOut() external onlyCampaignOwner {
        if (!failedOrCancelled()){
            revert CampaignNotRevoked();
        }

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
     */
    function registerForIDO() external nonReentrant {
        address account = msg.sender;
        (uint256 amountStaked, _, lockedFor ,_) = IStaker(staker).getUserStakeDetails(account);
        //user must have a some stake value
        uint256 tierIndex = IStaker(staker).getTierIndex(amountStaked);
        if (tierIndex == 0){
            revert UserRegistrationError();
        }
        if (!tokenFunded){
            revert CampaignNotFunded();
        }
        if (!isInRegistration()){
            revert CampaignRegistrationError();
        }
        if (userRegistered(account)){
            revert UserRegistrationError();
        }


        uint256 multiplier = IStaker(staker).getMultiplier(lockedFor);

        _register(account, tierIndex, multiplier);
    }

    function _register(address _account, uint256 _tierIndex, uint256 _multiplier) private {
        TierProfile storage tier = indexToTier[_tierIndex];
        tier.noOfParticipants = (tier.noOfParticipants) + 1; // Update no. of participants
        //REVIEW: do we also add multiplier here?
        totalPoolShares = totalPoolShares + (tier.weight * multiplier); // Update total shares
        allUserProfile[_account] = UserProfile(true, _tierIndex, _multiplier); // Update user profile

        emit Registered(_account, block.timestamp, _tierIndex);
    }


    //TODO: not needed, directly get the highest tier a account is eligible for
    // function _isEligibleForTier(
    //     address _account,
    //     uint256 _tierIndex
    // ) private view returns (bool) {
    //     IFactoryGetters fact = IFactoryGetters(factory);
    //     address stakerAddress = fact.getStakerAddress();

    //     Staker stakerContract = Staker(stakerAddress);
    //     uint256 stakedBal = stakerContract.stakedBalance(_account); // Get the staked balance of user

    //     return indexToTier[_tierIndex].minTokens <= stakedBal;
    // }

    //TODO:what does this do, it's not called anywhere
    // function _revertEarlyRegistration(address _account) private {
    //     if (userRegistered(_account)) {
    //         TierProfile storage tier = indexToTier[
    //             allUserProfile[_account].inTier
    //         ];
    //         tier.noOfParticipants = tier.noOfParticipants - 1;
    //         totalPoolShares = totalPoolShares - tier.weight;
    //         allUserProfile[_account] = UserProfile(false, 0);
    //     }
    // }

    /**
     * @dev Allows registered user to buy token in tiers.
     * @notice - Access control: Public
     */
    function buyTierTokens(uint256 value) external nonReentrant {
        payToken.safeTransferFrom(msg.sender, address(this), value);

        if (!tokenFunded){
            revert CampaignNotFunded();
        }

        if (!isLive() || !isInTierSale()){
            revert CampaignNotLive();
        }

        if (!userRegistered(account)){
            revert UserRegistrationError();
        }

        //REVIEW
        if (!isSharePriceSet) {
            sharePriceInFTM = hardCap / totalPoolShares;
            isSharePriceSet = true;
        }

        // Check for over purchase
        if (value == 0 || value > getRemaining()){
            revert InvalidAmount(value);
        }

        uint256 invested = participants[msg.sender] + value;

        if (invested > userMaxInvest(msg.sender)){
            revert InvalidAmount(value);
        }

        if (participants[msg.sender] == 0) {
            participantsList.push(msg.sender);
        }
        participants[msg.sender] = invested;
        collectedToken = collectedToken + value;

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
        if (!tokenFunded){
            revert CampaignNotFunded();
        }   
        if (!isLive()){
            revert CampaignNotLive();
        }

        if (!isInFCFS()){
            revert NotInFCFS();
        }
        if (!userRegistered(account)){
            revert UserRegistrationError();
        }

        // require(userRegistered(msg.sender), "Not regisered");

        // Check for over purchase
        if (value == 0 || value > getRemaining()){
            revert InvalidAmount(value);
        }
        
        if (participants[msg.sender] == 0) {
            participantsList.push(msg.sender);
        }
        uint256 invested = participants[msg.sender] + value;

        participants[msg.sender] = invested;

        collectedToken = collectedToken + value;

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
        if (finishUpSuccess){
            revert CampaignOver();
        }
        if (isLive()){
            revert InPresale();
        }
        if (failedOrCancelled()){
            revert PresaleCancelled();
        }
        if (collectedToken <= softCap){
            revert SoftcapNotReached();
        }
        
        finishUpSuccess = true;

        uint256 feeAmt = getFeeAmt(collectedToken);
        uint256 unSoldAmtFTM = getRemaining();
        uint256 remainFTM = collectedToken - feeAmt;

        // Send fee to fee address
        if (feeAmt > 0) {
            payToken.safeTransfer(feeAddress, feeAmt);
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
        if (!finishUpSuccess){
            revert CampaignNotOver();
        }
        tokenReadyToClaim = true;
    }

    /**
     * @dev Allow users to claim their tokens.
     * @notice - Access control: External
     */
    function claimTokens() external nonReentrant {
        if (!tokenReadyToClaim){
            revert NotClaimable();
        }
        address account = msg.sender
        if (claimedRecords[account]){
            revert ClaimedAlready(account);
        }

        uint256 amtBought = getClaimableTokenAmt(account);
        if (amtBought > 0) {
            claimedRecords[account] = true;
            emit TokenClaimed(account, block.timestamp, amtBought);
            IERC20(token).safeTransfer(account, amtBought);
        }
    }

    /**
     * @dev Allows Participants to withdraw/refunds when campaign fails
     * @notice - Access control: Public
     */
    function refund() external {
        if (!failedorCancelled()){
            revert CampaignNotOver();
        }

        uint256 investAmt = participants[msg.sender];
        if (investAmt == 0){
            revert InvalidAmount(investAmt);
        }

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
        // require(
        //     (_to == campaignOwner) || (_to == BURN_ADDRESS),
        //     "Can only be sent to campaign owner or burn address"
        // );
        //REVIEW
        if (_to != campaignOwner && _to != BURN_ADDRESS){
            revert NotCampaignOwner(_to);
        }

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
        //REViEW check decimal based on our token decimals
        return (_amt * feePcnt) / (1e6);
    }


    /**
     * @dev To check whether the campaign failed (softcap not met) or cancelled
     * @return - Bool value
     * @notice - Access control: Public
     */
    function failedOrCancelled() public view returns (bool) {
        if (cancelled) return true;

        return (block.timestamp >= endDate) && (softCap > collectedToken);
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
        if ((collectedToken >= hardCap)) return false;
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
        return hardCap - collectedToken;
    }

    /**
     * @dev Set a campaign as cancelled.
     * @dev This can only be set before tokenReadyToClaim, finishUpSuccess.
     * @dev ie, the users can either claim tokens or get refund, but Not both.
     * @notice - Access control: Public, OnlyFactory
     */
    function setCancelled() external onlyCampaignOwner {
        //require(!tokenReadyToClaim, "Too late, tokens are claimable");
        //require(!finishUpSuccess, "Too late, finishUp called");
        //REVIEW check this
        if (tokenReadyToClaim || finishUpSuccess){
            revert CampaignOver();
        }
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


}
