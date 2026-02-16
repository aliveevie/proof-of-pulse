// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {WBTCProofOfReserve} from "./WBTCProofOfReserve.sol";

/// @title PulseGuard - DeFi Circuit Breaker Powered by ProofPulse PoR Data
/// @notice A WBTC-collateral-aware ETH vault that automatically pauses deposits when
///         ProofPulse detects reserve issues. Demonstrates how DeFi protocols can
///         consume on-chain PoR data to protect users in real time.
/// @dev Reads health status and AI risk scores from WBTCProofOfReserve to gate operations.
///      Withdrawals are never blocked — user safety first.
contract PulseGuard {
    // ================================================================
    // │                          State                                │
    // ================================================================

    /// @notice The ProofPulse PoR contract this guard monitors
    WBTCProofOfReserve public immutable proofOfReserve;

    /// @notice Contract owner (can reset circuit breaker and update thresholds)
    address public owner;

    /// @notice AI risk score threshold — circuit breaker trips if score >= this value
    uint8 public riskThreshold;

    /// @notice Whether the circuit breaker is currently active (deposits paused)
    bool public circuitBreakerActive;

    /// @notice Timestamp when the circuit breaker was last triggered
    uint256 public breakerTriggeredAt;

    /// @notice ETH deposits per user
    mapping(address => uint256) public deposits;

    /// @notice Total ETH deposited in the vault
    uint256 public totalDeposits;

    // ================================================================
    // │                          Events                               │
    // ================================================================

    /// @notice Emitted when the circuit breaker activates due to unhealthy reserves or high risk
    event CircuitBreakerTriggered(
        uint256 collateralRatioBps,
        uint8 riskScore,
        string reason
    );

    /// @notice Emitted when the owner resets the circuit breaker after health is restored
    event CircuitBreakerReset(uint256 collateralRatioBps);

    /// @notice Emitted on successful deposit
    event Deposited(address indexed user, uint256 amount, uint256 totalBalance);

    /// @notice Emitted on successful withdrawal
    event Withdrawn(address indexed user, uint256 amount, uint256 totalBalance);

    /// @notice Emitted when the risk threshold is updated
    event RiskThresholdUpdated(uint8 oldThreshold, uint8 newThreshold);

    // ================================================================
    // │                         Errors                                │
    // ================================================================

    error CircuitBreakerIsActive();
    error ReservesUnhealthy();
    error InsufficientBalance(uint256 requested, uint256 available);
    error TransferFailed();
    error OnlyOwner();
    error ReservesStillUnhealthy();
    error InvalidThreshold();
    error ZeroDeposit();

    // ================================================================
    // │                       Constructor                             │
    // ================================================================

    /// @param _proofOfReserve Address of the deployed WBTCProofOfReserve contract
    /// @param _riskThreshold AI risk score threshold (0-100). Breaker trips if score >= threshold.
    constructor(address _proofOfReserve, uint8 _riskThreshold) {
        if (_riskThreshold == 0 || _riskThreshold > 100) revert InvalidThreshold();
        proofOfReserve = WBTCProofOfReserve(_proofOfReserve);
        riskThreshold = _riskThreshold;
        owner = msg.sender;
    }

    // ================================================================
    // │                      Vault Operations                         │
    // ================================================================

    /// @notice Deposit ETH into the vault. Only allowed when reserves are healthy
    ///         and circuit breaker is not active.
    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();
        if (circuitBreakerActive) revert CircuitBreakerIsActive();
        if (!proofOfReserve.isHealthy()) revert ReservesUnhealthy();

        deposits[msg.sender] += msg.value;
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value, deposits[msg.sender]);
    }

    /// @notice Withdraw ETH from the vault. Always allowed regardless of reserve health
    ///         or circuit breaker status — user funds are never locked.
    /// @param amount Amount of ETH to withdraw (in wei)
    function withdraw(uint256 amount) external {
        uint256 balance = deposits[msg.sender];
        if (amount > balance) revert InsufficientBalance(amount, balance);

        deposits[msg.sender] = balance - amount;
        totalDeposits -= amount;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(msg.sender, amount, deposits[msg.sender]);
    }

    // ================================================================
    // │                    Circuit Breaker Logic                       │
    // ================================================================

    /// @notice Check reserve health and trigger circuit breaker if needed.
    ///         Anyone can call this — permissionless health monitoring.
    /// @return triggered Whether the circuit breaker was triggered by this call
    function checkHealth() external returns (bool triggered) {
        if (circuitBreakerActive) return false;

        WBTCProofOfReserve.ReserveData memory reserve = proofOfReserve.getLatestReserve();
        (uint8 riskScore,,) = proofOfReserve.getLatestRisk();

        if (!proofOfReserve.isHealthy()) {
            circuitBreakerActive = true;
            breakerTriggeredAt = block.timestamp;
            emit CircuitBreakerTriggered(
                reserve.collateralRatioBps,
                riskScore,
                "Reserve collateral ratio below 99%"
            );
            return true;
        }

        if (riskScore >= riskThreshold) {
            circuitBreakerActive = true;
            breakerTriggeredAt = block.timestamp;
            emit CircuitBreakerTriggered(
                reserve.collateralRatioBps,
                riskScore,
                "AI risk score exceeds threshold"
            );
            return true;
        }

        return false;
    }

    /// @notice Reset the circuit breaker. Only callable by owner, and only when
    ///         reserves are verified healthy again.
    function resetCircuitBreaker() external {
        if (msg.sender != owner) revert OnlyOwner();
        if (!proofOfReserve.isHealthy()) revert ReservesStillUnhealthy();

        circuitBreakerActive = false;
        WBTCProofOfReserve.ReserveData memory reserve = proofOfReserve.getLatestReserve();
        emit CircuitBreakerReset(reserve.collateralRatioBps);
    }

    /// @notice Update the AI risk score threshold
    /// @param newThreshold New threshold (1-100)
    function setRiskThreshold(uint8 newThreshold) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (newThreshold == 0 || newThreshold > 100) revert InvalidThreshold();

        uint8 oldThreshold = riskThreshold;
        riskThreshold = newThreshold;
        emit RiskThresholdUpdated(oldThreshold, newThreshold);
    }

    // ================================================================
    // │                         Views                                 │
    // ================================================================

    /// @notice Get the current vault status in a single call
    /// @return vaultTotal Total ETH in vault
    /// @return isHealthy Whether PoR reports healthy reserves
    /// @return breakerActive Whether the circuit breaker is currently tripped
    /// @return currentRiskScore Latest AI risk score from Gemini
    /// @return currentRatioBps Latest collateral ratio in basis points
    function getVaultStatus() external view returns (
        uint256 vaultTotal,
        bool isHealthy,
        bool breakerActive,
        uint8 currentRiskScore,
        uint256 currentRatioBps
    ) {
        WBTCProofOfReserve.ReserveData memory reserve = proofOfReserve.getLatestReserve();
        (uint8 riskScore,,) = proofOfReserve.getLatestRisk();

        return (
            totalDeposits,
            proofOfReserve.isHealthy(),
            circuitBreakerActive,
            riskScore,
            reserve.collateralRatioBps
        );
    }

    /// @notice Check if deposits are currently allowed
    function depositsAllowed() external view returns (bool) {
        return !circuitBreakerActive && proofOfReserve.isHealthy();
    }

    receive() external payable {
        revert("Use deposit()");
    }
}
