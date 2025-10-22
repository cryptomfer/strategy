// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

// Interfaces locales de ton projet (tu les as déjà dans src/)
import {CC0StrategyFactory} from "src/CC0StrategyFactory.sol";
import {CC0StrategyHook} from "src/CC0StrategyHook.sol";

// Mocks si besoin (tu en as déjà)
import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockPositionManager} from "test/mocks/MockPositionManager.sol";
import {MockPermit2} from "test/mocks/MockPermit2.sol";
import {MockPoolManager} from "test/mocks/MockPoolManager.sol";

contract FactoryForkTest is Test {
    // On lit les URLs RPC du .env au setup
    string internal rpcEthereum;
    string internal rpcBase;

    // On garde des refs sur le fork courant si tu veux switcher
    uint256 internal forkEth;
    uint256 internal forkBase;

    // Dépendances / SUT
    CC0StrategyFactory internal factory;
    address internal feeAddress = address(0xFee);

    // Mocks utilisés même en fork pour éviter de dépendre d’artefacts externes
    MockRouter internal router;
    MockPositionManager internal posm;
    MockPermit2 internal permit2;
    MockPoolManager internal poolManager;

    function setUp() public {
        // charge les URLs depuis .env
        rpcEthereum = vm.envString("RPC_URL_ETHEREUM");
        rpcBase = vm.envString("RPC_URL_BASE");

        // crée 2 forks et sélectionne l’un d’eux
        forkEth = vm.createSelectFork(rpcEthereum);
        // forkBase = vm.createFork(rpcBase);

        // Instancie les mocks (même en fork, on reste hermétique aux vrais contrats)
        router = new MockRouter();
        posm = new MockPositionManager();
        permit2 = new MockPermit2();
        poolManager = new MockPoolManager();

        // Déploie la factory avec les bonnes signatures (tu les utilises déjà dans tes tests unitaires)
        factory = new CC0StrategyFactory(
            address(posm),
            address(permit2),
            payable(address(router)),
            address(poolManager),
            feeAddress,
            address(0),    // optional feeSplit or owner override si ton ctor le prend
            false          // isBaseChain
        );
    }

    function testFork_SimpleOwner() public view {
        assertEq(factory.owner(), address(this), "owner should be test contract");
    }

    // Exemple: changer le hook sur fork
    function testFork_UpdateHookAddress() public {
        address newHook = address(0x1234);
        factory.updateHookAddress(newHook);
        // si tu as un getter dans la factory:
        assertEq(factory.hookAddress(), newHook);
    }
}
