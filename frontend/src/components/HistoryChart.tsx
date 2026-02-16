import { useState } from "react";
import {
  ResponsiveContainer,
  ComposedChart,
  Area,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ReferenceLine,
  Legend,
} from "recharts";
import type { HistoryPoint } from "../hooks/useContracts";

interface Props {
  history: HistoryPoint[];
}

type ViewMode = "ratio" | "reserves" | "price";

const HEALTH_THRESHOLD = 9900;

function formatTime(ts: number): string {
  return new Date(ts * 1000).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatNumber(n: number): string {
  return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
}

export function HistoryChart({ history }: Props) {
  const [view, setView] = useState<ViewMode>("ratio");

  if (history.length === 0) {
    return (
      <div className="card full-width">
        <h2>Reserve History</h2>
        <div className="chart-empty">
          No historical data yet. Run a CRE workflow simulation with{" "}
          <code>--broadcast</code> to write data on-chain.
        </div>
      </div>
    );
  }

  const data = history.map((p) => ({
    ...p,
    time: formatTime(p.timestamp),
    ratioPercent: p.collateralRatioBps / 100,
  }));

  return (
    <div className="card full-width">
      <h2>
        Reserve History
        <span className="chart-count">{history.length} snapshots on-chain</span>
      </h2>

      <div className="chart-tabs">
        <button
          className={`chart-tab ${view === "ratio" ? "active" : ""}`}
          onClick={() => setView("ratio")}
        >
          Collateral Ratio
        </button>
        <button
          className={`chart-tab ${view === "reserves" ? "active" : ""}`}
          onClick={() => setView("reserves")}
        >
          BTC Reserves vs WBTC Supply
        </button>
        <button
          className={`chart-tab ${view === "price" ? "active" : ""}`}
          onClick={() => setView("price")}
        >
          BTC Price
        </button>
      </div>

      <div className="chart-container">
        <ResponsiveContainer width="100%" height={280}>
          {view === "ratio" ? (
            <ComposedChart data={data} margin={{ top: 10, right: 20, bottom: 0, left: 10 }}>
              <defs>
                <linearGradient id="ratioGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#1e2a42" />
              <XAxis dataKey="time" stroke="#8892a6" fontSize={11} />
              <YAxis
                stroke="#8892a6"
                fontSize={11}
                domain={[0, "auto"]}
                tickFormatter={(v: number) => `${v}%`}
              />
              <Tooltip
                contentStyle={{ background: "#131a2b", border: "1px solid #1e2a42", borderRadius: 8, fontSize: 12 }}
                labelStyle={{ color: "#8892a6" }}
                formatter={(value: number | undefined) => [`${(value ?? 0).toFixed(2)}%`, "Collateral Ratio"]}
              />
              <ReferenceLine
                y={99}
                stroke="#22c55e"
                strokeDasharray="6 3"
                label={{ value: "99% Healthy", fill: "#22c55e", fontSize: 11, position: "insideTopRight" }}
              />
              <ReferenceLine
                y={100}
                stroke="#8892a6"
                strokeDasharray="3 3"
                label={{ value: "100% Full", fill: "#8892a6", fontSize: 11, position: "insideBottomRight" }}
              />
              <Area
                type="monotone"
                dataKey="ratioPercent"
                stroke="#3b82f6"
                strokeWidth={2}
                fill="url(#ratioGrad)"
                name="Collateral Ratio"
                dot={{ r: 4, fill: "#3b82f6" }}
              />
            </ComposedChart>
          ) : view === "reserves" ? (
            <ComposedChart data={data} margin={{ top: 10, right: 20, bottom: 0, left: 10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#1e2a42" />
              <XAxis dataKey="time" stroke="#8892a6" fontSize={11} />
              <YAxis
                stroke="#8892a6"
                fontSize={11}
                tickFormatter={(v: number) => `${formatNumber(v)}`}
              />
              <Tooltip
                contentStyle={{ background: "#131a2b", border: "1px solid #1e2a42", borderRadius: 8, fontSize: 12 }}
                labelStyle={{ color: "#8892a6" }}
                formatter={(value: number | undefined, name?: string) => [formatNumber(value ?? 0) + " BTC", name ?? ""]}
              />
              <Legend wrapperStyle={{ fontSize: 11, color: "#8892a6" }} />
              <Line
                type="monotone"
                dataKey="btcReserveBTC"
                stroke="#f97316"
                strokeWidth={2}
                name="BTC Reserves (Blockstream)"
                dot={{ r: 4, fill: "#f97316" }}
              />
              <Line
                type="monotone"
                dataKey="wbtcSupplyBTC"
                stroke="#ef4444"
                strokeWidth={2}
                name="WBTC Supply (Ethereum)"
                dot={{ r: 4, fill: "#ef4444" }}
              />
              <Line
                type="monotone"
                dataKey="chainlinkBTC"
                stroke="#22c55e"
                strokeWidth={2}
                strokeDasharray="5 5"
                name="Chainlink PoR Feed"
                dot={{ r: 4, fill: "#22c55e" }}
              />
            </ComposedChart>
          ) : (
            <ComposedChart data={data} margin={{ top: 10, right: 20, bottom: 0, left: 10 }}>
              <defs>
                <linearGradient id="priceGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#eab308" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#eab308" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#1e2a42" />
              <XAxis dataKey="time" stroke="#8892a6" fontSize={11} />
              <YAxis
                stroke="#8892a6"
                fontSize={11}
                tickFormatter={(v: number) => `$${formatNumber(v)}`}
              />
              <Tooltip
                contentStyle={{ background: "#131a2b", border: "1px solid #1e2a42", borderRadius: 8, fontSize: 12 }}
                labelStyle={{ color: "#8892a6" }}
                formatter={(value: number | undefined) => [`$${formatNumber(value ?? 0)}`, "BTC/USD"]}
              />
              <Area
                type="monotone"
                dataKey="btcPriceUsd"
                stroke="#eab308"
                strokeWidth={2}
                fill="url(#priceGrad)"
                name="BTC Price"
                dot={{ r: 4, fill: "#eab308" }}
              />
            </ComposedChart>
          )}
        </ResponsiveContainer>
      </div>

      <div className="chart-footer">
        {data.length >= 2 && (
          <>
            <span>
              Range: {data[0].time} — {data[data.length - 1].time}
            </span>
            <span className="chart-sep">|</span>
            <span>
              Ratio: {data[0].ratioPercent.toFixed(2)}% &rarr; {data[data.length - 1].ratioPercent.toFixed(2)}%
            </span>
            {view === "ratio" && (
              <>
                <span className="chart-sep">|</span>
                <span className={data[data.length - 1].collateralRatioBps >= HEALTH_THRESHOLD ? "chart-healthy" : "chart-unhealthy"}>
                  {data[data.length - 1].collateralRatioBps >= HEALTH_THRESHOLD ? "Currently Healthy" : "Currently Unhealthy"}
                </span>
              </>
            )}
          </>
        )}
      </div>
    </div>
  );
}
