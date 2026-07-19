import { http, createConfig } from "wagmi";
import { bsc, bscTestnet } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";

// Get a project ID from https://cloud.walletconnect.com if you want
// WalletConnect (mobile wallet QR) support in addition to injected
// (MetaMask/Trust Wallet browser extension) connections.
const WALLETCONNECT_PROJECT_ID = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || "";

export const config = createConfig({
  chains: [bscTestnet, bsc],
  connectors: [
    injected(),
    ...(WALLETCONNECT_PROJECT_ID
      ? [walletConnect({ projectId: WALLETCONNECT_PROJECT_ID })]
      : []),
  ],
  transports: {
    // Explicit RPC URLs -- viem's chain defaults (data-seed-*.bnbchain.org,
    // thirdweb) reset/reject connections from a lot of datacenter and cloud
    // IPs, which silently breaks reads for a chunk of real users too, not
    // just CI. publicnode is reliable for both chains.
    [bscTestnet.id]: http(import.meta.env.VITE_TESTNET_RPC_URL || "https://bsc-testnet-rpc.publicnode.com"),
    [bsc.id]: http(import.meta.env.VITE_MAINNET_RPC_URL || "https://bsc-rpc.publicnode.com"),
  },
});
