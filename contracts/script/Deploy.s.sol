// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {WBTCProofOfReserve} from "../src/WBTCProofOfReserve.sol";
import {PulseGuard} from "../src/PulseGuard.sol";

/// @title Deploy — Deploys WBTCProofOfReserve + PulseGuard sequentially
/// @notice Used by setup-tenderly.sh for automated Tenderly VNet deployments.
///         FORWARDER_ADDRESS defaults to the Sepolia KeystoneForwarder, which is
///         the CRE-authorized contract that delivers signed reports to receivers.
contract Deploy is Script {
    /// @dev Sepolia KeystoneForwarder — CRE uses this to deliver signed reports
    address constant SEPOLIA_KEYSTONE_FORWARDER = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88;

    function run() external {
        address forwarder = vm.envOr("FORWARDER_ADDRESS", SEPOLIA_KEYSTONE_FORWARDER);
        uint8 riskThreshold = uint8(vm.envOr("RISK_THRESHOLD", uint256(70)));

        vm.startBroadcast();

        WBTCProofOfReserve por = new WBTCProofOfReserve(forwarder);
        new PulseGuard(address(por), riskThreshold);

        vm.stopBroadcast();
    }
}
