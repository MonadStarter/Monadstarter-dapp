// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Campaign.sol";

contract Factory is IFactoryGetters, Ownable {
    address private launcherTokenAddress;
    address private stakerAddress;
    address public payToken;

    struct CampaignInfo {
        address contractAddress;
        address owner;
    }
    // List of campaign and their project owner address.
    // For security, only project owner can provide fund.
    mapping(uint256 => CampaignInfo) public allCampaigns;
    uint256 public count;

    address private feeAddress;

    constructor(
        address _stakerAddress,
        address _feeAddress,
        address _paytoken
    ) {
        payToken = _paytoken;
        feeAddress = _feeAddress;
        stakerAddress = _stakerAddress;
    }

    //TODO: make sure the decimals of the fee token
    /**
     * @dev Create a new campaign
     * @param _token - The token address
     * @param _subIndex - The fund raising round Id
     * @param _campaignOwner - Campaign owner address
     * @param _stats - Array of 4 uint256 values.
     * @notice - [0] Softcap. 1e18 = 1 FTM.
     * @notice - [1] Hardcap. 1e18 = 1 FTM.
     * @notice - [2] TokenSalesQty. The amount of tokens for sale. Example: 1e8 for 1 token with 8 decimals.
     * @notice - [3] feePcnt. 100% is 1e6.
     * @param _dates - Array of 4 uint256 dates.
     * @notice - [0] Start date.
     * @notice - [1] End date. (Considering FCFS)
     * @notice - [2] Registration End date.
     * @notice - [3] Tier Sale End date.
     * @param _burnUnSold - Indicate to burn un-sold tokens or not. For successful campaign only.
     * @return campaignAddress - The address of the new campaign smart contract created
     * @notice - Access control: Public, OnlyOwner
     * @param _tierWeights - Array of 6 uint256 values.
     * @param _tierMinTokens - Array of 6 uint256 values.
     * @notice - there are 6 tier pools
     * @notice - _tierWeights are list of weights of the tiers
     * @notice - _tierMinTokens are list of min tokens required to participate in the tiers
     */

    function createCampaign(
        address _token,
        uint256 _subIndex,
        address _campaignOwner,
        uint256[4] memory _stats,
        uint256[4] memory _dates,
        bool _burnUnSold,
        uint256 _tokenLockTime,
        uint256[5] memory _tierWeights,
        uint256[5] memory _tierMinTokens
    ) public onlyOwner returns (address campaignAddress) {
        require(
            _stats[0] < _stats[1],
            "Soft cap can't be higher than hard cap"
        );
        require(_stats[2] > 0, "Token for sales can't be 0");
        require(_stats[3] <= 1e6, "Invalid fees value");

        require(
            _dates[0] < _dates[1],
            "Start date can't be higher than end date"
        );
        require(
            _dates[0] < _dates[2] && _dates[0] < _dates[3],
            "Reg And Tier Sale Can't Be Before Start Date"
        );
        require(
            _dates[1] > _dates[2] && _dates[1] > _dates[3],
            "Reg And Tier Sale Can't Be After End Date"
        );
        require(_dates[2] < _dates[3], "Reg Can't End before tier sale");
        require(
            block.timestamp < _dates[0],
            "Start date must be higher than current date "
        );

        bytes memory bytecode = type(Campaign).creationCode;
        bytes32 salt = keccak256(
            abi.encodePacked(_token, _subIndex, msg.sender)
        );
        assembly {
            campaignAddress := create2(
                0,
                add(bytecode, 32),
                mload(bytecode),
                salt
            )
        }

        Campaign(campaignAddress).initialize(
            _token,
            _campaignOwner,
            _stats,
            _dates,
            _burnUnSold,
            _tokenLockTime,
            _tierWeights,
            _tierMinTokens,
            payToken
        );

        allCampaigns[count] = CampaignInfo(campaignAddress, _campaignOwner);

        count = count + 1;

        return campaignAddress;
    }

    function updatePayToken(address newToken) external onlyOwner {
        require(newToken != address(0), "Invalid token address");
        payToken = newToken;
    }

    /**
     * @dev Cancel a campaign
     * @param _campaignID - The campaign ID
     * @notice - Access control: External, OnlyOwner
     */
    function cancelCampaign(uint256 _campaignID) external onlyOwner {
        require(_campaignID < count, "Invalid ID");

        CampaignInfo memory info = allCampaigns[_campaignID];
        require(
            info.contractAddress != address(0),
            "Invalid Campaign contract"
        );

        Campaign camp = Campaign(info.contractAddress);
        camp.setCancelled();
    }

    /**
     * @dev Get the fee address
     * @return - Return the fee address
     * @notice - Access control: External
     */
    function getFeeAddress() external view override returns (address) {
        return feeAddress;
    }

    /**
     * @dev Get the staker token address
     * @return - Return the address
     * @notice - Access control: External
     */
    function getStakerAddress() external view override returns (address) {
        return stakerAddress;
    }
}
