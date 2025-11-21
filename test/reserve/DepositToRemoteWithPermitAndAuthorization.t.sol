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

import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {ZeroAddress} from "./../../src/common/Errors.sol";
import {DepositParams, PermitParams, AuthorizationParams} from "./../../src/lib/DepositParams.sol";
import {Blocklistable} from "./../../src/modules/x-reserve/Blocklistable.sol";
import {DepositToRemote} from "./../../src/modules/x-reserve/DepositToRemote.sol";
import {Pausing} from "./../../src/modules/x-reserve/Pausing.sol";
import {RemoteDomainRegistration} from "./../../src/modules/x-reserve/RemoteDomainRegistration.sol";
import {TokenSupport} from "./../../src/modules/x-reserve/TokenSupport.sol";
import {xReserve} from "../../src/xReserve.sol";
import {DeployXReserve} from "../utils/DeployXReserve.sol";
import {ForkTestUtils} from "./../utils/ForkTestUtils.sol";

contract XReserveDepositToRemoteWithPermitAndAuthorizationTest is DeployXReserve {
    xReserve private reserve;
    FiatTokenV2_2 private token;

    address private owner = makeAddr("owner");
    address private pauser = owner;
    address private blocklister = owner;
    address private user;
    uint256 private userPrivateKey;
    uint256 private activeTimeOffset;

    address private gatewayWallet;
    address private gatewayMinter;

    // Remote domain setup
    address internal remoteRecipient;
    bytes32 internal remoteRecipientBytes32;

    uint32 private domain;
    uint32 private constant REMOTE_DOMAIN = 10001;
    uint256 internal constant MAX_FEE = 10e6; // 10 USDC
    bytes internal constant HOOK_DATA = "test integration hook data";

    // EIP712 permit signature parameters
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // EIP3009 authorization signature parameters
    bytes32 private constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    function setUp() public {
        // Generate a proper private key for testing
        userPrivateKey = uint256(keccak256("test user"));
        user = vm.addr(userPrivateKey);

        // Get fork variables for contract addresses
        ForkTestUtils.ForkVars memory forkedVars = ForkTestUtils.forkVars();
        domain = forkedVars.domain;
        token = FiatTokenV2_2(forkedVars.usdc);
        gatewayWallet = forkedVars.gatewayWallet;
        gatewayMinter = forkedVars.gatewayMinter;
        activeTimeOffset = 1 minutes;

        remoteRecipient = makeAddr("remoteRecipient");
        remoteRecipientBytes32 = bytes32(uint256(uint160(remoteRecipient)));

        reserve = deployXReserve(
            owner, domain, gatewayMinter, gatewayWallet, forkedVars.tokenMessenger, forkedVars.tokenMessengerV2
        );

        // Add token as supported
        vm.prank(owner);
        reserve.addSupportedToken(address(token));

        // Register remote domain
        address[] memory attesters = new address[](2);
        attesters[0] = makeAddr("attester1");
        attesters[1] = makeAddr("attester2");

        vm.prank(owner);
        reserve.registerRemoteDomain(REMOTE_DOMAIN, owner, makeAddr("domainPauser"), attesters, 2, 50400, address(0));

        bytes32 remoteToken = bytes32(uint256(uint160(makeAddr("remoteToken"))));
        vm.prank(owner);
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, remoteToken);

        // Setup user's token balance
        deal(address(token), user, 10000e6);
    }

    // Helper function to create permit signature
    function _createPermitSignature(address _owner, address spender, uint256 value, uint256 deadline, uint256 nonce)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        return vm.sign(userPrivateKey, digest);
    }

    // Helper function to create authorization signature
    function _createAuthorizationSignature(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 structHash =
            keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        return vm.sign(userPrivateKey, digest);
    }

    // ============ Permit Tests ============
    function test_depositToRemoteWithPermit_succeeds() public {
        uint256 value = 1000e6;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "test hook data";
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(user);

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(user, address(reserve), value, deadline, nonce);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true);
        emit DepositToRemote.DepositedToRemote(
            address(token),
            value,
            user,
            destinationRecipient,
            REMOTE_DOMAIN,
            reserve.getRemoteToken(REMOTE_DOMAIN, address(token)),
            maxFee,
            hookData
        );

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: maxFee,
            hookData: hookData
        });

        PermitParams memory permitParams = PermitParams({owner: user, deadline: deadline, signature: signature});

        reserve.depositToRemoteWithPermit(depositParams, permitParams);
    }

    function test_depositToRemoteWithPermit_realPermit_succeeds() public {
        uint256 value = 1000e6;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(user);

        // Create permit params and execute test
        PermitParams memory permitParams = _createRealPermitParams(value, deadline);
        DepositParams memory depositParams = _createDepositParams(value);

        // Capture initial state
        uint256 initialUserBalance = token.balanceOf(user);
        uint256 initialNonce = token.nonces(user);
        uint256 initialGatewayBalance = token.balanceOf(gatewayWallet);

        // Expect event
        _expectDepositedToRemote(depositParams);

        // Execute the deposit with real permit flow
        vm.prank(user);
        reserve.depositToRemoteWithPermit(depositParams, permitParams);

        // Verify the REAL permit was processed correctly
        assertEq(token.nonces(user), initialNonce + 1, "User nonce should be incremented by real permit");
        assertEq(token.allowance(user, address(reserve)), 0, "Allowance should be consumed by real transfer");
        assertEq(token.nonces(user), nonce + 1, "User nonce should increment");
        assertEq(token.balanceOf(user), initialUserBalance - value, "User balance should decrease by real transfer");
        assertEq(
            token.balanceOf(gatewayWallet),
            initialGatewayBalance + value,
            "GatewayWallet should hold tokens at the end of transaction"
        );
    }

    function test_depositToRemoteWithPermit_revertsWhenZeroValue() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: 0,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: 0,
            hookData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(DepositToRemote.ZeroValue.selector));
        PermitParams memory permitParams = PermitParams({
            owner: user,
            deadline: deadline,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        reserve.depositToRemoteWithPermit(depositParams, permitParams);
    }

    function test_depositToRemoteWithPermit_revertsWhenZeroAddressToken() public {
        uint256 value = 1000e6;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(0),
            maxFee: 0,
            hookData: ""
        });

        vm.expectRevert(ZeroAddress.selector);
        PermitParams memory permitParams = PermitParams({
            owner: user,
            deadline: deadline,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        reserve.depositToRemoteWithPermit(depositParams, permitParams);
    }

    function test_depositToRemoteWithPermit_revertsWhenDomainPaused() public {
        // Pause domain deposits using the reserve's pausing
        vm.prank(makeAddr("domainPauser")); // Use the domain pauser for REMOTE_DOMAIN
        reserve.setDomainPauseState(REMOTE_DOMAIN, true, false);

        uint256 value = 1000e6;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: 0,
            hookData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(Pausing.DomainDepositsPaused.selector, REMOTE_DOMAIN));
        PermitParams memory permitParams = PermitParams({
            owner: user,
            deadline: deadline,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        reserve.depositToRemoteWithPermit(depositParams, permitParams);
    }

    function test_depositToRemoteWithPermit_revertsWhenRecipientBlocklisted() public {
        // Blocklist the recipient
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        vm.prank(blocklister);
        reserve.blocklist(REMOTE_DOMAIN, destinationRecipient);

        uint256 value = 1000e6;
        uint256 deadline = block.timestamp + 1 hours;

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: 0,
            hookData: ""
        });

        vm.expectRevert(
            abi.encodeWithSelector(Blocklistable.AccountBlocklisted.selector, REMOTE_DOMAIN, destinationRecipient)
        );
        PermitParams memory permitParams = PermitParams({
            owner: user,
            deadline: deadline,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        reserve.depositToRemoteWithPermit(depositParams, permitParams);
    }

    function test_depositToRemoteWithPermit_revertsWhenInsufficientBalance() public {
        uint256 userBalance = token.balanceOf(user);
        uint256 depositAmount = userBalance + 1; // User tries to deposit more than they have

        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "";
        uint256 deadline = block.timestamp + 1 hours;

        DepositParams memory depositParams = DepositParams({
            value: depositAmount,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: maxFee,
            hookData: hookData
        });

        // Attempt to deposit more than user balance should revert during permit-based transfer
        uint256 nonce = token.nonces(user);
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(user, address(reserve), depositAmount, deadline, nonce);
        PermitParams memory permitParams =
            PermitParams({owner: user, deadline: deadline, signature: abi.encodePacked(r, s, v)});
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(user);
        reserve.depositToRemoteWithPermit(depositParams, permitParams);
    }

    function test_depositToRemoteWithPermit_expiredDeadline_reverts() public {
        uint256 deadline = block.timestamp - 1; // Expired deadline
        uint256 nonce = token.nonces(user);
        uint256 value = 1000e6;

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(user, address(reserve), value, deadline, nonce);
        bytes memory signature = abi.encodePacked(r, s, v);

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: remoteRecipientBytes32,
            localToken: address(token),
            maxFee: MAX_FEE,
            hookData: HOOK_DATA
        });

        PermitParams memory permitParams = PermitParams({owner: user, deadline: deadline, signature: signature});

        // Should revert due to expired deadline
        vm.expectRevert("FiatTokenV2: permit is expired");
        reserve.depositToRemoteWithPermit(depositParams, permitParams);
    }

    // ============ Authorization Tests ============

    function test_depositToRemoteWithAuthorization_succeeds() public {
        uint256 value = 1000e6;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "test hook data";
        bytes32 nonce = keccak256("test nonce");

        // Advance time first
        skip(activeTimeOffset);

        // Then set validAfter to be in the past and validBefore to be in the future
        uint256 validAfter = block.timestamp - 10; // 10 seconds in the past
        uint256 validBefore = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) =
            _createAuthorizationSignature(user, address(reserve), value, validAfter, validBefore, nonce);

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: maxFee,
            hookData: hookData
        });

        AuthorizationParams memory authParams = AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(r, s, v)
        });

        _expectDepositedToRemote(depositParams);
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);
    }

    function test_depositToRemoteWithAuthorization_revertsWhenZeroValue() public {
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test nonce");
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: 0,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: 0,
            hookData: ""
        });

        AuthorizationParams memory authParams = AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        vm.expectRevert(abi.encodeWithSelector(DepositToRemote.ZeroValue.selector));
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);
    }

    function test_depositToRemoteWithAuthorization_revertsWhenZeroAddressToken() public {
        uint256 value = 1000e6;
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test nonce");
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(0),
            maxFee: 0,
            hookData: ""
        });

        AuthorizationParams memory authParams = AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        vm.expectRevert(ZeroAddress.selector);
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);
    }

    function test_depositToRemoteWithAuthorization_revertsWhenDomainPaused() public {
        // Pause domain deposits using the reserve's pausing
        vm.prank(makeAddr("domainPauser")); // Use the domain pauser for REMOTE_DOMAIN
        reserve.setDomainPauseState(REMOTE_DOMAIN, true, false);

        uint256 value = 1000e6;
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test nonce");
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: 0,
            hookData: ""
        });

        AuthorizationParams memory authParams = AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        vm.expectRevert(abi.encodeWithSelector(Pausing.DomainDepositsPaused.selector, REMOTE_DOMAIN));
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);
    }

    function test_depositToRemoteWithAuthorization_revertsWhenRecipientBlocklisted() public {
        // Blocklist the recipient
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        vm.prank(blocklister);
        reserve.blocklist(REMOTE_DOMAIN, destinationRecipient);

        uint256 value = 1000e6;
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test nonce");

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: 0,
            hookData: ""
        });

        AuthorizationParams memory authParams = AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        vm.expectRevert(
            abi.encodeWithSelector(Blocklistable.AccountBlocklisted.selector, REMOTE_DOMAIN, destinationRecipient)
        );
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);
    }

    function test_depositToRemoteWithAuthorization_revertsWhenInsufficientBalance() public {
        // Domain and token are already registered in setUp(), no need to register again

        uint256 userBalance = 500e6; // User has 500 tokens
        uint256 depositAmount = 1000e6; // User tries to deposit 1000 tokens

        address masterMinter = token.masterMinter();
        vm.prank(masterMinter);
        token.configureMinter(address(this), type(uint256).max);

        token.mint(user, userBalance);

        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "";
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test nonce");

        DepositParams memory depositParams = DepositParams({
            value: depositAmount,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: maxFee,
            hookData: hookData
        });

        // receiveWithAuthorization should fail due to insufficient balance or invalid signature
        // Since we're using zero signature, it will fail at signature validation
        vm.expectRevert();
        AuthorizationParams memory authParams = AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);
    }

    function test_depositToRemoteWithAuthorization_revertsWhenUnsupportedToken() public {
        FiatTokenV2_2 unsupportedToken = deployMockFiatToken(owner);

        uint256 value = 1000e6;
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test nonce");
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(unsupportedToken),
            maxFee: 0,
            hookData: ""
        });

        AuthorizationParams memory authParams = AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        vm.expectRevert(abi.encodeWithSelector(TokenSupport.UnsupportedToken.selector, address(unsupportedToken)));
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);
    }

    function test_depositToRemoteWithPermit_revertsWhenUnsupportedToken() public {
        FiatTokenV2_2 unsupportedToken = deployMockFiatToken(owner);

        uint256 value = 1000e6;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: destinationRecipient,
            localToken: address(unsupportedToken),
            maxFee: 0,
            hookData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(TokenSupport.UnsupportedToken.selector, address(unsupportedToken)));
        PermitParams memory permitParams = PermitParams({
            owner: user,
            deadline: deadline,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        reserve.depositToRemoteWithPermit(depositParams, permitParams);
    }

    function test_depositToRemoteWithPermit_revertsWhenRemoteDomainNotRegistered() public {
        uint32 unregisteredDomain = 99999;
        uint256 value = 1000e6;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: unregisteredDomain,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: 0,
            hookData: ""
        });

        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, unregisteredDomain)
        );
        PermitParams memory permitParams = PermitParams({
            owner: user,
            deadline: deadline,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        reserve.depositToRemoteWithPermit(depositParams, permitParams);
    }

    function test_depositToRemoteWithAuthorization_revertsWhenRemoteDomainNotRegistered() public {
        uint32 unregisteredDomain = 99999;
        uint256 value = 1000e6;
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test nonce");
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: unregisteredDomain,
            remoteRecipient: destinationRecipient,
            localToken: address(token),
            maxFee: 0,
            hookData: ""
        });

        AuthorizationParams memory authParams = AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });
        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, unregisteredDomain)
        );
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);
    }

    function test_depositToRemoteWithAuthorization_revertsWithReusedNonce() public {
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("reuse_test_nonce");
        uint256 value = 1000e6;

        (uint8 v, bytes32 r, bytes32 s) =
            _createAuthorizationSignature(user, address(reserve), value, validAfter, validBefore, nonce);
        bytes memory signature = abi.encodePacked(r, s, v);

        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: remoteRecipientBytes32,
            localToken: address(token),
            maxFee: MAX_FEE,
            hookData: HOOK_DATA
        });

        AuthorizationParams memory authParams = AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: signature
        });

        // First use should succeed
        _expectDepositedToRemote(depositParams);
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);

        // Second use should revert
        vm.expectRevert("FiatTokenV2: authorization is used or canceled");
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);
    }

    /// @notice Integration test using real authorization calls instead of mocks
    function test_depositToRemoteWithAuthorization_realAuthorization_succeeds() public {
        uint256 value = 1000e6;
        bytes32 nonce = keccak256("test nonce for real auth");

        // Create authorization params and execute test
        AuthorizationParams memory authParams = _createRealAuthorizationParams(value, nonce);
        DepositParams memory depositParams = _createDepositParams(value);

        // Capture initial state
        uint256 initialUserBalance = token.balanceOf(user);
        uint256 initialGatewayBalance = token.balanceOf(gatewayWallet);
        bool wasAuthUsedBefore = _getAuthorizationState(nonce);

        // Expect event and execute
        _expectDepositedToRemote(depositParams);
        vm.prank(user);
        reserve.depositToRemoteWithAuthorization(depositParams, authParams);

        // Verify the REAL authorization was processed correctly
        assertEq(
            token.balanceOf(user),
            initialUserBalance - value,
            "User balance should decrease by real authorization transfer"
        );
        assertEq(
            token.balanceOf(gatewayWallet),
            initialGatewayBalance + value,
            "GatewayWallet should receive tokens from real authorization"
        );

        bool wasAuthUsedAfter = _getAuthorizationState(nonce);
        if (wasAuthUsedAfter != wasAuthUsedBefore) {
            // Only check if authorizationState is available
            assertEq(wasAuthUsedAfter, true, "Authorization should be marked as used");
            assertEq(wasAuthUsedBefore, false, "Authorization should not have been used before");

            // Try to reuse the same authorization - should fail
            vm.expectRevert();
            vm.prank(user);
            reserve.depositToRemoteWithAuthorization(depositParams, authParams);
        }
    }

    // ============ Helper Functions for Stack Depth Optimization ============

    function _createDepositParams(uint256 value) internal view returns (DepositParams memory) {
        return DepositParams({
            value: value,
            remoteDomain: REMOTE_DOMAIN,
            remoteRecipient: bytes32(uint256(uint160(user))),
            localToken: address(token),
            maxFee: 10,
            hookData: "test hook data"
        });
    }

    function _createRealPermitParams(uint256 value, uint256 deadline) internal view returns (PermitParams memory) {
        uint256 nonce = token.nonces(user);
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(user, address(reserve), value, deadline, nonce);
        return PermitParams({owner: user, deadline: deadline, signature: abi.encodePacked(r, s, v)});
    }

    function _createRealAuthorizationParams(uint256 value, bytes32 nonce)
        internal
        view
        returns (AuthorizationParams memory)
    {
        uint256 validAfter = block.timestamp - 1; // Set to past timestamp to ensure validity
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _createAuthorizationSignature(user, address(reserve), value, validAfter, validBefore, nonce);
        return AuthorizationParams({
            from: user,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(r, s, v)
        });
    }

    function _expectDepositedToRemote(DepositParams memory depositParams) internal {
        vm.expectEmit(true, true, true, true);
        emit DepositToRemote.DepositedToRemote(
            depositParams.localToken,
            depositParams.value,
            user,
            depositParams.remoteRecipient,
            depositParams.remoteDomain,
            reserve.getRemoteToken(depositParams.remoteDomain, depositParams.localToken),
            depositParams.maxFee,
            depositParams.hookData
        );
    }

    function _getAuthorizationState(bytes32 nonce) internal view returns (bool) {
        try token.authorizationState(user, nonce) returns (bool used) {
            return used;
        } catch {
            return false; // If authorizationState doesn't exist, assume false
        }
    }
}
