//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MOST} from "../contracts/most_contracts/MOST.sol";
import {Staker} from "../contracts/most_contracts/Staker.sol";
import "./DeployHelpers.s.sol";

error InvalidPrivateKey(string);

contract DeployScript is ScaffoldETHDeploy {
    uint256 private constant _MOST_TOTAL_SUPPLY = 100000 ether;

    function run() external {
        uint256 deployerPrivateKey = setupLocalhostEnv();
        if (deployerPrivateKey == 0) {
            revert InvalidPrivateKey(
                "You don't have a deployer account. Make sure you have set DEPLOYER_PRIVATE_KEY in .env or use `yarn generate` to generate a new random account"
            );
        }
        vm.startBroadcast(deployerPrivateKey);
        MOST most = new MOST(_MOST_TOTAL_SUPPLY);
        console.logString(
            string.concat("most deployed at: ", vm.toString(address(most)))
        );

        Staker staker = new Staker(address(most));
        console.logString(
            string.concat("staker deployed at: ", vm.toString(address(staker)))
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
