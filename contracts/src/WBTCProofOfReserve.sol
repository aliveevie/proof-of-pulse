// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReceiverTemplate} from "./interfaces/ReceiverTemplate.sol";

/// @title WBTCProofOfReserve - Cross-chain WBTC Proof of Reserve consumer
/// @notice Receives verified PoR data from CRE workflows and stores reserve/risk snapshots on-chain.
///         Monitors collateral health by comparing BTC reserves against WBTC supply and the
///         Chainlink PoR feed, emitting alerts on undercollateralization or data divergence.
/// @dev Report routing uses a prefix byte: 0x01 = reserve update, 0x02 = AI risk update.
///      Only the CRE KeystoneForwarder can call onReport() (enforced by ReceiverTemplate).
contract WBTCProofOfReserve is ReceiverTemplate {
    // ================================================================
    // │                          Structs                              │
    // ================================================================

    /// @notice Snapshot of WBTC reserve health at a point in time
    /// @param btcReserveSats BTC held in custody addresses (satoshis, from Blockstream API)
    /// @param wbtcSupplySats WBTC ERC-20 totalSupply on Ethereum (satoshi-equivalent, 8 decimals)
    /// @param collateralRatioBps Ratio of BTC reserves to WBTC supply in basis points (10000 = 100%)
    /// @param btcUsdPriceCents BTC/USD price in cents (from CoinGecko)
    /// @param chainlinkReserveSats BTC reserve value reported by the Chainlink PoR feed
    /// @param timestamp Unix timestamp of the observation (from blockchain, not wall clock)
    struct ReserveData {
        uint256 btcReserveSats;
        uint256 wbtcSupplySats;
        uint256 collateralRatioBps;
        uint256 btcUsdPriceCents;
        uint256 chainlinkReserveSats;
        uint256 timestamp;
    }

    /// @notice AI-generated risk assessment from Gemini analysis
    /// @param score Risk score 0-100 (0 = safe, 100 = critical)
    /// @param recommendation One-sentence action recommendation from Gemini
    /// @param timestamp Unix timestamp of the assessment
    struct RiskData {
        uint8 score;
        string recommendation;
        uint256 timestamp;
    }

    // ================================================================
    // │                           State                               │
    // ================================================================

    /// @notice Most recent reserve snapshot
    ReserveData public latestReserve;

    /// @notice Append-only history of all reserve snapshots
    ReserveData[] public reserveHistory;

    /// @notice Most recent AI risk assessment
    RiskData public latestRisk;

    // ================================================================
    // │                          Events                               │
    // ================================================================

    /// @notice Emitted on every successful reserve update
    event ReserveUpdated(
        uint256 btcReserveSats,
        uint256 wbtcSupplySats,
        uint256 collateralRatioBps,
        uint256 timestamp
    );

    /// @notice Emitted when collateral ratio drops below 100% (10000 bps)
    event UndercollateralizedAlert(uint256 collateralRatioBps, uint256 timestamp);

    /// @notice Emitted when our BTC reserve diverges from Chainlink's feed by more than 5%
    event ChainlinkDivergenceAlert(uint256 ourReserve, uint256 clReserve, uint256 timestamp);

    /// @notice Emitted on every AI risk assessment update
    event RiskUpdated(uint8 score, string recommendation, uint256 timestamp);

    /// @notice Emitted when a user requests an AI-powered audit (triggers CRE Log Trigger)
    event AuditRequested(uint256 indexed auditId);

    // ================================================================
    // │                        Constructor                            │
    // ================================================================

    /// @param forwarder CRE KeystoneForwarder address on the target chain
    constructor(address forwarder) ReceiverTemplate(forwarder) {}

    // ================================================================
    // │                     Report Routing                            │
    // ================================================================

    /// @dev Routes incoming CRE reports based on prefix byte.
    ///      0x01 → reserve data update, 0x02 → AI risk assessment update.
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

    /// @dev Decodes and stores a reserve snapshot, emitting alerts if thresholds are breached.
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

        // Check for >5% divergence between our reserve and Chainlink's feed.
        // Uses division instead of multiplication to avoid potential overflow:
        // diff > chainlinkReserveSats * 5 / 100  ⟹  diff > chainlinkReserveSats / 20
        if (chainlinkReserveSats > 0) {
            uint256 diff = btcReserveSats > chainlinkReserveSats
                ? btcReserveSats - chainlinkReserveSats
                : chainlinkReserveSats - btcReserveSats;
            if (diff > chainlinkReserveSats / 20) {
                emit ChainlinkDivergenceAlert(btcReserveSats, chainlinkReserveSats, timestamp);
            }
        }
    }

    // ================================================================
    // │                      Risk Update                              │
    // ================================================================

    /// @dev Decodes and stores an AI risk assessment from Gemini.
    function _updateRisk(bytes calldata payload) internal {
        (uint8 score, string memory recommendation, uint256 timestamp) =
            abi.decode(payload, (uint8, string, uint256));

        latestRisk = RiskData({score: score, recommendation: recommendation, timestamp: timestamp});

        emit RiskUpdated(score, recommendation, timestamp);
    }

    // ================================================================
    // │                      Public Views                             │
    // ================================================================

    /// @notice Returns true if the latest collateral ratio is >= 99%.
    /// @dev The 1% buffer (9900 bps vs 10000) accounts for minor timing differences
    ///      between BTC block confirmation and WBTC mint/burn settlement.
    function isHealthy() external view returns (bool) {
        return latestReserve.collateralRatioBps >= 9900;
    }

    /// @notice Returns the most recent reserve snapshot
    function getLatestReserve() external view returns (ReserveData memory) {
        return latestReserve;
    }

    /// @notice Returns the most recent AI risk assessment
    function getLatestRisk() external view returns (uint8, string memory, uint256) {
        return (latestRisk.score, latestRisk.recommendation, latestRisk.timestamp);
    }

    /// @notice Returns the USD value of BTC reserves in cents
    /// @dev Calculation: (satoshis × price_cents) / 1e8 = reserve value in cents
    function getReserveValueUsd() external view returns (uint256) {
        return (latestReserve.btcReserveSats * latestReserve.btcUsdPriceCents) / 1e8;
    }

    /// @notice Returns the number of historical reserve snapshots stored
    function getReserveHistoryLength() external view returns (uint256) {
        return reserveHistory.length;
    }

    // ================================================================
    // │                     Public Actions                            │
    // ================================================================

    /// @notice Request an AI-powered audit via Gemini. Emits AuditRequested which
    ///         the CRE Log Trigger monitors to kick off Handler 2 (risk assessment).
    /// @param auditId Caller-chosen identifier for tracking the audit request
    function requestAudit(uint256 auditId) external {
        emit AuditRequested(auditId);
    }
}
