interface Props {
  logs: string[];
  loading: boolean;
  onRefresh: () => void;
}

export function ActivityLog({ logs, loading, onRefresh }: Props) {
  return (
    <div className="card full-width">
      <h2>Live Activity</h2>
      <div className="log-container">
        {logs.length === 0 ? (
          <div className="muted">No activity yet...</div>
        ) : (
          logs.map((line, i) => <div key={i}>{line}</div>)
        )}
      </div>
      <button className="btn secondary" onClick={onRefresh} style={{ marginTop: 8 }}>
        {loading ? "Refreshing..." : "Refresh All Data"}
      </button>
    </div>
  );
}
