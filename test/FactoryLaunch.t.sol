// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {CC0StrategyFactory} from "../src/CC0StrategyFactory.sol";
import {ICC0StrategyHook} from "../src/Interfaces.sol";
import {MockPositionManager} from "./mocks/MockPositionManager.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";
import {MockRouter} from "./mocks/MockRouter.sol";

contract MockHook is ICC0StrategyHook {
    function adminUpdateFeeAddress(address, address) external {}
}

contract MockERC20Simple {
    string public name = "MockToken";
    string public symbol = "MOCK";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (balanceOf[from] < value) return false;
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to] += value;
        }
        return true;
    }
}

contract FactoryLaunchTest is Test {
    CC0StrategyFactory factory;

    address feeAddress = makeAddr("fees");

    MockPositionManager posm;
    MockPermit2 permit2;
    MockRouter router;

    function setUp() public {
        posm = new MockPositionManager();
        permit2 = new MockPermit2();
        router = new MockRouter();

        factory = new CC0StrategyFactory(
            address(posm),
            address(permit2),
            payable(address(router)),
            address(0),
            feeAddress,
            address(0),
            false
        );
    }

    function test_updateLauncher_onlyOwner() public {
        address anon = makeAddr("anon");
        vm.prank(anon);
        vm.expectRevert();
        factory.updateLauncher(anon, true);

        // owner path
        factory.updateLauncher(anon, true);
        // if public, assert mapping
        try factory.launchers(anon) returns (bool enabled) {
            assertTrue(enabled, "launcher not enabled");
        } catch {}
    }

    function test_updateHookAddress_onlyOwner() public {
        address anon = makeAddr("anon");
        address hook = address(new MockHook());

        vm.prank(anon);
        vm.expectRevert();
        factory.updateHookAddress(hook);

        factory.updateHookAddress(hook);
        assertEq(factory.hookAddress(), hook, "hook not set");
    }

    function test_launchWithEth_happyPath() public {
        // set hook
        address hook = address(new MockHook());
        factory.updateHookAddress(hook);

        // default fee is 0.69 ether
        uint256 fee = factory.launchFeeEth();
        address collection = address(new ERC721Like());

        vm.deal(address(this), fee + 1 ether);

        vm.expectEmit(true, true, false, false);
        emit CC0StrategyLaunched(collection, address(0), "", "");

        address strat = factory.launchCC0StrategyWithEth{value: fee}(
            collection,
            "CC0 Token",
            "CC0",
            makeAddr("owner"),
            1 ether
        );

        assertTrue(strat != address(0), "strategy not deployed");
        assertEq(factory.collectionToCC0Strategy(collection), strat, "indexing failed");
    }

    function test_launchWithEth_revert_whenHookUnset() public {
        address collection = address(new ERC721Like());
        vm.expectRevert(CC0StrategyFactory.HookNotSet.selector);
        factory.launchCC0StrategyWithEth{value: factory.launchFeeEth()}(
            collection,
            "CC0 Token",
            "CC0",
            makeAddr("owner"),
            1 ether
        );
    }

    function test_launchWithCc0_happyPath_and_revertInsufficient() public {
        // use Base mode
        CC0StrategyFactory baseFactory = new CC0StrategyFactory(
            address(posm),
            address(permit2),
            payable(address(router)),
            address(0),
            feeAddress,
            address(0),
            true
        );

        // hook and token settings
        address hook = address(new MockHook());
        baseFactory.updateHookAddress(hook);

        MockERC20Simple token = new MockERC20Simple();
        baseFactory.setCc0CompanyToken(address(token));
        baseFactory.setLaunchFeeCc0OnBase(1_000 ether);

        address collection = address(new ERC721Like());

        // insufficient funds -> revert
        vm.expectRevert(bytes("CC0 transfer failed"));
        baseFactory.launchCC0StrategyWithCc0(
            collection,
            "CC0 Token",
            "CC0",
            makeAddr("owner"),
            1 ether
        );

        // mint and retry -> success
        token.mint(address(this), 1_000 ether);
        address strat = baseFactory.launchCC0StrategyWithCc0(
            collection,
            "CC0 Token",
            "CC0",
            makeAddr("owner"),
            1 ether
        );
        assertTrue(strat != address(0), "cc0 path failed");
    }
}

/// @dev Minimal ERC721-like that advertises the ERC721 interface id
contract ERC721Like {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function ownerOf(uint256) external view returns (address) {
        return address(0);
    }

    function transferFrom(address, address, uint256) external {}

    function owner() external view returns (address) {
        return address(0);
    }
}

