// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReceiverTemplate} from "./interfaces/ReceiverTemplate.sol";

/// @title WBTCProofOfReserve - Cross-chain WBTC Proof of Reserve consumer
/// @notice Receives verified PoR data from CRE workflows and stores reserve/risk snapshots
contract WBTCProofOfReserve is ReceiverTemplate {
    // ================================================================
    // │                          Structs                              │
    // ================================================================

    struct ReserveData {
        uint256 btcReserveSats;
        uint256 wbtcSupplySats;
        uint256 collateralRatioBps;
        uint256 btcUsdPriceCents;
        uint256 chainlinkReserveSats;
        uint256 timestamp;
    }

    struct RiskData {
        uint8 score;
        string recommendation;
        uint256 timestamp;
    }

    // ================================================================
    // │                           State                               │
    // ================================================================

    ReserveData public latestReserve;
    ReserveData[] public reserveHistory;
    RiskData public latestRisk;

    // ================================================================
    // │                          Events                               │
    // ================================================================

    event ReserveUpdated(
        uint256 btcReserveSats,
        uint256 wbtcSupplySats,
        uint256 collateralRatioBps,
        uint256 timestamp
    );
    event UndercollateralizedAlert(uint256 collateralRatioBps, uint256 timestamp);
    event ChainlinkDivergenceAlert(uint256 ourReserve, uint256 clReserve, uint256 timestamp);
    event RiskUpdated(uint8 score, string recommendation, uint256 timestamp);
    event AuditRequested(uint256 indexed auditId);

    // ================================================================
    // │                        Constructor                            │
    // ================================================================

    /// @param forwarder CRE KeystoneForwarder address on target chain
    constructor(address forwarder) ReceiverTemplate(forwarder) {}

    // ================================================================
    // │                     Report Routing                            │
    // ================================================================

    /// @dev Routes reports based on prefix byte: 0x01 = reserve, 0x02 = risk
    function _processReport(bytes calldata report) internal override {
        require(report.length > 0, "Empty report");
        bytes1 prefix = report[0];
        bytes calldata payload = report[1:];

        if (prefix == 0x01) {
            _updateReserve(payload);
        } else if (prefix == 0x02) {
            _updateRisk(payload);
        } else {
            revert("Unknown report prefix");
        }
    }

    // ================================================================
    // │                    Reserve Update                             │
    // ================================================================

    function _updateReserve(bytes calldata payload) internal {
        (
            uint256 btcReserveSats,
            uint256 wbtcSupplySats,
            uint256 collateralRatioBps,
            uint256 btcUsdPriceCents,
            uint256 chainlinkReserveSats,
            uint256 timestamp
        ) = abi.decode(payload, (uint256, uint256, uint256, uint256, uint256, uint256));

        latestReserve = ReserveData({
            btcReserveSats: btcReserveSats,
            wbtcSupplySats: wbtcSupplySats,
            collateralRatioBps: collateralRatioBps,
            btcUsdPriceCents: btcUsdPriceCents,
            chainlinkReserveSats: chainlinkReserveSats,
            timestamp: timestamp
        });
        reserveHistory.push(latestReserve);

        emit ReserveUpdated(btcReserveSats, wbtcSupplySats, collateralRatioBps, timestamp);

        if (collateralRatioBps < 10000) {
            emit UndercollateralizedAlert(collateralRatioBps, timestamp);
        }

        if (chainlinkReserveSats > 0) {
            uint256 diff = btcReserveSats > chainlinkReserveSats
                ? btcReserveSats - chainlinkReserveSats
                : chainlinkReserveSats - btcReserveSats;
            if (diff * 100 > chainlinkReserveSats * 5) {
                emit ChainlinkDivergenceAlert(btcReserveSats, chainlinkReserveSats, timestamp);
            }
        }
    }

    // ================================================================
    // │                      Risk Update                              │
    // ================================================================

    function _updateRisk(bytes calldata payload) internal {
        (uint8 score, string memory recommendation, uint256 timestamp) =
            abi.decode(payload, (uint8, string, uint256));

        latestRisk = RiskData({score: score, recommendation: recommendation, timestamp: timestamp});

        emit RiskUpdated(score, recommendation, timestamp);
    }

    // ================================================================
    // │                      Public Views                             │
    // ================================================================

    function isHealthy() external view returns (bool) {
        return latestReserve.collateralRatioBps >= 9900;
    }

    function getLatestReserve() external view returns (ReserveData memory) {
        return latestReserve;
    }

    function getLatestRisk() external view returns (uint8, string memory, uint256) {
        return (latestRisk.score, latestRisk.recommendation, latestRisk.timestamp);
    }

    function getReserveValueUsd() external view returns (uint256) {
        return (latestReserve.btcReserveSats * latestReserve.btcUsdPriceCents) / 1e8;
    }

    function getReserveHistoryLength() external view returns (uint256) {
        return reserveHistory.length;
    }

    // ================================================================
    // │                     Public Actions                            │
    // ================================================================

    /// @notice Request an AI-powered audit (emits event for CRE Log Trigger)
    function requestAudit(uint256 auditId) external {
        emit AuditRequested(auditId);
    }
}
