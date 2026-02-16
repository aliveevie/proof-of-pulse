import { useState, useEffect, useCallback } from "react";
import { ethers } from "ethers";
import {
  SEPOLIA_RPC,
  SEPOLIA_CHAIN_ID,
  POR_ADDRESS,
  GUARD_ADDRESS,
  POR_ABI,
  GUARD_ABI,
} from "../config/contracts";

export interface ReserveData {
  btcReserveSats: string;
  wbtcSupplySats: string;
  collateralRatioBps: number;
  btcUsdPriceCents: string;
  chainlinkReserveSats: string;
  timestamp: number;
}

export interface RiskData {
  score: number;
  recommendation: string;
  timestamp: number;
}

export interface VaultData {
  totalDeposits: string;
  isHealthy: boolean;
  breakerActive: boolean;
  riskScore: number;
  ratioBps: number;
  depositsAllowed: boolean;
  riskThreshold: number;
  userBalance: string;
}

export interface HistoryPoint {
  timestamp: number;
  collateralRatioBps: number;
  btcReserveBTC: number;
  wbtcSupplyBTC: number;
  btcPriceUsd: number;
  chainlinkBTC: number;
}

const provider = new ethers.providers.JsonRpcProvider(SEPOLIA_RPC);
const porRead = new ethers.Contract(POR_ADDRESS, POR_ABI, provider);
const guardRead = new ethers.Contract(GUARD_ADDRESS, GUARD_ABI, provider);

