import { ethers } from "ethers";
import type { VaultData } from "../hooks/useContracts";
import { GUARD_ADDRESS } from "../config/contracts";

interface Props {
  vault: VaultData | null;
  account: string | null;
  walletBalance: string;
  onDeposit: () => void;
  onWithdraw: () => void;
  onCheckHealth: () => void;
  onConnect: () => void;
}

export function VaultCard({ vault, account, walletBalance, onDeposit, onWithdraw, onCheckHealth, onConnect }: Props) {
  if (!vault) return <div className="card"><h2>PulseGuard Vault</h2><p className="muted">Loading...</p></div>;

  const blockedReason = !vault.depositsAllowed
    ? !vault.isHealthy
      ? `Reserves unhealthy (${(vault.ratioBps / 100).toFixed(1)}% < 99% threshold)`
      : vault.breakerActive
        ? "Circuit breaker tripped — owner must reset after health restores"
        : "Unknown"
    : null;

  return (
    <div className="card">
      <h2>PulseGuard Vault</h2>

      <div className="two-col">
        <div className="metric">
          <div className="label">Total Deposits</div>
          <div className="value sm">{ethers.utils.formatEther(vault.totalDeposits)} ETH</div>
        </div>
        <div className="metric">
          <div className="label">Circuit Breaker</div>
          <span className={`badge ${vault.breakerActive ? "unhealthy" : "healthy"}`}>
            {vault.breakerActive ? "ACTIVE" : "INACTIVE"}
          </span>
        </div>
      </div>

      <div className="two-col">
        <div className="metric">
          <div className="label">Deposits</div>
          <span className={`badge ${vault.depositsAllowed ? "healthy" : "unhealthy"}`}>
            {vault.depositsAllowed ? "OPEN" : "BLOCKED"}
          </span>
        </div>
        <div className="metric">
          <div className="label">Risk Threshold</div>
          <div className="value sm">&ge; {vault.riskThreshold} triggers breaker</div>
        </div>
      </div>

      {blockedReason && (
        <div className="alert-box">
          <div className="alert-title">Deposits blocked — Circuit breaker protecting users</div>
          <div className="alert-detail">{blockedReason}</div>
          <div className="alert-detail" style={{ marginTop: 4 }}>
            This is the DeFi safety feature in action. Withdrawals remain open.
          </div>
        </div>
      )}

      <div className="sep" />

      {!account ? (
        <button className="btn" onClick={onConnect}>
          Connect Wallet
        </button>
      ) : (
        <>
          <div className="metric" style={{ marginBottom: 8 }}>
            <div className="label">Your Wallet</div>
            <div className="value sm">{Number(walletBalance).toFixed(4)} ETH</div>
            <div className="addr">
              {account.slice(0, 8)}...{account.slice(-6)}
            </div>
          </div>

          <div className="two-col">
            <button className="btn" onClick={onDeposit} disabled={!vault.depositsAllowed}>
              Deposit 0.001 ETH
            </button>
            <button className="btn secondary" onClick={onWithdraw}>
              Withdraw All
            </button>
          </div>
          <button className="btn secondary" onClick={onCheckHealth} style={{ marginTop: 4 }}>
            Check Health (triggers breaker if unhealthy)
          </button>

          <div className="metric" style={{ marginTop: 12 }}>
            <div className="label">Your Vault Balance</div>
            <div className="value sm">{ethers.utils.formatEther(vault.userBalance)} ETH</div>
          </div>
        </>
      )}

      <div className="addr" style={{ marginTop: 8 }}>
        PulseGuard: {GUARD_ADDRESS.slice(0, 8)}...{GUARD_ADDRESS.slice(-6)}
      </div>
    </div>
  );
}
