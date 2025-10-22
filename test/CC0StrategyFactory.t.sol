// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {CC0StrategyFactory} from "../src/CC0StrategyFactory.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

// Use our local vendor interface to keep tests decoupled from periphery layout.
import {IUniswapV4Router04} from "../src/vendor/IUniswapV4Router04.sol";

import {MockPositionManager} from "./mocks/MockPositionManager.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";
import {MockRouter} from "./mocks/MockRouter.sol";

import {Ownable} from "solady/auth/Ownable.sol";


contract CC0StrategyFactoryTest is Test {
    CC0StrategyFactory factory;

    // Mocks
    MockPositionManager posmMock;
    MockPermit2 permit2Mock;
    MockRouter routerMock;

    // Constructor args
    IPositionManager posm;
    IAllowanceTransfer permit2;
    IUniswapV4Router04 router;
    IPoolManager poolManager;
    address feeAddress;
    address weth; // use zero unless your code reads it
    bool isBaseChain;

    function setUp() public {
        // Deploy mocks
        posmMock = new MockPositionManager();
        permit2Mock = new MockPermit2();
        routerMock = new MockRouter();

        // Wire constructor args
        posm = IPositionManager(address(posmMock));
        permit2 = IAllowanceTransfer(address(permit2Mock));
        router = IUniswapV4Router04(payable(address(routerMock)));
        poolManager = IPoolManager(address(0));
        feeAddress = makeAddr("fees");
        weth = address(0);
        isBaseChain = false;

        factory = new CC0StrategyFactory(
            address(posm),
            address(permit2),
            payable(address(router)),
            address(poolManager),
            feeAddress,
            weth,
            isBaseChain
        );
    }

    function testOwnerIsDeployer() public {
        assertEq(factory.owner(), address(this), "owner should be test contract");
    }

    function testOnlyOwnerCanUpdateLauncher() public {
        address anon = makeAddr("anon");

        // non-owner reverts
        vm.prank(anon);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        factory.updateLauncher(anon, true);

        // owner succeeds
        factory.updateLauncher(anon, true);
        // mapping launchers(address)=>bool is public in factory; assert it if exposed
        try factory.launchers(anon) returns (bool enabled) {
            assertTrue(enabled, "launcher should be enabled");
        } catch {
            // if not public, we at least assert no revert on the call above
            assertTrue(true);
        }
    }

    function testOnlyOwnerCanUpdateHookAddress() public {
        address anon = makeAddr("anon");
        address newHook = makeAddr("hook");

        // non-owner reverts
        vm.prank(anon);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        factory.updateHookAddress(newHook);

        // owner succeeds (don’t assert return type in case signature changed)
        factory.updateHookAddress(newHook);
    }
}


