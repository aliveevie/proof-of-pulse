import type { RiskData } from "../hooks/useContracts";

interface Props {
  risk: RiskData | null;
  onRequestAudit: () => Promise<string | undefined>;
}

export function RiskCard({ risk, onRequestAudit }: Props) {
  const score = risk?.score ?? 0;
  const scoreColor = score <= 25 ? "green" : score <= 50 ? "yellow" : score <= 75 ? "orange" : "red";

  const segments = Array.from({ length: 20 }, (_, i) => {
    const threshold = i * 5;
    const active = threshold < score;
    const color = score <= 25 ? "var(--green)" : score <= 50 ? "var(--yellow)" : score <= 75 ? "var(--orange)" : "var(--red)";
    return (
      <div
        key={i}
        className="risk-seg"
        style={{ background: active ? color : "#1a2332" }}
      />
    );
  });

  return (
    <div className="card">
      <h2>AI Risk Assessment</h2>

      <div className="metric">
        <div className="label">Gemini Risk Score</div>
        <div className={`value ${scoreColor}`}>{score} / 100</div>
        <div className="risk-meter">{segments}</div>
        <div className="sub">0 = Safe | 100 = Critical</div>
      </div>

      <div className="metric">
        <div className="label">Recommendation</div>
        <div className="rec-text">{risk?.recommendation || "No assessment yet"}</div>
      </div>

      <div className="metric">
        <div className="label">Last Updated</div>
        <div className="rec-text">
          {risk && risk.timestamp > 0
            ? new Date(risk.timestamp * 1000).toLocaleString()
            : "Never"}
        </div>
      </div>

      <div className="sep" />
      <button className="btn" onClick={onRequestAudit}>
        Request AI Audit
      </button>
    </div>
  );
}
