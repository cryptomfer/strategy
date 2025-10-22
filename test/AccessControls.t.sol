// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {CC0StrategyFactory} from "../src/CC0StrategyFactory.sol";
import {MockPositionManager} from "./mocks/MockPositionManager.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";
import {MockRouter} from "./mocks/MockRouter.sol";

contract AccessControlsTest is Test {
    CC0StrategyFactory factory;
    address deployer = address(0xBEEF);
    address poolManager = address(0xDEAD);
    address feeAddress = address(0xFEED);

    function setUp() public {
        vm.startPrank(deployer);

        MockPositionManager posmMock = new MockPositionManager();
        MockPermit2 permit2Mock = new MockPermit2();
        MockRouter routerMock = new MockRouter();

        factory = new CC0StrategyFactory(
            address(posmMock),
            address(permit2Mock),
            payable(address(routerMock)),
            address(0),
            feeAddress,
            address(0),
            false
        );

        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateHookAddress() public {
        address hook = address(0x9999);
        vm.expectRevert(); // not owner
        factory.updateHookAddress(hook);

        vm.prank(deployer);
        factory.updateHookAddress(hook);
    }

    function testOnlyOwnerCanUpdateLauncher() public {
        address alice = makeAddr("alice");
        // Non-owner cannot update launcher
        vm.expectRevert();
        vm.prank(alice);
        factory.updateLauncher(alice, true);

        // Owner can update launcher
        vm.prank(deployer);
        factory.updateLauncher(alice, true);
    }
}

