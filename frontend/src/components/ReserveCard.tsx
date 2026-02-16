import type { ReserveData } from "../hooks/useContracts";
import { fmtBTC, fmtUSD } from "../utils";

interface Props {
  reserve: ReserveData | null;
  reserveUsd: string;
  historyLength: number;
}

export function ReserveCard({ reserve, reserveUsd, historyLength }: Props) {
  if (!reserve) return <div className="card"><h2>Reserve Health</h2><p className="muted">Loading...</p></div>;

  const ratioBps = reserve.collateralRatioBps;
  const ratioPercent = (ratioBps / 100).toFixed(2);
  const isHealthy = ratioBps >= 9900;
  const barWidth = Math.min(100, ratioBps / 100);
  const barColor = ratioBps >= 9900 ? "var(--green)" : ratioBps >= 5000 ? "var(--yellow)" : "var(--red)";

  const deficit = Number(reserve.wbtcSupplySats) - Number(reserve.btcReserveSats);
  const deficitBTC = deficit > 0 ? (deficit / 1e8).toLocaleString(undefined, { maximumFractionDigits: 2 }) : null;

  return (
    <div className="card">
      <h2>Reserve Health</h2>

      <div className="metric">
        <div className="label">Collateral Ratio</div>
        <div className={`value ${isHealthy ? "green" : ratioBps >= 5000 ? "yellow" : "red"}`}>
          {ratioPercent}%
        </div>
        <div className="bar-container">
          <div className="bar" style={{ width: `${barWidth}%`, background: barColor }} />
        </div>
        <div className="sub">{ratioBps} bps | Threshold: 9900 bps (99%) | {historyLength} snapshots</div>
      </div>

      <div className="metric">
        <div className="label">Health Status</div>
        <span className={`badge ${isHealthy ? "healthy" : "unhealthy"}`}>
          {isHealthy ? "HEALTHY" : "UNHEALTHY"}
        </span>
        {deficitBTC && (
          <span className="deficit-note"> — {deficitBTC} BTC deficit</span>
        )}
      </div>

      <div className="two-col">
        <div className="metric">
          <div className="label">BTC Reserves (Blockstream)</div>
          <div className="value sm">{fmtBTC(reserve.btcReserveSats)}</div>
        </div>
        <div className="metric">
          <div className="label">WBTC Supply (Ethereum)</div>
          <div className="value sm">{fmtBTC(reserve.wbtcSupplySats)}</div>
        </div>
      </div>

      <div className="two-col">
        <div className="metric">
          <div className="label">Chainlink PoR Feed</div>
          <div className="value sm">{fmtBTC(reserve.chainlinkReserveSats)}</div>
        </div>
        <div className="metric">
          <div className="label">BTC Price (CoinGecko)</div>
          <div className="value sm">{fmtUSD(reserve.btcUsdPriceCents)}</div>
        </div>
      </div>

      <div className="metric">
        <div className="label">Reserve Value (USD)</div>
        <div className="value sm">{fmtUSD(reserveUsd)}</div>
      </div>

      {reserve.timestamp > 0 && (
        <div className="sub">
          Last CRE update: {new Date(reserve.timestamp * 1000).toLocaleString()}
        </div>
      )}

      <div className="addr" style={{ marginTop: 4 }}>
        PoR Contract:{" "}
        <a href="https://sepolia.etherscan.io/address/0x4177bF2196151A05A51f7928988afd3Fe7B6e949" target="_blank" rel="noreferrer">
          0x4177bF...6e949
        </a>
      </div>
    </div>
  );
}
