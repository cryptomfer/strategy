// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {MockFeeDecayer} from "test/mocks/MockFeeDecayer.sol";

contract HookFeeDecayTest is Test {
    MockFeeDecayer decayer;

    function setUp() public {
        // Set launch block = now
        decayer = new MockFeeDecayer(block.number);
    }

    function testInitialBuyFeeIsHigh() public view {
        // Should be ~95% at launch
        uint128 f0 = decayer.calculateFee(true);
        assertEq(f0, 9500, "initial buy fee should be 95%");
    }

    function testBuyFeeDecaysOverBlocks() public {
        // Advance 5 blocks => minus 1% (100 bips)
        vm.roll(block.number + 5);
        uint128 f1 = decayer.calculateFee(true);
        assertEq(f1, 9400, "buy fee should decay by 1% every 5 blocks");

        // Advance 25 more blocks (total 30) => minus 6%
        vm.roll(block.number + 25);
        uint128 f2 = decayer.calculateFee(true);
        assertEq(f2, 8900, "buy fee decayed further");
    }

    function testSellFeeUnchangedByDecay() public view {
        uint128 s0 = decayer.calculateFee(false);
        assertEq(s0, 300, "sell fee should be constant (3%)");
    }
}
