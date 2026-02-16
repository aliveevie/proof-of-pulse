// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/WBTCProofOfReserve.sol";
import "../src/PulseGuard.sol";

contract PulseGuardTest is Test {
    WBTCProofOfReserve public por;
    PulseGuard public guard;
    address constant FORWARDER = address(0xF0);
    address constant USER = address(0x1);
    address constant USER2 = address(0x2);

    function setUp() public {
        por = new WBTCProofOfReserve(FORWARDER);
        guard = new PulseGuard(address(por), 70);

        // Fund test users
        vm.deal(USER, 100 ether);
        vm.deal(USER2, 100 ether);

        // Seed with healthy reserve data (collateral ratio > 99%)
        _writeReserve(1000e8, 1000e8, 10000, 9700000, 1000e8, block.timestamp);
    }

    // ================================================================
    // │                        Helpers                                │
    // ================================================================

    function _writeReserve(
        uint256 btcReserve, uint256 wbtcSupply, uint256 ratioBps,
        uint256 priceCents, uint256 clReserve, uint256 ts
    ) internal {
        bytes memory report = abi.encodePacked(
            bytes1(0x01),
            abi.encode(btcReserve, wbtcSupply, ratioBps, priceCents, clReserve, ts)
        );
        vm.prank(FORWARDER);
        por.onReport("", report);
    }

    function _writeRisk(uint8 score, string memory rec, uint256 ts) internal {
        bytes memory report = abi.encodePacked(
            bytes1(0x02),
            abi.encode(score, rec, ts)
        );
        vm.prank(FORWARDER);
        por.onReport("", report);
    }

    // ================================================================
    // │                    Deposit Tests                               │
    // ================================================================

    function test_deposit_whenHealthy() public {
        vm.prank(USER);
        guard.deposit{value: 1 ether}();

        assertEq(guard.deposits(USER), 1 ether);
        assertEq(guard.totalDeposits(), 1 ether);
    }

    function test_deposit_multipleUsers() public {
        vm.prank(USER);
        guard.deposit{value: 2 ether}();

        vm.prank(USER2);
        guard.deposit{value: 3 ether}();

        assertEq(guard.deposits(USER), 2 ether);
        assertEq(guard.deposits(USER2), 3 ether);
        assertEq(guard.totalDeposits(), 5 ether);
    }

    function test_deposit_emitsEvent() public {
        vm.prank(USER);
        vm.expectEmit(true, false, false, true);
        emit PulseGuard.Deposited(USER, 1 ether, 1 ether);
        guard.deposit{value: 1 ether}();
    }

    function test_deposit_revert_zeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(PulseGuard.ZeroDeposit.selector);
        guard.deposit{value: 0}();
    }

    function test_deposit_revert_whenCircuitBreakerActive() public {
        // Make reserves unhealthy and trigger breaker
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);
        guard.checkHealth();
        assertTrue(guard.circuitBreakerActive());

        vm.prank(USER);
        vm.expectRevert(PulseGuard.CircuitBreakerIsActive.selector);
        guard.deposit{value: 1 ether}();
    }

    function test_deposit_revert_whenReservesUnhealthy() public {
        // Set unhealthy reserves (98% collateral)
        _writeReserve(980e8, 1000e8, 9800, 9700000, 980e8, block.timestamp);

        vm.prank(USER);
        vm.expectRevert(PulseGuard.ReservesUnhealthy.selector);
        guard.deposit{value: 1 ether}();
    }

    function test_deposit_revert_whenRiskScoreHigh() public {
        // Set high AI risk score
        _writeRisk(85, "Critical risk detected", block.timestamp);
        guard.checkHealth(); // Triggers breaker

        vm.prank(USER);
        vm.expectRevert(PulseGuard.CircuitBreakerIsActive.selector);
        guard.deposit{value: 1 ether}();
    }

    // ================================================================
    // │                   Withdraw Tests                               │
    // ================================================================

    function test_withdraw_full() public {
        vm.prank(USER);
        guard.deposit{value: 5 ether}();

        vm.prank(USER);
        guard.withdraw(5 ether);

        assertEq(guard.deposits(USER), 0);
        assertEq(guard.totalDeposits(), 0);
    }

    function test_withdraw_partial() public {
        vm.prank(USER);
        guard.deposit{value: 5 ether}();

        vm.prank(USER);
        guard.withdraw(2 ether);

        assertEq(guard.deposits(USER), 3 ether);
        assertEq(guard.totalDeposits(), 3 ether);
    }

    function test_withdraw_emitsEvent() public {
        vm.prank(USER);
        guard.deposit{value: 5 ether}();

        vm.prank(USER);
        vm.expectEmit(true, false, false, true);
        emit PulseGuard.Withdrawn(USER, 2 ether, 3 ether);
        guard.withdraw(2 ether);
    }

    function test_withdraw_alwaysAllowed_whenCircuitBreakerActive() public {
        // Deposit first while healthy
        vm.prank(USER);
        guard.deposit{value: 5 ether}();

        // Trip circuit breaker
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);
        guard.checkHealth();
        assertTrue(guard.circuitBreakerActive());

        // Withdraw should STILL work — user funds never locked
        vm.prank(USER);
        guard.withdraw(5 ether);
        assertEq(guard.deposits(USER), 0);
    }

    function test_withdraw_alwaysAllowed_whenUnhealthy() public {
        vm.prank(USER);
        guard.deposit{value: 5 ether}();

        // Make unhealthy
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);

        // Withdraw still works
        vm.prank(USER);
        guard.withdraw(5 ether);
        assertEq(guard.deposits(USER), 0);
    }

    function test_withdraw_revert_insufficientBalance() public {
        vm.prank(USER);
        guard.deposit{value: 1 ether}();

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(
            PulseGuard.InsufficientBalance.selector, 2 ether, 1 ether
        ));
        guard.withdraw(2 ether);
    }

    // ================================================================
    // │                  Circuit Breaker Tests                         │
    // ================================================================

    function test_checkHealth_triggersOnUnhealthy() public {
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);

        vm.expectEmit(false, false, false, true);
        emit PulseGuard.CircuitBreakerTriggered(8000, 0, "Reserve collateral ratio below 99%");
        bool triggered = guard.checkHealth();

        assertTrue(triggered);
        assertTrue(guard.circuitBreakerActive());
        assertGt(guard.breakerTriggeredAt(), 0);
    }

    function test_checkHealth_triggersOnHighRiskScore() public {
        // Reserves healthy but AI says risk is high
        _writeRisk(75, "Anomaly detected in reserve pattern", block.timestamp);

        vm.expectEmit(false, false, false, true);
        emit PulseGuard.CircuitBreakerTriggered(10000, 75, "AI risk score exceeds threshold");
        bool triggered = guard.checkHealth();

        assertTrue(triggered);
        assertTrue(guard.circuitBreakerActive());
    }

    function test_checkHealth_noTriggerWhenHealthy() public {
        _writeRisk(30, "Low risk", block.timestamp);

        bool triggered = guard.checkHealth();
        assertFalse(triggered);
        assertFalse(guard.circuitBreakerActive());
    }

    function test_checkHealth_noTriggerWhenAlreadyActive() public {
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);
        guard.checkHealth();
        assertTrue(guard.circuitBreakerActive());

        // Calling again should return false (already active)
        bool triggered = guard.checkHealth();
        assertFalse(triggered);
    }

    function test_checkHealth_riskBelowThreshold_noTrigger() public {
        // Risk score exactly at threshold - 1
        _writeRisk(69, "Moderate risk", block.timestamp);

        bool triggered = guard.checkHealth();
        assertFalse(triggered);
        assertFalse(guard.circuitBreakerActive());
    }

    function test_checkHealth_riskExactlyAtThreshold_triggers() public {
        // Risk score exactly at threshold (70)
        _writeRisk(70, "High risk detected", block.timestamp);

        bool triggered = guard.checkHealth();
        assertTrue(triggered);
        assertTrue(guard.circuitBreakerActive());
    }

    // ================================================================
    // │                   Reset Tests                                  │
    // ================================================================

    function test_resetCircuitBreaker() public {
        // Trip it
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);
        guard.checkHealth();
        assertTrue(guard.circuitBreakerActive());

        // Restore health
        _writeReserve(1000e8, 1000e8, 10000, 9700000, 1000e8, block.timestamp);

        // Owner resets
        vm.expectEmit(false, false, false, true);
        emit PulseGuard.CircuitBreakerReset(10000);
        guard.resetCircuitBreaker();
        assertFalse(guard.circuitBreakerActive());
    }

    function test_resetCircuitBreaker_revert_notOwner() public {
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);
        guard.checkHealth();

        _writeReserve(1000e8, 1000e8, 10000, 9700000, 1000e8, block.timestamp);

        vm.prank(USER);
        vm.expectRevert(PulseGuard.OnlyOwner.selector);
        guard.resetCircuitBreaker();
    }

    function test_resetCircuitBreaker_revert_stillUnhealthy() public {
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);
        guard.checkHealth();

        // Try to reset without restoring health
        vm.expectRevert(PulseGuard.ReservesStillUnhealthy.selector);
        guard.resetCircuitBreaker();
    }

    function test_depositsResumeAfterReset() public {
        // Trip breaker
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);
        guard.checkHealth();

        // Restore and reset
        _writeReserve(1000e8, 1000e8, 10000, 9700000, 1000e8, block.timestamp);
        guard.resetCircuitBreaker();

        // Deposits work again
        vm.prank(USER);
        guard.deposit{value: 1 ether}();
        assertEq(guard.deposits(USER), 1 ether);
    }

    // ================================================================
    // │                    Threshold Tests                             │
    // ================================================================

    function test_setRiskThreshold() public {
        vm.expectEmit(false, false, false, true);
        emit PulseGuard.RiskThresholdUpdated(70, 50);
        guard.setRiskThreshold(50);
        assertEq(guard.riskThreshold(), 50);
    }

    function test_setRiskThreshold_revert_notOwner() public {
        vm.prank(USER);
        vm.expectRevert(PulseGuard.OnlyOwner.selector);
        guard.setRiskThreshold(50);
    }

    function test_setRiskThreshold_revert_zero() public {
        vm.expectRevert(PulseGuard.InvalidThreshold.selector);
        guard.setRiskThreshold(0);
    }

    function test_setRiskThreshold_revert_above100() public {
        vm.expectRevert(PulseGuard.InvalidThreshold.selector);
        guard.setRiskThreshold(101);
    }

    // ================================================================
    // │                     View Tests                                 │
    // ================================================================

    function test_getVaultStatus() public {
        vm.prank(USER);
        guard.deposit{value: 3 ether}();

        (
            uint256 vaultTotal,
            bool isHealthy,
            bool breakerActive,
            uint8 riskScore,
            uint256 ratioBps
        ) = guard.getVaultStatus();

        assertEq(vaultTotal, 3 ether);
        assertTrue(isHealthy);
        assertFalse(breakerActive);
        assertEq(riskScore, 0);
        assertEq(ratioBps, 10000);
    }

    function test_depositsAllowed_true() public view {
        assertTrue(guard.depositsAllowed());
    }

    function test_depositsAllowed_false_breaker() public {
        _writeReserve(800e8, 1000e8, 8000, 9700000, 800e8, block.timestamp);
        guard.checkHealth();
        assertFalse(guard.depositsAllowed());
    }

    function test_depositsAllowed_false_unhealthy() public {
        _writeReserve(980e8, 1000e8, 9800, 9700000, 980e8, block.timestamp);
        assertFalse(guard.depositsAllowed());
    }

    // ================================================================
    // │                  Integration Scenario                          │
    // ================================================================

    function test_fullScenario_healthyToUnhealthyAndBack() public {
        // 1. Healthy: users deposit
        vm.prank(USER);
        guard.deposit{value: 5 ether}();
        vm.prank(USER2);
        guard.deposit{value: 3 ether}();
        assertEq(guard.totalDeposits(), 8 ether);

        // 2. PoR detects undercollateralization
        _writeReserve(900e8, 1000e8, 9000, 9700000, 900e8, block.timestamp);
        bool triggered = guard.checkHealth();
        assertTrue(triggered);

        // 3. New deposits blocked
        vm.prank(USER);
        vm.expectRevert(PulseGuard.CircuitBreakerIsActive.selector);
        guard.deposit{value: 1 ether}();

        // 4. Withdrawals still work
        vm.prank(USER2);
        guard.withdraw(3 ether);
        assertEq(guard.totalDeposits(), 5 ether);

        // 5. Reserves restored
        _writeReserve(1000e8, 1000e8, 10000, 9700000, 1000e8, block.timestamp);

        // 6. Owner resets circuit breaker
        guard.resetCircuitBreaker();
        assertFalse(guard.circuitBreakerActive());

        // 7. Deposits resume
        vm.prank(USER2);
        guard.deposit{value: 2 ether}();
        assertEq(guard.totalDeposits(), 7 ether);
    }

    function test_revert_directEthTransfer() public {
        vm.prank(USER);
        vm.expectRevert("Use deposit()");
        (bool sent,) = address(guard).call{value: 1 ether}("");
        // suppress unused variable warning
        sent;
    }
}
