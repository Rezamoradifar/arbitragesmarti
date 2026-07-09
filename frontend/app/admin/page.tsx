"use client";

import { useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { CONTRACT_ADDRESS, CONTRACT_ABI } from "@/lib/contract";
import { useContractTx, TxStatus } from "@/components/TxButton";

function AdminAction({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="card">
      <h3 className="mb-4 text-lg font-semibold">{title}</h3>
      {children}
    </section>
  );
}

export default function AdminPage() {
  const { address, isConnected } = useAccount();

  const { data: owner } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: "owner",
  });
  const { data: paused, refetch: refetchPaused } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: "paused",
  });

  const isOwner = !!address && !!owner && address.toLowerCase() === (owner as string).toLowerCase();

  const pauseTx = useContractTx(refetchPaused);
  const unpauseTx = useContractTx(refetchPaused);
  const blacklistTx = useContractTx();
  const feeWalletsTx = useContractTx();
  const profitRecipientTx = useContractTx();
  const profitBpsTx = useContractTx();
  const splitTx = useContractTx();
  const mergeTx = useContractTx();
  const redeemTx = useContractTx();

  const [blacklistAddr, setBlacklistAddr] = useState("");
  const [blacklistVal, setBlacklistVal] = useState(true);
  const [fw1, setFw1] = useState("");
  const [fw2, setFw2] = useState("");
  const [profitRecipientAddr, setProfitRecipientAddr] = useState("");
  const [profitBps, setProfitBps] = useState("");
  const [conditionId, setConditionId] = useState("");
  const [partition, setPartition] = useState("1,2");
  const [amount, setAmount] = useState("");

  const parsedPartition = () => partition.split(",").map((s) => BigInt(s.trim()));

  if (!isConnected) {
    return (
      <div className="card mx-auto mt-16 max-w-md text-center">
        <p className="mb-4 text-slate-400">Connect the owner wallet to access admin controls.</p>
        <div className="flex justify-center">
          <ConnectButton />
        </div>
      </div>
    );
  }

  if (!isOwner) {
    return (
      <div className="card mx-auto mt-16 max-w-md text-center">
        <p className="text-slate-400">
          Connected address is not the contract owner. Admin controls are hidden.
        </p>
        <p className="mt-2 break-all text-xs text-slate-600">Owner: {owner as string}</p>
      </div>
    );
  }

  return (
    <div className="space-y-6 py-6">
      <h1 className="text-2xl font-bold">Admin panel</h1>
      <p className="text-sm text-slate-500">
        Connected as owner. Every action below is a real, signed on-chain transaction —
        double-check values before confirming in your wallet.
      </p>

      <AdminAction title="Pause / Unpause">
        <p className="mb-4 text-sm text-slate-400">
          Current state: <span className="font-semibold">{paused ? "Paused" : "Active"}</span>
        </p>
        <div className="flex gap-3">
          <button className="btn-secondary" disabled={!!paused} onClick={() => pauseTx.call("pause")}>
            Pause
          </button>
          <button className="btn-primary" disabled={!paused} onClick={() => unpauseTx.call("unpause")}>
            Unpause
          </button>
        </div>
        <TxStatus {...pauseTx} />
        <TxStatus {...unpauseTx} />
      </AdminAction>

      <AdminAction title="Blacklist">
        <label className="label">Address</label>
        <input className="input" value={blacklistAddr} onChange={(e) => setBlacklistAddr(e.target.value)} placeholder="0x..." />
        <div className="mt-3 flex items-center gap-3">
          <label className="flex items-center gap-2 text-sm text-slate-400">
            <input type="checkbox" checked={blacklistVal} onChange={(e) => setBlacklistVal(e.target.checked)} />
            Blacklist (uncheck to remove)
          </label>
        </div>
        <button
          className="btn-primary mt-4"
          disabled={!blacklistAddr}
          onClick={() => blacklistTx.call("setBlacklist", [blacklistAddr, blacklistVal])}
        >
          Update blacklist
        </button>
        <TxStatus {...blacklistTx} />
      </AdminAction>

      <AdminAction title="Fee wallets">
        <label className="label">Fee wallet 1</label>
        <input className="input" value={fw1} onChange={(e) => setFw1(e.target.value)} placeholder="0x..." />
        <label className="label mt-3">Fee wallet 2</label>
        <input className="input" value={fw2} onChange={(e) => setFw2(e.target.value)} placeholder="0x..." />
        <button
          className="btn-primary mt-4"
          disabled={!fw1 || !fw2}
          onClick={() => feeWalletsTx.call("setFeeWallets", [fw1, fw2])}
        >
          Update fee wallets
        </button>
        <TxStatus {...feeWalletsTx} />
      </AdminAction>

      <AdminAction title="Profit recipient & performance fee">
        <label className="label">Profit recipient address</label>
        <input
          className="input"
          value={profitRecipientAddr}
          onChange={(e) => setProfitRecipientAddr(e.target.value)}
          placeholder="0x..."
        />
        <button
          className="btn-secondary mt-3"
          disabled={!profitRecipientAddr}
          onClick={() => profitRecipientTx.call("setProfitRecipient", [profitRecipientAddr])}
        >
          Update recipient
        </button>
        <TxStatus {...profitRecipientTx} />

        <label className="label mt-6">Performance fee (basis points, max 2000 = 20%)</label>
        <input className="input" value={profitBps} onChange={(e) => setProfitBps(e.target.value)} placeholder="1000" />
        <button
          className="btn-secondary mt-3"
          disabled={!profitBps}
          onClick={() => profitBpsTx.call("setProfitFeeBPS", [BigInt(profitBps || "0")])}
        >
          Update fee rate
        </button>
        <TxStatus {...profitBpsTx} />
      </AdminAction>

      <AdminAction title="Polymarket — split / merge / redeem">
        <p className="mb-4 text-xs text-slate-500">
          Calls the real, official Polymarket Conditional Tokens contract. See the
          contract&apos;s NatSpec for the honest limitation on order-book trading —
          these are direct CTF-level operations only.
        </p>
        <label className="label">Condition ID (bytes32)</label>
        <input className="input" value={conditionId} onChange={(e) => setConditionId(e.target.value)} placeholder="0x..." />
        <label className="label mt-3">Partition / index sets (comma-separated)</label>
        <input className="input" value={partition} onChange={(e) => setPartition(e.target.value)} placeholder="1,2" />
        <label className="label mt-3">Amount (collateral units, 6 decimals raw integer)</label>
        <input className="input" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="e.g. 100000000" />
        <div className="mt-4 flex flex-wrap gap-3">
          <button
            className="btn-primary"
            disabled={!conditionId || !amount}
            onClick={() => splitTx.call("executePolymarketSplit", [conditionId, parsedPartition(), BigInt(amount || "0")])}
          >
            Split
          </button>
          <button
            className="btn-secondary"
            disabled={!conditionId || !amount}
            onClick={() => mergeTx.call("executePolymarketMerge", [conditionId, parsedPartition(), BigInt(amount || "0")])}
          >
            Merge
          </button>
          <button
            className="btn-secondary"
            disabled={!conditionId}
            onClick={() => redeemTx.call("executePolymarketRedeem", [conditionId, parsedPartition()])}
          >
            Redeem
          </button>
        </div>
        <TxStatus {...splitTx} />
        <TxStatus {...mergeTx} />
        <TxStatus {...redeemTx} />
      </AdminAction>
    </div>
  );
}
