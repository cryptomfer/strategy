// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CC0StrategyFactory} from "src/CC0StrategyFactory.sol";
import {MockPositionManager} from "test/mocks/MockPositionManager.sol";
import {MockPermit2} from "test/mocks/MockPermit2.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockPoolManager} from "test/mocks/MockPoolManager.sol";

contract FactoryForkTest is Test {
    CC0StrategyFactory factory;
    MockPositionManager posm;
    MockPermit2 permit2;
    MockRouter router;
    MockPoolManager poolManager;

    uint256 forkEth;
    uint256 forkBase;

    function setUp() public {
        // ETH fork (url obligatoire, block optionnel)
        {
            string memory url = vm.envString("RPC_URL_ETHEREUM");
            // si FORK_BLOCK_ETHEREUM n’existe pas, on revient à 0
            uint256 blockNum = _envUintOr("FORK_BLOCK_ETHEREUM", 0);
            forkEth = (blockNum == 0) ? vm.createSelectFork(url) : vm.createSelectFork(url, blockNum);
        }

        // BASE fork (url obligatoire, block optionnel)
        {
            string memory url = vm.envString("RPC_URL_BASE");
            uint256 blockNum = _envUintOr("FORK_BLOCK_BASE", 0);
            forkBase = (blockNum == 0) ? vm.createSelectFork(url) : vm.createSelectFork(url, blockNum);
        }

        // On travaille par défaut sur le fork ETH pour ces tests
        vm.selectFork(forkEth);

        // Mocks filaires comme en unit
        posm = new MockPositionManager();
        permit2 = new MockPermit2();
        router = new MockRouter();
        poolManager = new MockPoolManager();

        address feeAddress = makeAddr("fees");
        address launchDeployer = address(0);
        bool isBaseChain = false;

        factory = new CC0StrategyFactory(
            address(posm),
            address(permit2),
            address(router),
            address(poolManager),
            feeAddress,
            launchDeployer,
            isBaseChain
        );
    }

    function testFork_SimpleOwner() public {
        assertEq(factory.owner(), address(this));
    }

    function testFork_UpdateHookAddress() public {
        address hook = makeAddr("hook");
        vm.prank(factory.owner());
        factory.updateHookAddress(hook);
        // pas de revert = ok
    }

    // ---------- helpers ----------
    function _envUintOr(string memory key, uint256 fallbackValue) internal returns (uint256) {
        // essaye de lire une variable d'env uint, sinon renvoie la valeur de secours
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch {
            return fallbackValue;
        }
    }
}
