// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/WBTCProofOfReserve.sol";

contract WBTCProofOfReserveTest is Test {
    WBTCProofOfReserve public por;
    address constant FORWARDER = address(0xF0);
    address constant USER = address(0x1);

    function setUp() public {
        por = new WBTCProofOfReserve(FORWARDER);
    }

    // Helper to build a reserve report
    function _reserveReport(
        uint256 btcReserve, uint256 wbtcSupply, uint256 ratioBps,
        uint256 priceCents, uint256 clReserve, uint256 ts
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes1(0x01),
            abi.encode(btcReserve, wbtcSupply, ratioBps, priceCents, clReserve, ts)
        );
    }

    // Helper to build a risk report
    function _riskReport(uint8 score, string memory rec, uint256 ts)
        internal pure returns (bytes memory)
    {
        return abi.encodePacked(bytes1(0x02), abi.encode(score, rec, ts));
    }

    // ================================================================
    // │                   Reserve Update Tests                        │
    // ================================================================

    function test_updateReserve_storesData() public {
        bytes memory report = _reserveReport(
            1000e8, 900e8, 11111, 9700000, 1000e8, 1700000000
        );

        vm.prank(FORWARDER);
        por.onReport("", report);

        WBTCProofOfReserve.ReserveData memory data = por.getLatestReserve();
        assertEq(data.btcReserveSats, 1000e8);
        assertEq(data.wbtcSupplySats, 900e8);
        assertEq(data.collateralRatioBps, 11111);
        assertEq(data.btcUsdPriceCents, 9700000);
        assertEq(data.chainlinkReserveSats, 1000e8);
        assertEq(data.timestamp, 1700000000);
        assertEq(por.getReserveHistoryLength(), 1);
    }

    function test_updateReserve_emitsEvent() public {
        bytes memory report = _reserveReport(
            1000e8, 900e8, 11111, 9700000, 1000e8, 1700000000
        );

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.ReserveUpdated(1000e8, 900e8, 11111, 1700000000);
        por.onReport("", report);
    }

    function test_undercollateralizedAlert() public {
        bytes memory report = _reserveReport(
            800e8, 1000e8, 8000, 9700000, 800e8, 1700000000
        );

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.UndercollateralizedAlert(8000, 1700000000);
        por.onReport("", report);
    }

    function test_noUndercollateralizedAlert_atExactly100Percent() public {
        bytes memory report = _reserveReport(
            1000e8, 1000e8, 10000, 9700000, 1000e8, 1700000000
        );

        vm.prank(FORWARDER);
        vm.recordLogs();
        por.onReport("", report);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 alertSig = keccak256("UndercollateralizedAlert(uint256,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != alertSig, "Should not emit undercollateralized at 100%");
        }
    }

    function test_chainlinkDivergenceAlert() public {
        // 10% divergence (> 5% threshold)
        bytes memory report = _reserveReport(
            1100e8, 1000e8, 11000, 9700000, 1000e8, 1700000000
        );

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.ChainlinkDivergenceAlert(1100e8, 1000e8, 1700000000);
        por.onReport("", report);
    }

    function test_noChainlinkDivergenceWhenClose() public {
        // 2% divergence (< 5% threshold) — should NOT emit
        bytes memory report = _reserveReport(
            1020e8, 1000e8, 10200, 9700000, 1000e8, 1700000000
        );

        vm.prank(FORWARDER);
        vm.recordLogs();
        por.onReport("", report);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 divergenceSig = keccak256("ChainlinkDivergenceAlert(uint256,uint256,uint256)");
        bool hasDivergence = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == divergenceSig) {
                hasDivergence = true;
            }
        }
        assertFalse(hasDivergence);
    }

    function test_divergenceAlert_atExactly5Percent() public {
        // Exactly 5% divergence — diff = 50e8, chainlink/20 = 50e8
        // diff > chainlink/20 is false (equal, not greater), so NO alert
        bytes memory report = _reserveReport(
            1050e8, 1000e8, 10500, 9700000, 1000e8, 1700000000
        );

        vm.prank(FORWARDER);
        vm.recordLogs();
        por.onReport("", report);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 divergenceSig = keccak256("ChainlinkDivergenceAlert(uint256,uint256,uint256)");
        bool hasDivergence = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == divergenceSig) {
                hasDivergence = true;
            }
        }
        assertFalse(hasDivergence, "Exactly 5% should not trigger divergence alert");
    }

    function test_divergenceAlert_justAbove5Percent() public {
        // 5.01% divergence — should trigger
        bytes memory report = _reserveReport(
            1051e8, 1000e8, 10510, 9700000, 1000e8, 1700000000
        );

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.ChainlinkDivergenceAlert(1051e8, 1000e8, 1700000000);
        por.onReport("", report);
    }

    function test_divergenceAlert_withLargeValues() public {
        // Test with very large values to ensure no overflow in divergence check
        uint256 clReserve = 15_000_000e8; // 15M BTC in sats
        uint256 ourReserve = 16_000_000e8; // ~6.67% divergence
        bytes memory report = _reserveReport(
            ourReserve, 14_000_000e8, 10714, 9700000, clReserve, 1700000000
        );

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.ChainlinkDivergenceAlert(ourReserve, clReserve, 1700000000);
        por.onReport("", report);
    }

    function test_noDivergenceAlert_whenChainlinkIsZero() public {
        // chainlinkReserveSats = 0 should skip divergence check entirely
        bytes memory report = _reserveReport(
            1000e8, 1000e8, 10000, 9700000, 0, 1700000000
        );

        vm.prank(FORWARDER);
        vm.recordLogs();
        por.onReport("", report);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 divergenceSig = keccak256("ChainlinkDivergenceAlert(uint256,uint256,uint256)");
        bool hasDivergence = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == divergenceSig) {
                hasDivergence = true;
            }
        }
        assertFalse(hasDivergence, "Should skip divergence check when Chainlink is 0");
    }

    function test_zeroReserves() public {
        bytes memory report = _reserveReport(0, 1000e8, 0, 9700000, 0, 1700000000);

        vm.prank(FORWARDER);
        por.onReport("", report);

        WBTCProofOfReserve.ReserveData memory data = por.getLatestReserve();
        assertEq(data.btcReserveSats, 0);
        assertEq(data.collateralRatioBps, 0);
        assertFalse(por.isHealthy());
    }

    // ================================================================
    // │                     Risk Update Tests                         │
    // ================================================================

    function test_updateRisk_storesData() public {
        bytes memory report = _riskReport(75, "High reserve drift detected", 1700000000);

        vm.prank(FORWARDER);
        por.onReport("", report);

        (uint8 score, string memory rec, uint256 ts) = por.getLatestRisk();
        assertEq(score, 75);
        assertEq(rec, "High reserve drift detected");
        assertEq(ts, 1700000000);
    }

    function test_updateRisk_emitsEvent() public {
        bytes memory report = _riskReport(25, "Low risk", 1700000000);

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.RiskUpdated(25, "Low risk", 1700000000);
        por.onReport("", report);
    }

    function test_updateRisk_score0_safe() public {
        bytes memory report = _riskReport(0, "All clear", 1700000000);

        vm.prank(FORWARDER);
        por.onReport("", report);

        (uint8 score,,) = por.getLatestRisk();
        assertEq(score, 0);
    }

    function test_updateRisk_score100_critical() public {
        bytes memory report = _riskReport(100, "Critical: immediate action required", 1700000000);

        vm.prank(FORWARDER);
        por.onReport("", report);

        (uint8 score,,) = por.getLatestRisk();
        assertEq(score, 100);
    }

    function test_updateRisk_longRecommendation() public {
        // 500-char recommendation string
        string memory longRec = "This is a very detailed recommendation from the AI risk assessment engine that covers multiple aspects of the current WBTC reserve health including BTC custody address balances, WBTC supply dynamics, Chainlink feed comparison, historical trend analysis, and potential market impact scenarios. The assessment covers both immediate and medium-term risks. Additional context about market volatility and cross-chain bridge security considerations is also included in this comprehensive review.";
        bytes memory report = _riskReport(60, longRec, 1700000000);

        vm.prank(FORWARDER);
        por.onReport("", report);

        (, string memory rec,) = por.getLatestRisk();
        assertEq(rec, longRec);
    }

    // ================================================================
    // │                      View Tests                               │
    // ================================================================

    function test_isHealthy_true_at100Percent() public {
        bytes memory report = _reserveReport(
            1000e8, 1000e8, 10000, 9700000, 1000e8, 1700000000
        );

        vm.prank(FORWARDER);
        por.onReport("", report);
        assertTrue(por.isHealthy());
    }

    function test_isHealthy_true_at99Percent() public {
        // 99% is the health threshold boundary — should still be healthy
        bytes memory report = _reserveReport(
            990e8, 1000e8, 9900, 9700000, 990e8, 1700000000
        );

        vm.prank(FORWARDER);
        por.onReport("", report);
        assertTrue(por.isHealthy(), "99% should be considered healthy");
    }

    function test_isHealthy_false_below99Percent() public {
        // 98.99% — just below the 99% threshold
        bytes memory report = _reserveReport(
            980e8, 1000e8, 9899, 9700000, 980e8, 1700000000
        );

        vm.prank(FORWARDER);
        por.onReport("", report);
        assertFalse(por.isHealthy(), "98.99% should not be healthy");
    }

    function test_isHealthy_false_beforeAnyUpdate() public {
        // Default state — no reserve data yet, ratio = 0
        assertFalse(por.isHealthy());
    }

    function test_getReserveValueUsd() public {
        // 1000 BTC at $97,000 = $97,000,000
        bytes memory report = _reserveReport(
            1000e8, 1000e8, 10000, 9700000, 1000e8, 1700000000
        );

        vm.prank(FORWARDER);
        por.onReport("", report);

        // (1000e8 sats * 9700000 cents) / 1e8 = 9,700,000,000 cents = $97,000,000
        assertEq(por.getReserveValueUsd(), 9700000000);
    }

    // ================================================================
    // │                    Audit Request Test                          │
    // ================================================================

    function test_requestAudit_emitsEvent() public {
        vm.prank(USER);
        vm.expectEmit(true, false, false, true);
        emit WBTCProofOfReserve.AuditRequested(42);
        por.requestAudit(42);
    }

    function test_requestAudit_anyoneCanCall() public {
        // Verify no access control on requestAudit — it's a public trigger
        address randomUser = address(0xBEEF);
        vm.prank(randomUser);
        vm.expectEmit(true, false, false, true);
        emit WBTCProofOfReserve.AuditRequested(1);
        por.requestAudit(1);
    }

    // ================================================================
    // │                   Access Control Tests                        │
    // ================================================================

    function test_revert_nonForwarder() public {
        bytes memory report = _reserveReport(0, 0, 0, 0, 0, 0);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(
            ReceiverTemplate.UnauthorizedForwarder.selector, USER
        ));
        por.onReport("", report);
    }

    function test_revert_unknownPrefix() public {
        bytes memory report = abi.encodePacked(bytes1(0x03), abi.encode(uint256(0)));

        vm.prank(FORWARDER);
        vm.expectRevert("Unknown report prefix");
        por.onReport("", report);
    }

    function test_revert_emptyReport() public {
        vm.prank(FORWARDER);
        vm.expectRevert("Empty report");
        por.onReport("", "");
    }

    // ================================================================
    // │                   History Accumulation                         │
    // ================================================================

    function test_reserveHistory_accumulates() public {
        for (uint256 i = 1; i <= 3; i++) {
            bytes memory report = _reserveReport(
                i * 100e8, 100e8, i * 10000, 9700000, i * 100e8, 1700000000 + i
            );
            vm.prank(FORWARDER);
            por.onReport("", report);
        }

        assertEq(por.getReserveHistoryLength(), 3);
    }

    function test_reserveHistory_preservesPastEntries() public {
        // Write two updates and verify first entry isn't mutated by second
        bytes memory report1 = _reserveReport(
            500e8, 500e8, 10000, 9700000, 500e8, 1700000001
        );
        bytes memory report2 = _reserveReport(
            600e8, 500e8, 12000, 9800000, 600e8, 1700000002
        );

        vm.prank(FORWARDER);
        por.onReport("", report1);
        vm.prank(FORWARDER);
        por.onReport("", report2);

        // Latest should be the second update
        WBTCProofOfReserve.ReserveData memory latest = por.getLatestReserve();
        assertEq(latest.btcReserveSats, 600e8);

        // History[0] should still be the first update
        (uint256 btcReserve,,,,, uint256 ts) = por.reserveHistory(0);
        assertEq(btcReserve, 500e8);
        assertEq(ts, 1700000001);

        assertEq(por.getReserveHistoryLength(), 2);
    }

    // ================================================================
    // │               Multiple Report Types                           │
    // ================================================================

    function test_reserveAndRisk_independentState() public {
        // Write a reserve update
        bytes memory reserveReport = _reserveReport(
            1000e8, 900e8, 11111, 9700000, 1000e8, 1700000000
        );
        vm.prank(FORWARDER);
        por.onReport("", reserveReport);

        // Write a risk update
        bytes memory riskReport = _riskReport(30, "Moderate risk", 1700000001);
        vm.prank(FORWARDER);
        por.onReport("", riskReport);

        // Both states should be independent
        WBTCProofOfReserve.ReserveData memory reserve = por.getLatestReserve();
        assertEq(reserve.btcReserveSats, 1000e8);

        (uint8 score, string memory rec,) = por.getLatestRisk();
        assertEq(score, 30);
        assertEq(rec, "Moderate risk");
    }
}
