/// <reference types="vite/client" />

interface Window {
  ethereum?: import("ethers").ethers.providers.ExternalProvider & {
    request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
  };
}
