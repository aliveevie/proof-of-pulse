import { useContracts } from "./hooks/useContracts";
import { ReserveCard } from "./components/ReserveCard";
import { RiskCard } from "./components/RiskCard";
import { VaultCard } from "./components/VaultCard";
import { HistoryChart } from "./components/HistoryChart";
import { ContractExplorer } from "./components/ContractExplorer";
import { ActivityLog } from "./components/ActivityLog";

export default function App() {
  const {
    reserve,
    risk,
    vault,
    reserveUsd,
    historyLength,
    history,
    loading,
    account,
    walletBalance,
    logs,
    connectWallet,
    refreshAll,
    requestAudit,
    deposit,
    withdraw,
    checkHealth,
  } = useContracts();

  return (
    <div className="app">
      <header className="header">
        <h1>
          Proof<span className="accent">Pulse</span>
        </h1>
        <p>Cross-Chain WBTC Proof of Reserve & DeFi Circuit Breaker — Live on Sepolia</p>
        {reserve && (
          <div className="header-status">
            <span className={`status-dot ${reserve.collateralRatioBps >= 9900 ? "dot-green" : "dot-red"}`} />
            {reserve.collateralRatioBps >= 9900 ? "Reserves Healthy" : "Reserves Unhealthy"} — {(reserve.collateralRatioBps / 100).toFixed(1)}% collateralized
            {reserve.timestamp > 0 && (
              <span className="muted"> | Last update: {new Date(reserve.timestamp * 1000).toLocaleString()}</span>
            )}
          </div>
        )}
      </header>

      <div className="grid">
        <ReserveCard
          reserve={reserve}
          reserveUsd={reserveUsd}
          historyLength={historyLength}
        />
        <RiskCard risk={risk} onRequestAudit={requestAudit} />
        <VaultCard
          vault={vault}
          account={account}
          walletBalance={walletBalance}
          onDeposit={deposit}
          onWithdraw={withdraw}
          onCheckHealth={checkHealth}
          onConnect={connectWallet}
        />
        <HistoryChart history={history} />
        <ContractExplorer
          reserve={reserve}
          risk={risk}
          vault={vault}
          reserveUsd={reserveUsd}
          historyLength={historyLength}
        />
        <ActivityLog logs={logs} loading={loading} onRefresh={refreshAll} />
      </div>
    </div>
  );
}
