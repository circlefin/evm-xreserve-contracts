/**
 * Copyright 2025 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
pragma solidity ^0.8.29;

import {MasterMinter} from "@gateway/test/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "@gateway/test/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployFiatToken} from "@gateway/test/mock_fiattoken/deploy-fiat-token.s.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Test} from "forge-std/Test.sol";

// Contract to deploy mock FiatToken (USDC) contract for local testing. Copied with minor modification from @circlefin/stablecoin-evm/test/scripts/deploy/TestUtils.sol
// solhint-disable-next-line max-states-count
contract DeployMockFiatToken is CommonBase, Test {
    uint256 internal deployerPrivateKey = 1;
    address public deployer = vm.addr(deployerPrivateKey);

    uint8 internal decimals = 6;
    string internal tokenName = "USDC";
    string internal tokenSymbol = "USDC";
    string internal tokenCurrency = "USD";

    DeployFiatToken private deployScript;

    function setUpMockFiatTokenConfig(address owner) public {
        vm.setEnv("TOKEN_NAME", tokenName);
        vm.setEnv("TOKEN_SYMBOL", tokenSymbol);
        vm.setEnv("TOKEN_CURRENCY", tokenCurrency);
        vm.setEnv("TOKEN_DECIMALS", "6");
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("PROXY_ADMIN_ADDRESS", vm.toString(makeAddr("fiatTokenProxyAdmin")));
        vm.setEnv("MASTER_MINTER_OWNER_ADDRESS", vm.toString(owner));
        vm.setEnv("OWNER_ADDRESS", vm.toString(owner));
        vm.setEnv("PAUSER_ADDRESS", vm.toString(owner));
        vm.setEnv("BLACKLISTER_ADDRESS", vm.toString(owner));

        // Deploy an instance of proxy contract to configure contract address in env
        vm.prank(deployer);
        FiatTokenV2_2 fiatToken = new FiatTokenV2_2();

        vm.prank(owner);
        FiatTokenProxy proxy = new FiatTokenProxy(address(fiatToken));

        vm.startPrank(deployer);
        MasterMinter masterMinter = new MasterMinter(address(proxy));
        masterMinter.transferOwnership(owner);

        FiatTokenV2_2 proxyAsFiatToken = FiatTokenV2_2(address(proxy));

        proxyAsFiatToken.initialize(tokenName, tokenSymbol, "USD", decimals, address(masterMinter), owner, owner, owner);
        proxyAsFiatToken.initializeV2(tokenName);
        proxyAsFiatToken.initializeV2_1(owner);
        proxyAsFiatToken.initializeV2_2(new address[](0), tokenSymbol);
        vm.setEnv("FIAT_TOKEN_PROXY_ADDRESS", vm.toString(address(proxy)));

        vm.stopPrank();
    }

    /// @dev Deploy a mock FiatToken contract for local testing.
    /// @param owner The owner of the FiatToken contract.
    /// @return fiatToken The deployed FiatToken contract.
    function deployMockFiatToken(address owner) public returns (FiatTokenV2_2 fiatToken) {
        setUpMockFiatTokenConfig(owner);

        vm.prank(deployer);
        deployScript = new DeployFiatToken();
        deployScript.setUp();
        (,, FiatTokenProxy fiatTokenProxy) = deployScript.run();
        fiatToken = FiatTokenV2_2(address(fiatTokenProxy));
    }
}
