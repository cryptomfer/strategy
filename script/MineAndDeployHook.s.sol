// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {CC0StrategyHook} from "src/CC0StrategyHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ICC0StrategyFactory, IFeeSplit} from "src/Interfaces.sol";
import {HookPermLib} from "src/utils/HookPermLib.sol";

contract MineAndDeployHook is Script {
    /// @dev Renseigne ici les permissions EXACTES que ton CC0StrategyHook déclare dans getHookPermissions().
    /// IMPORTANT: ces booleans DOIVENT matcher la réalité, sinon le ctor revert.
    function desiredPerms() internal pure returns (HookPermLib.Perms memory p) {
        // Exemple courant: fee sur swap => beforeSwap + afterSwap = true, le reste = false.
        p.beforeSwap = true;
        p.afterSwap  = true;
        // Ajuste si ton hook utilise aussi before/afterAddLiquidity, (after)initialize, donate, etc.
    }

    function run() external {
        // ====== Charge les params depuis .env ou édite ici ======
        // Addresses nécessaires au ctor du hook.
        address managerAddr   = vm.envAddress("POOL_MANAGER");
        address factoryAddr   = vm.envAddress("CC0_FACTORY");
        uint128 feeBips       = uint128(vm.envUint("HOOK_FEE_BIPS")); // ex: 300
        uint128 sellFeeBips   = uint128(vm.envUint("HOOK_SELL_FEE_BIPS")); // ex: 300
        address feeSplitAddr  = vm.envOr("FEE_SPLIT", address(0));

        // Deployer (clé privée)
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // On veut miner un salt tel que l'adresse prédite matche le mask requis.
        HookPermLib.Perms memory perms = desiredPerms();
        uint160 requiredMask = HookPermLib.pack(perms);

        // Build init code hash une seule fois (constructor args inclus)
        bytes memory init = abi.encodePacked(
            type(CC0StrategyHook).creationCode,
            abi.encode(IPoolManager(managerAddr), ICC0StrategyFactory(factoryAddr), feeBips, sellFeeBips, IFeeSplit(feeSplitAddr))
        );
        bytes32 initCodeHash = keccak256(init);

        console.log("Deployer: ", deployer);
        console.logBytes32(initCodeHash);
        console.log("Required mask (hex): ", requiredMask);

        // Mine le salt en pur off-chain (forge script n’a pas de coût gas).
        bytes32 salt;
        address predicted;
        for (uint256 i = 0; ; ++i) {
            salt = bytes32(i);
            predicted = computeCreate2(deployer, salt, initCodeHash);
            if ((uint160(uint256(uint160(predicted))) & requiredMask) == requiredMask) {
                console.log("Found salt:", uint256(salt));
                console.log("Predicted:", predicted);
                break;
            }
            // Optionnel: réduis le bruit de logs
            if (i % 100000 == 0) console.log("Tried:", i);
        }

        // Déploie
        vm.startBroadcast(pk);
        CC0StrategyHook hook = new CC0StrategyHook{salt: salt}(
            IPoolManager(managerAddr),
            ICC0StrategyFactory(factoryAddr),
            feeBips,
            sellFeeBips,
            IFeeSplit(feeSplitAddr)
        );
        vm.stopBroadcast();

        require(address(hook) == predicted, "Address mismatch");
        console.log("Hook deployed at:", address(hook));
    }

    function computeCreate2(address deployer, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        // EIP-1014: keccak256(0xff ++ deployer ++ salt ++ keccak256(init_code))[12:]
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), deployer, salt, initCodeHash
        )))));
    }
}
