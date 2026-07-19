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
    [bscTestnet.id]: http(),
    [bsc.id]: http(),
  },
});
