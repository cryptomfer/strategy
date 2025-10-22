// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {CC0StrategyFactory} from "../src/CC0StrategyFactory.sol";
import {ICC0StrategyHook} from "../src/Interfaces.sol";
import {IPositionManager, IAllowanceTransfer, IUniswapV4Router04, IPoolManager} from "../src/vendor/UniswapInterfaces.sol";
import {MockPositionManager} from "./mocks/MockPositionManager.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";
import {MockRouter} from "./mocks/MockRouter.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";

contract FactoryLaunchTest is Test {
    CC0StrategyFactory public factory;
    MockPositionManager public posm;
    MockPermit2 public permit2;
    MockRouter public router;
    MockPoolManager public poolManager;
    address public owner = address(this);

    function setUp() public {
        posm = new MockPositionManager();
        permit2 = new MockPermit2();
        router = new MockRouter();
        poolManager = new MockPoolManager();

        factory = new CC0StrategyFactory(
            address(posm),
            address(permit2),
            payable(address(router)),
            address(poolManager),
            address(0xFEE5),
            address(0),
            false
        );
    }

    function testOnlyOwnerCanUpdateLauncher() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.updateLauncher(nonOwner, true);

        factory.updateLauncher(address(1), true);
        assertTrue(factory.launchers(address(1)));
    }

    function testOnlyOwnerCanUpdateHookAddress() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.updateHookAddress(address(0x123));

        factory.updateHookAddress(address(0x999));
        assertEq(factory.hookAddress(), address(0x999));
    }

    function testLaunchCC0StrategyWithEth() public {
        factory.updateHookAddress(address(0x999));
        vm.deal(address(this), 1 ether);
        factory.launchCC0StrategyWithEth{value: 0.1 ether}(address(0xAAA));
    }

    function testLaunchCC0StrategyWithCc0() public {
        CC0StrategyFactory baseFactory = new CC0StrategyFactory(
            address(posm),
            address(permit2),
            payable(address(router)),
            address(poolManager),
            address(0xFEE5),
            address(0),
            true
        );

        baseFactory.updateHookAddress(address(0x999));
        baseFactory.launchCC0StrategyWithCc0(address(0xAAA), 1 ether);
    }
}
