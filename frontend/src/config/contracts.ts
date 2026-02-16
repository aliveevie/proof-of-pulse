export const SEPOLIA_RPC = "https://virtual.sepolia.eu.rpc.tenderly.co/edfcf111-7230-4890-a00d-6955af566bb9";
export const SEPOLIA_CHAIN_ID = 11155111;

export const POR_ADDRESS = "0x3C4f266542EEE824303F39189CdeBF9530FEFd73";
export const GUARD_ADDRESS = "0x97999Af8E10B03A5f8eC8bC8ADFF7B0679b6EA11";

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
