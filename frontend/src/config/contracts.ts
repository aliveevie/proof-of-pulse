export const SEPOLIA_RPC = "https://ethereum-sepolia-rpc.publicnode.com";
export const SEPOLIA_CHAIN_ID = 11155111;

export const POR_ADDRESS = "0x4177bF2196151A05A51f7928988afd3Fe7B6e949";
export const GUARD_ADDRESS = "0x887dC9BF62755dCbb0A3d93028fCAd741585106E";

export const POR_ABI = [
  "function getLatestReserve() view returns (uint256 btcReserveSats, uint256 wbtcSupplySats, uint256 collateralRatioBps, uint256 btcUsdPriceCents, uint256 chainlinkReserveSats, uint256 timestamp)",
  "function getLatestRisk() view returns (uint8 score, string recommendation, uint256 timestamp)",
  "function isHealthy() view returns (bool)",
  "function getReserveValueUsd() view returns (uint256)",
  "function getReserveHistoryLength() view returns (uint256)",
  "function reserveHistory(uint256 index) view returns (uint256 btcReserveSats, uint256 wbtcSupplySats, uint256 collateralRatioBps, uint256 btcUsdPriceCents, uint256 chainlinkReserveSats, uint256 timestamp)",
  "function requestAudit(uint256 auditId)",
];

export const GUARD_ABI = [
  "function getVaultStatus() view returns (uint256 vaultTotal, bool isHealthy, bool breakerActive, uint8 currentRiskScore, uint256 currentRatioBps)",
  "function depositsAllowed() view returns (bool)",
  "function riskThreshold() view returns (uint8)",
  "function deposits(address) view returns (uint256)",
  "function deposit() payable",
  "function withdraw(uint256 amount)",
  "function checkHealth() returns (bool)",
];
