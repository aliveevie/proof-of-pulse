import { useState } from "react";
import { useSimulation } from "../hooks/useSimulation";
import type { SimAction } from "../hooks/useSimulation";

interface Props {
  account: string | null;
}

const ACTION_LABELS: Record<SimAction, { label: string; desc: string }> = {
  deposit: {
    label: "Deposit",
    desc: "Test if PulseGuard will accept your deposit given current reserve health",
  },
  withdraw: {
    label: "Withdraw",
    desc: "Test if withdrawal will succeed — always allowed regardless of health",
  },
  checkHealth: {
    label: "Check Health",
    desc: "Simulate circuit breaker evaluation — would it trip right now?",
  },
};

export function TenderlySimulator({ account }: Props) {
  const { simulating, result, simulate, clearResult } = useSimulation();
  const [action, setAction] = useState<SimAction>("deposit");
  const [amount, setAmount] = useState("0.001");

  const handleSimulate = () => {
    simulate(action, account || undefined, amount);
  };

  return (
    <div className="card tenderly-card">
      <h2>
        <span className="tenderly-badge">TENDERLY VNET</span>
        Transaction Simulator
      </h2>
      <p className="sim-desc">
        Preview transactions before executing — powered by Tenderly Virtual
        TestNet. Full EVM simulation with zero gas cost, no state changes.
      </p>

      <div className="sim-actions">
        {(Object.keys(ACTION_LABELS) as SimAction[]).map((a) => (
          <button
            key={a}
            className={`sim-action-btn ${action === a ? "active" : ""}`}
            onClick={() => {
              setAction(a);
              clearResult();
            }}
          >
            {ACTION_LABELS[a].label}
          </button>
        ))}
      </div>

      <div className="sim-action-desc">{ACTION_LABELS[action].desc}</div>

      {action !== "checkHealth" && (
        <div className="sim-input-row">
          <label>Amount (ETH)</label>
          <input
            type="text"
            value={amount}
            onChange={(e) => {
              setAmount(e.target.value);
              clearResult();
            }}
            className="sim-input"
            placeholder="0.001"
          />
        </div>
      )}

      <div className="sim-from">
        <label>From</label>
        <span>
          {account
            ? `${account.slice(0, 8)}...${account.slice(-6)}`
            : "Test address (connect wallet for yours)"}
        </span>
      </div>

      <button
        className="btn sim-btn"
        onClick={handleSimulate}
        disabled={simulating}
      >
        {simulating
          ? "Simulating on Tenderly VNet..."
          : `Simulate ${ACTION_LABELS[action].label}`}
      </button>

      {result && (
        <div
          className={`sim-result ${result.success ? "sim-success" : "sim-revert"}`}
        >
          <div className="sim-result-header">
            <span
              className={`sim-status ${result.success ? "success" : "revert"}`}
            >
              {result.success
                ? "TRANSACTION WOULD SUCCEED"
                : "TRANSACTION WOULD REVERT"}
            </span>
          </div>

          {result.revertReason && (
            <div className="sim-detail">
              <span className="sim-detail-label">Revert Reason</span>
              <code className="sim-code">{result.revertReason}</code>
            </div>
          )}

          {result.gasEstimate && (
            <div className="sim-detail">
              <span className="sim-detail-label">Estimated Gas</span>
              <span className="sim-gas-value">
                {parseInt(result.gasEstimate).toLocaleString()} units
              </span>
            </div>
          )}

          <div className="sim-state">
            <span className="sim-detail-label">Contract State</span>
            <div className="sim-state-grid">
              <div className="sim-state-row">
                <span>depositsAllowed()</span>
                <span
                  className={`badge ${result.statePreview.depositsAllowed ? "healthy" : "unhealthy"}`}
                >
                  {result.statePreview.depositsAllowed ? "OPEN" : "BLOCKED"}
                </span>
              </div>
              <div className="sim-state-row">
                <span>isHealthy()</span>
                <span
                  className={`badge ${result.statePreview.isHealthy ? "healthy" : "unhealthy"}`}
                >
                  {result.statePreview.isHealthy ? "HEALTHY" : "UNHEALTHY"}
                </span>
              </div>
              <div className="sim-state-row">
                <span>Collateral Ratio</span>
                <span>
                  {(result.statePreview.collateralRatio / 100).toFixed(1)}%
                </span>
              </div>
              <div className="sim-state-row">
                <span>Gemini Risk Score</span>
                <span>{result.statePreview.riskScore}/100</span>
              </div>
              <div className="sim-state-row">
                <span>Vault Total</span>
                <span>{result.statePreview.vaultTotal} ETH</span>
              </div>
            </div>
          </div>
        </div>
      )}

      <div className="sim-footer">
        Tenderly Virtual TestNets enable safe transaction simulation with full
        EVM execution — test cross-contract interactions before committing
        on-chain.
      </div>
    </div>
  );
}
