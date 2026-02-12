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

    // ================================================================
    // │                   Reserve Update Tests                        │
    // ================================================================

    function test_updateReserve_storesData() public {
        bytes memory payload = abi.encode(
            uint256(1000e8),  // btcReserveSats
            uint256(900e8),   // wbtcSupplySats
            uint256(11111),   // collateralRatioBps (111.11%)
            uint256(9700000), // btcUsdPriceCents ($97,000)
            uint256(1000e8),  // chainlinkReserveSats
            uint256(1700000000) // timestamp
        );
        bytes memory report = abi.encodePacked(bytes1(0x01), payload);

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
        bytes memory payload = abi.encode(
            uint256(1000e8), uint256(900e8), uint256(11111),
            uint256(9700000), uint256(1000e8), uint256(1700000000)
        );
        bytes memory report = abi.encodePacked(bytes1(0x01), payload);

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.ReserveUpdated(1000e8, 900e8, 11111, 1700000000);
        por.onReport("", report);
    }

    function test_undercollateralizedAlert() public {
        bytes memory payload = abi.encode(
            uint256(800e8),   // btcReserveSats (less than wbtc)
            uint256(1000e8),  // wbtcSupplySats
            uint256(8000),    // collateralRatioBps (80%)
            uint256(9700000), uint256(800e8), uint256(1700000000)
        );
        bytes memory report = abi.encodePacked(bytes1(0x01), payload);

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.UndercollateralizedAlert(8000, 1700000000);
        por.onReport("", report);
    }

    function test_chainlinkDivergenceAlert() public {
        // 10% divergence (> 5% threshold)
        bytes memory payload = abi.encode(
            uint256(1100e8),  // btcReserveSats
            uint256(1000e8),  // wbtcSupplySats
            uint256(11000),   // collateralRatioBps
            uint256(9700000),
            uint256(1000e8),  // chainlinkReserveSats (10% lower)
            uint256(1700000000)
        );
        bytes memory report = abi.encodePacked(bytes1(0x01), payload);

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.ChainlinkDivergenceAlert(1100e8, 1000e8, 1700000000);
        por.onReport("", report);
    }

    function test_noChainlinkDivergenceWhenClose() public {
        // 2% divergence (< 5% threshold) — should NOT emit
        bytes memory payload = abi.encode(
            uint256(1020e8),  // btcReserveSats
            uint256(1000e8),  // wbtcSupplySats
            uint256(10200),   // collateralRatioBps
            uint256(9700000),
            uint256(1000e8),  // chainlinkReserveSats (2% lower)
            uint256(1700000000)
        );
        bytes memory report = abi.encodePacked(bytes1(0x01), payload);

        vm.prank(FORWARDER);
        // Record logs to check no divergence alert was emitted
        vm.recordLogs();
        por.onReport("", report);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Should only have ReserveUpdated, not ChainlinkDivergenceAlert
        bool hasDivergence = false;
        bytes32 divergenceSig = keccak256("ChainlinkDivergenceAlert(uint256,uint256,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == divergenceSig) {
                hasDivergence = true;
            }
        }
        assertFalse(hasDivergence);
    }

    // ================================================================
    // │                     Risk Update Tests                         │
    // ================================================================

    function test_updateRisk_storesData() public {
        bytes memory payload = abi.encode(uint8(75), "High reserve drift detected", uint256(1700000000));
        bytes memory report = abi.encodePacked(bytes1(0x02), payload);

        vm.prank(FORWARDER);
        por.onReport("", report);

        (uint8 score, string memory rec, uint256 ts) = por.getLatestRisk();
        assertEq(score, 75);
        assertEq(rec, "High reserve drift detected");
        assertEq(ts, 1700000000);
    }

    function test_updateRisk_emitsEvent() public {
        bytes memory payload = abi.encode(uint8(25), "Low risk", uint256(1700000000));
        bytes memory report = abi.encodePacked(bytes1(0x02), payload);

        vm.prank(FORWARDER);
        vm.expectEmit(false, false, false, true);
        emit WBTCProofOfReserve.RiskUpdated(25, "Low risk", 1700000000);
        por.onReport("", report);
    }

    // ================================================================
    // │                      View Tests                               │
    // ================================================================

    function test_isHealthy_true() public {
        bytes memory payload = abi.encode(
            uint256(1000e8), uint256(1000e8), uint256(10000),
            uint256(9700000), uint256(1000e8), uint256(1700000000)
        );
        bytes memory report = abi.encodePacked(bytes1(0x01), payload);

        vm.prank(FORWARDER);
        por.onReport("", report);

        assertTrue(por.isHealthy());
    }

    function test_isHealthy_false() public {
        bytes memory payload = abi.encode(
            uint256(980e8), uint256(1000e8), uint256(9800),
            uint256(9700000), uint256(980e8), uint256(1700000000)
        );
        bytes memory report = abi.encodePacked(bytes1(0x01), payload);

        vm.prank(FORWARDER);
        por.onReport("", report);

        assertFalse(por.isHealthy());
    }

    function test_getReserveValueUsd() public {
        // 1000 BTC at $97,000 = $97,000,000
        bytes memory payload = abi.encode(
            uint256(1000e8), uint256(1000e8), uint256(10000),
            uint256(9700000), // $97,000 in cents
            uint256(1000e8), uint256(1700000000)
        );
        bytes memory report = abi.encodePacked(bytes1(0x01), payload);

        vm.prank(FORWARDER);
        por.onReport("", report);

        // 1000e8 * 9700000 / 1e8 = 9700000 * 1000 = 9,700,000,000 cents? No...
        // Actually: (1000 * 1e8) * 9700000 / 1e8 = 1000 * 9700000 = 9,700,000,000
        // That's $97,000,000 in cents = $97M which is correct for 1000 BTC * $97k
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

    // ================================================================
    // │                   Access Control Tests                        │
    // ================================================================

    function test_revert_nonForwarder() public {
        bytes memory report = abi.encodePacked(bytes1(0x01), abi.encode(
            uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)
        ));

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
            bytes memory payload = abi.encode(
                uint256(i * 100e8), uint256(100e8), uint256(i * 10000),
                uint256(9700000), uint256(i * 100e8), uint256(1700000000 + i)
            );
            bytes memory report = abi.encodePacked(bytes1(0x01), payload);
            vm.prank(FORWARDER);
            por.onReport("", report);
        }

        assertEq(por.getReserveHistoryLength(), 3);
    }
}
