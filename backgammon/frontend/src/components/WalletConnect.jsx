import { useAccount, useConnect, useDisconnect, useBalance, useSwitchChain } from "wagmi";
import { bsc, bscTestnet } from "wagmi/chains";

function short(addr) {
  return addr ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : "";
}

export default function WalletConnect() {
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  const { data: balance } = useBalance({ address, query: { enabled: !!address } });

  const wrongChain = isConnected && chainId !== bsc.id && chainId !== bscTestnet.id;

  if (!isConnected) {
    return (
      <div style={{ display: "flex", gap: "0.6rem" }}>
        {connectors
          .filter((c, i, arr) => arr.findIndex((x) => x.name === c.name) === i)
          .map((connector) => (
            <button
              key={connector.uid}
              className="btn-primary"
              disabled={isPending}
              onClick={() => connect({ connector })}
            >
              {isPending ? "Connecting…" : `Connect ${connector.name}`}
            </button>
          ))}
      </div>
    );
  }

  return (
    <div style={{ display: "flex", alignItems: "center", gap: "0.9rem" }}>
      {wrongChain && (
        <button className="btn-primary" onClick={() => switchChain({ chainId: bscTestnet.id })}>
          Switch to BSC Testnet
        </button>
      )}
      <div className="mono" style={{ fontSize: "0.85rem", color: "var(--ivory-dim)" }}>
        {balance ? `${Number(balance.formatted).toFixed(4)} ${balance.symbol}` : ""}
      </div>
      <div
        className="mono panel"
        style={{ padding: "0.4rem 0.8rem", fontSize: "0.85rem", color: "var(--brass-bright)" }}
      >
        {short(address)}
      </div>
      <button className="btn-ghost" onClick={() => disconnect()}>
        Disconnect
      </button>
    </div>
  );
}
