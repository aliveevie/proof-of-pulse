export function fmtBTC(sats: string): string {
  const btc = Number(sats) / 1e8;
  return btc.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " BTC";
}

export function fmtUSD(cents: string): string {
  const usd = Number(cents) / 100;
  return "$" + usd.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
