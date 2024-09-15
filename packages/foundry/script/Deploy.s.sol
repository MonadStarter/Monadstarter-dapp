//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MOST} from "../contracts/most_contracts/MOST.sol";
import {BTC} from "../contracts/most_contracts/BTC.sol";
import {USDC} from "../contracts/most_contracts/USDC.sol";

import {Staker} from "../contracts/most_contracts/Staker.sol";
import {Campaign} from "../contracts/most_contracts/Campaign.sol";
import "./DeployHelpers.s.sol";

error InvalidPrivateKey(string);

contract DeployScript is ScaffoldETHDeploy {
    uint256 private constant _MOST_TOTAL_SUPPLY = 100000 ether;
    uint256 private constant _BTC_TOKEN_TOTAL_SUPPLY = 100000 ether;
    uint256 private constant _USDC_TOKEN_TOTAL_SUPPLY = 100000 ether;

    function run() external {
        uint256 deployerPrivateKey = setupLocalhostEnv();
        if (deployerPrivateKey == 0) {
            revert InvalidPrivateKey(
                "You don't have a deployer account. Make sure you have set DEPLOYER_PRIVATE_KEY in .env or use `yarn generate` to generate a new random account"
            );
        }
        vm.startBroadcast(deployerPrivateKey);
        MOST most = new MOST(_MOST_TOTAL_SUPPLY);
        BTC btc = new BTC(_BTC_TOKEN_TOTAL_SUPPLY);
        USDC usdc = new USDC(_USDC_TOKEN_TOTAL_SUPPLY);

        console.logString(
            string.concat("most deployed at: ", vm.toString(address(most)))
        );

        Staker staker = new Staker(address(most));
        console.logString(
            string.concat("staker deployed at: ", vm.toString(address(staker)))
        );

        softcap = uint256(100_000);
        hardcap = uint256(1000 ether);
        tokenSalesQuantity = uint256(1000 ether);
        fee = uint256(500);

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

        // Deploy campaign contract
        campaign = new Campaign(
            address(btc),
            _campaignOwner,
            _stats,
            _dates,
            _burnUnSold,
            _tokenLockTime,
            _tierWeights,
            _tierMinTokens,
            address(usdc),
            address(staker),
            feeAddress
        );
        vm.stopBroadcast();

        /**
         * This function generates the file containing the contracts Abi definitions.
         * These definitions are used to derive the types needed in the custom scaffold-eth hooks, for example.
         * This function should be called last.
         */
        exportDeployments();
    }
}
