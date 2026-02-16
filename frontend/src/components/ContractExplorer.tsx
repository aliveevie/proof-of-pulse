import { useState } from "react";
import type { ReserveData, RiskData, VaultData } from "../hooks/useContracts";
import { POR_ADDRESS, GUARD_ADDRESS } from "../config/contracts";

interface Props {
  reserve: ReserveData | null;
  risk: RiskData | null;
  vault: VaultData | null;
  reserveUsd: string;
  historyLength: number;
}

interface CallResult {
  fn: string;
  contract: string;
  returns: string;
  value: string;
}

export function ContractExplorer({ reserve, risk, vault, reserveUsd, historyLength }: Props) {
  const [expanded, setExpanded] = useState(false);

  const calls: CallResult[] = [];

  if (reserve) {
    calls.push(
      { fn: "getLatestReserve()", contract: "PoR", returns: "ReserveData", value: JSON.stringify({
        btcReserveSats: reserve.btcReserveSats,
        wbtcSupplySats: reserve.wbtcSupplySats,
        collateralRatioBps: reserve.collateralRatioBps,
        btcUsdPriceCents: reserve.btcUsdPriceCents,
        chainlinkReserveSats: reserve.chainlinkReserveSats,
        timestamp: reserve.timestamp,
      }, null, 2) },
      { fn: "isHealthy()", contract: "PoR", returns: "bool", value: String(reserve.collateralRatioBps >= 9900) },
      { fn: "getReserveValueUsd()", contract: "PoR", returns: "uint256", value: reserveUsd + " (cents)" },
      { fn: "getReserveHistoryLength()", contract: "PoR", returns: "uint256", value: String(historyLength) },
    );
  }

  if (risk) {
    calls.push(
      { fn: "getLatestRisk()", contract: "PoR", returns: "(uint8, string, uint256)", value: JSON.stringify({
        score: risk.score,
        recommendation: risk.recommendation,
        timestamp: risk.timestamp,
      }, null, 2) },
    );
  }

  if (vault) {
    calls.push(
      { fn: "getVaultStatus()", contract: "Guard", returns: "(uint256, bool, bool, uint8, uint256)", value: JSON.stringify({
        vaultTotal: vault.totalDeposits + " wei",
        isHealthy: vault.isHealthy,
        breakerActive: vault.breakerActive,
        currentRiskScore: vault.riskScore,
        currentRatioBps: vault.ratioBps,
      }, null, 2) },
      { fn: "depositsAllowed()", contract: "Guard", returns: "bool", value: String(vault.depositsAllowed) },
      { fn: "riskThreshold()", contract: "Guard", returns: "uint8", value: String(vault.riskThreshold) },
    );
  }

  return (
    <div className="card full-width">
      <h2>
        Contract Data Explorer
        <button
          className="toggle-btn"
          onClick={() => setExpanded(!expanded)}
        >
          {expanded ? "Collapse" : "Expand"} ({calls.length} calls)
        </button>
      </h2>

      {!expanded ? (
        <div className="explorer-summary">
          {calls.length} live contract calls returning data from Sepolia. Click expand to see raw values.
        </div>
      ) : (
        <div className="explorer-grid">
          {calls.map((call, i) => (
            <div key={i} className="explorer-row">
              <div className="explorer-header">
                <span className={`explorer-badge ${call.contract === "PoR" ? "badge-por" : "badge-guard"}`}>
                  {call.contract === "PoR" ? "WBTCProofOfReserve" : "PulseGuard"}
                </span>
                <code className="explorer-fn">{call.fn}</code>
                <span className="explorer-returns">&rarr; {call.returns}</span>
              </div>
              <pre className="explorer-value">{call.value}</pre>
            </div>
          ))}
          <div className="explorer-addrs">
            <div>PoR: <a href={`https://sepolia.etherscan.io/address/${POR_ADDRESS}`} target="_blank" rel="noreferrer">{POR_ADDRESS}</a></div>
            <div>Guard: <a href={`https://sepolia.etherscan.io/address/${GUARD_ADDRESS}`} target="_blank" rel="noreferrer">{GUARD_ADDRESS}</a></div>
          </div>
        </div>
      )}
    </div>
  );
}
