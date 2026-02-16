import { useState } from "react";
import { ethers } from "ethers";
import {
  SEPOLIA_RPC,
  GUARD_ADDRESS,
  GUARD_ABI,
  POR_ADDRESS,
  POR_ABI,
} from "../config/contracts";

export type SimAction = "deposit" | "withdraw" | "checkHealth";

export interface SimulationResult {
  action: SimAction;
  success: boolean;
  gasEstimate: string | null;
  revertReason: string | null;
  statePreview: {
    depositsAllowed: boolean;
    isHealthy: boolean;
    riskScore: number;
    vaultTotal: string;
    collateralRatio: number;
  };
}

const provider = new ethers.providers.JsonRpcProvider(SEPOLIA_RPC);
const guardContract = new ethers.Contract(GUARD_ADDRESS, GUARD_ABI, provider);
const porContract = new ethers.Contract(POR_ADDRESS, POR_ABI, provider);
const guardIface = new ethers.utils.Interface(GUARD_ABI);

const DEFAULT_FROM = "0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF";

export function useSimulation() {
  const [simulating, setSimulating] = useState(false);
  const [result, setResult] = useState<SimulationResult | null>(null);

  const simulate = async (
    action: SimAction,
    fromAddress?: string,
    amount = "0.001"
  ) => {
    setSimulating(true);
    setResult(null);

    const from = fromAddress || DEFAULT_FROM;

    try {
      // Read current state in parallel
      const [depositsAllowed, isHealthy, vaultStatus, riskData] =
        await Promise.all([
          guardContract.depositsAllowed(),
          porContract.isHealthy(),
          guardContract.getVaultStatus(),
          porContract.getLatestRisk(),
        ]);

      // Build transaction params based on action
      let txParams: ethers.providers.TransactionRequest;

      switch (action) {
        case "deposit":
          txParams = {
            to: GUARD_ADDRESS,
            from,
            data: guardIface.encodeFunctionData("deposit"),
            value: ethers.utils.parseEther(amount),
          };
          break;
        case "withdraw":
          txParams = {
            to: GUARD_ADDRESS,
            from,
            data: guardIface.encodeFunctionData("withdraw", [
              ethers.utils.parseEther(amount),
            ]),
          };
          break;
        case "checkHealth":
          txParams = {
            to: GUARD_ADDRESS,
            from,
            data: guardIface.encodeFunctionData("checkHealth"),
          };
          break;
      }

      // Simulate via eth_call on Tenderly VNet
      let success = false;
      let gasEstimate: string | null = null;
      let revertReason: string | null = null;

      try {
        await provider.call(txParams);
        success = true;
        try {
          const gas = await provider.estimateGas(txParams);
          gasEstimate = gas.toString();
        } catch {
          // Gas estimate can fail in edge cases
        }
      } catch (e: unknown) {
        success = false;
        const err = e as {
          reason?: string;
          error?: { message?: string };
          message?: string;
        };
        const msg =
          err.reason || err.error?.message || err.message || "Unknown error";
        revertReason = msg
          .replace("execution reverted: ", "")
          .replace(
            "cannot estimate gas; transaction may fail or may require manual gas limit",
            "Transaction would revert"
          );
      }

      setResult({
        action,
        success,
        gasEstimate,
        revertReason,
        statePreview: {
          depositsAllowed,
          isHealthy,
          riskScore:
            typeof riskData[0] === "number"
              ? riskData[0]
              : riskData[0].toNumber(),
          vaultTotal: ethers.utils.formatEther(vaultStatus[0]),
          collateralRatio: vaultStatus[4].toNumber(),
        },
      });
    } catch (e: unknown) {
      const err = e as { message?: string };
      setResult({
        action,
        success: false,
        gasEstimate: null,
        revertReason: err.message || "Simulation failed",
        statePreview: {
          depositsAllowed: false,
          isHealthy: false,
          riskScore: 0,
          vaultTotal: "0",
          collateralRatio: 0,
        },
      });
    }

    setSimulating(false);
  };

  const clearResult = () => setResult(null);

  return { simulating, result, simulate, clearResult };
}