export function useContracts() {
  const [reserve, setReserve] = useState<ReserveData | null>(null);
  const [risk, setRisk] = useState<RiskData | null>(null);
  const [vault, setVault] = useState<VaultData | null>(null);
  const [reserveUsd, setReserveUsd] = useState<string>("0");
  const [historyLength, setHistoryLength] = useState(0);
  const [history, setHistory] = useState<HistoryPoint[]>([]);
  const [loading, setLoading] = useState(true);
  const [signer, setSigner] = useState<ethers.Signer | null>(null);
  const [account, setAccount] = useState<string | null>(null);
  const [walletBalance, setWalletBalance] = useState<string>("0");
  const [logs, setLogs] = useState<string[]>([]);

  const addLog = useCallback((msg: string) => {
    const time = new Date().toLocaleTimeString();
    setLogs((prev) => [`[${time}] ${msg}`, ...prev].slice(0, 50));
  }, []);

  const loadHistory = useCallback(async () => {
    try {
      const len = await porRead.getReserveHistoryLength();
      const count = len.toNumber();
      if (count === 0) return;

      const promises = [];
      for (let i = 0; i < count; i++) {
        promises.push(porRead.reserveHistory(i));
      }
      const entries = await Promise.all(promises);

      const points: HistoryPoint[] = entries.map((e) => ({
        timestamp: e.timestamp.toNumber(),
        collateralRatioBps: e.collateralRatioBps.toNumber(),
        btcReserveBTC: Number(e.btcReserveSats.toString()) / 1e8,
        wbtcSupplyBTC: Number(e.wbtcSupplySats.toString()) / 1e8,
        btcPriceUsd: Number(e.btcUsdPriceCents.toString()) / 100,
        chainlinkBTC: Number(e.chainlinkReserveSats.toString()) / 1e8,
      }));

      setHistory(points);
    } catch (e: unknown) {
      addLog("Error loading history: " + (e as Error).message);
    }
  }, [addLog]);

  const loadReserve = useCallback(async () => {
    try {
      const r = await porRead.getLatestReserve();
      const healthy = await porRead.isHealthy();
      const usd = await porRead.getReserveValueUsd();
      const hLen = await porRead.getReserveHistoryLength();

      setReserve({
        btcReserveSats: r.btcReserveSats.toString(),
        wbtcSupplySats: r.wbtcSupplySats.toString(),
        collateralRatioBps: r.collateralRatioBps.toNumber(),
        btcUsdPriceCents: r.btcUsdPriceCents.toString(),
        chainlinkReserveSats: r.chainlinkReserveSats.toString(),
        timestamp: r.timestamp.toNumber(),
      });
      setReserveUsd(usd.toString());
      setHistoryLength(hLen.toNumber());
      void healthy; // used in vault
    } catch (e: unknown) {
      addLog("Error loading reserve: " + (e as Error).message);
    }
  }, [addLog]);

  const loadRisk = useCallback(async () => {
    try {
      const [score, rec, ts] = await porRead.getLatestRisk();
      setRisk({
        score: typeof score === "number" ? score : score.toNumber(),
        recommendation: rec,
        timestamp: ts.toNumber(),
      });
    } catch (e: unknown) {
      addLog("Error loading risk: " + (e as Error).message);
    }
  }, [addLog]);

  const loadVault = useCallback(
    async (addr?: string) => {
      try {
        const [vaultTotal, isHealthy, breakerActive, riskScore, ratioBps] =
          await guardRead.getVaultStatus();
        const allowed = await guardRead.depositsAllowed();
        const threshold = await guardRead.riskThreshold();

        let userBal = "0";
        if (addr) {
          userBal = (await guardRead.deposits(addr)).toString();
        }

        setVault({
          totalDeposits: vaultTotal.toString(),
          isHealthy,
          breakerActive,
          riskScore:
            typeof riskScore === "number" ? riskScore : riskScore.toNumber(),
          ratioBps: ratioBps.toNumber(),
          depositsAllowed: allowed,
          riskThreshold:
            typeof threshold === "number" ? threshold : threshold.toNumber(),
          userBalance: userBal,
        });
      } catch (e: unknown) {
        addLog("Error loading vault: " + (e as Error).message);
      }
    },
    [addLog]
  );

  const refreshAll = useCallback(async () => {
    setLoading(true);
    await Promise.all([
      loadReserve(),
      loadRisk(),
      loadVault(account || undefined),
      loadHistory(),
    ]);
    setLoading(false);
    addLog("Data refreshed");
  }, [loadReserve, loadRisk, loadVault, loadHistory, account, addLog]);

  const connectWallet = useCallback(async () => {
    if (!window.ethereum) {
      addLog("No wallet detected. Install MetaMask.");
      return;
    }
    try {
      const web3Provider = new ethers.providers.Web3Provider(
        window.ethereum as ethers.providers.ExternalProvider
      );
      await web3Provider.send("eth_requestAccounts", []);
      const network = await web3Provider.getNetwork();
      if (network.chainId !== SEPOLIA_CHAIN_ID) {
        addLog("Please switch MetaMask to Sepolia testnet");
        try {
          await (window.ethereum as { request: (args: { method: string; params: unknown[] }) => Promise<void> }).request({
            method: "wallet_switchEthereumChain",
            params: [{ chainId: "0x" + SEPOLIA_CHAIN_ID.toString(16) }],
          });
        } catch {
          return;
        }
      }
      const s = web3Provider.getSigner();
      const addr = await s.getAddress();
      const bal = await web3Provider.getBalance(addr);
      setSigner(s);
      setAccount(addr);
      setWalletBalance(ethers.utils.formatEther(bal));
      addLog("Wallet connected: " + addr.slice(0, 10) + "...");
      addLog("Sepolia ETH balance: " + ethers.utils.formatEther(bal).slice(0, 8) + " ETH");
      await loadVault(addr);
    } catch (e: unknown) {
      addLog("Connect failed: " + (e as Error).message);
    }
  }, [addLog, loadVault]);

  const requestAudit = useCallback(async () => {
    if (!signer) {
      await connectWallet();
      return;
    }
    try {
      const por = new ethers.Contract(POR_ADDRESS, POR_ABI, signer);
      const auditId = Math.floor(Date.now() / 1000);
      addLog("Sending requestAudit()...");
      const tx = await por.requestAudit(auditId);
      addLog("Tx: " + tx.hash.slice(0, 18) + "...");
      await tx.wait();
      addLog("Audit requested! ID=" + auditId + " — CRE Log Trigger will pick this up");
      return tx.hash;
    } catch (e: unknown) {
      const err = e as { reason?: string; message: string };
      addLog("Audit failed: " + (err.reason || err.message));
    }
  }, [signer, connectWallet, addLog]);

  const deposit = useCallback(async () => {
    if (!signer) {
      await connectWallet();
      return;
    }
    try {
      const guard = new ethers.Contract(GUARD_ADDRESS, GUARD_ABI, signer);
      addLog("Depositing 0.001 ETH...");
      const tx = await guard.deposit({
        value: ethers.utils.parseEther("0.001"),
      });
      addLog("Tx: " + tx.hash.slice(0, 18) + "...");
      await tx.wait();
      addLog("Deposit confirmed!");
      await loadVault(account || undefined);
    } catch (e: unknown) {
      const err = e as { reason?: string; message: string };
      addLog("Deposit failed: " + (err.reason || err.message));
    }
  }, [signer, connectWallet, addLog, loadVault, account]);

  const withdraw = useCallback(async () => {
    if (!signer || !account) {
      await connectWallet();
      return;
    }
    try {
      const balance = await guardRead.deposits(account);
      if (balance.isZero()) {
        addLog("No balance to withdraw");
        return;
      }
      const guard = new ethers.Contract(GUARD_ADDRESS, GUARD_ABI, signer);
      addLog("Withdrawing " + ethers.utils.formatEther(balance) + " ETH...");
      const tx = await guard.withdraw(balance);
      addLog("Tx: " + tx.hash.slice(0, 18) + "...");
      await tx.wait();
      addLog("Withdrawal confirmed!");
      await loadVault(account);
    } catch (e: unknown) {
      const err = e as { reason?: string; message: string };
      addLog("Withdraw failed: " + (err.reason || err.message));
    }
  }, [signer, account, connectWallet, addLog, loadVault]);

  const checkHealth = useCallback(async () => {
    if (!signer) {
      await connectWallet();
      return;
    }
    try {
      const guard = new ethers.Contract(GUARD_ADDRESS, GUARD_ABI, signer);
      addLog("Checking vault health...");
      const tx = await guard.checkHealth();
      addLog("Tx: " + tx.hash.slice(0, 18) + "...");
      await tx.wait();
      addLog("Health check complete");
      await loadVault(account || undefined);
    } catch (e: unknown) {
      const err = e as { reason?: string; message: string };
      addLog("Health check failed: " + (err.reason || err.message));
    }
  }, [signer, connectWallet, addLog, loadVault, account]);

  // Initial load + auto-refresh
  useEffect(() => {
    refreshAll();
    const interval = setInterval(refreshAll, 30000);
    return () => clearInterval(interval);
  }, [refreshAll]);

  return {
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
  };
}
