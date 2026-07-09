"use client";

import { useMemo, useState } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import {
  CONTRACT_ADDRESS,
  CONTRACT_ABI,
  ERC20_ABI,
  formatUnits6,
  parseUnits6,
  PLAN_NAMES,
} from "@/lib/contract";
import { StatCard } from "@/components/StatCard";
import { useContractTx, TxStatus } from "@/components/TxButton";
import { useWriteContract } from "wagmi";

export default function DashboardPage() {
  const { address, isConnected } = useAccount();

  const { data: collateralAddress } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: "collateralToken",
  });

  const { data: globalStats, refetch: refetchGlobal } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: "getGlobalStats",
  });

  const { data: userData, refetch: refetchUser } = useReadContracts({
    contracts: [
      { address: CONTRACT_ADDRESS, abi: CONTRACT_ABI, functionName: "stakes", args: [address] },
      { address: CONTRACT_ADDRESS, abi: CONTRACT_ABI, functionName: "getReward", args: [address] },
      { address: CONTRACT_ADDRESS, abi: CONTRACT_ABI, functionName: "getReferralInfo", args: [address] },
      { address: CONTRACT_ADDRESS, abi: CONTRACT_ABI, functionName: "getTeamVolume", args: [address] },
      { address: CONTRACT_ADDRESS, abi: CONTRACT_ABI, functionName: "getF1Count", args: [address] },
      { address: CONTRACT_ADDRESS, abi: CONTRACT_ABI, functionName: "isFreePeriod" },
      { address: CONTRACT_ADDRESS, abi: CONTRACT_ABI, functionName: "paused" },
    ],
    query: { enabled: !!address },
  });

  const { data: tokenData, refetch: refetchToken } = useReadContracts({
    contracts: [
      { address: collateralAddress as `0x${string}`, abi: ERC20_ABI, functionName: "symbol" },
      { address: collateralAddress as `0x${string}`, abi: ERC20_ABI, functionName: "balanceOf", args: [address] },
      {
        address: collateralAddress as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "allowance",
        args: [address, CONTRACT_ADDRESS],
      },
    ],
    query: { enabled: !!address && !!collateralAddress },
  });

  const stake = userData?.[0].result as
    | readonly [bigint, bigint, bigint, bigint, bigint, bigint, boolean, boolean, boolean]
    | undefined;
  const pendingReward = (userData?.[1].result as bigint | undefined) ?? 0n;
  const referralInfo = userData?.[2].result as
    | readonly [string, bigint, bigint, bigint, bigint]
    | undefined;
  const teamVolume = userData?.[3].result as readonly [bigint, bigint, bigint] | undefined;
  const f1Count = (userData?.[4].result as bigint | undefined) ?? 0n;
  const isFreePeriod = Boolean(userData?.[5].result);
  const isPaused = Boolean(userData?.[6].result);

  const tokenSymbol = (tokenData?.[0].result as string | undefined) ?? "TOKEN";
  const tokenBalance = (tokenData?.[1].result as bigint | undefined) ?? 0n;
  const allowance = (tokenData?.[2].result as bigint | undefined) ?? 0n;

  const refetchAll = () => {
    refetchGlobal();
    refetchUser();
    refetchToken();
  };

  const [stakeAmount, setStakeAmount] = useState("");
  const [referrer, setReferrer] = useState("");

  const needsApproval = useMemo(() => {
    try {
      return allowance < parseUnits6(stakeAmount || "0");
    } catch {
      return true;
    }
  }, [allowance, stakeAmount]);

  const approveTx = useContractTx(refetchAll);
  const stakeTx = useContractTx(refetchAll);
  const topUpTx = useContractTx(refetchAll);
  const upgradeTx = useContractTx(refetchAll);
  const claimTx = useContractTx(refetchAll);
  const claimRefTx = useContractTx(refetchAll);
  const exitTx = useContractTx(refetchAll);
  const emergencyTx = useContractTx(refetchAll);
  const { writeContract: approveWrite } = useWriteContract();

  function handleApprove() {
    if (!collateralAddress) return;
    approveWrite(
      {
        address: collateralAddress as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [CONTRACT_ADDRESS, parseUnits6(stakeAmount || "0") * 10n],
      },
      { onSuccess: () => refetchToken() }
    );
  }

  if (!isConnected) {
    return (
      <div className="card mx-auto mt-16 max-w-md text-center">
        <p className="mb-4 text-slate-400">Connect your wallet to view your dashboard.</p>
        <div className="flex justify-center">
          <ConnectButton />
        </div>
      </div>
    );
  }

  const hasActiveStake = stake?.[6] === true;
  const hasExited = stake?.[7] === true;

  return (
    <div className="space-y-10 py-6">
      {isPaused && (
        <div className="rounded-xl border border-amber-500/40 bg-amber-500/10 p-4 text-sm text-amber-300">
          The contract is currently paused by the owner. Staking, top-ups, and claims
          are temporarily disabled. If this persists for 30+ days, an{" "}
          <code>emergencyWithdraw</code> becomes available below.
        </div>
      )}

      <section>
        <h1 className="mb-6 text-2xl font-bold">Platform stats</h1>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatCard label="Total users" value={globalStats ? globalStats[0].toString() : "—"} />
          <StatCard
            label="Total staked"
            value={globalStats ? `${formatUnits6(globalStats[1])} ${tokenSymbol}` : "—"}
          />
          <StatCard
            label="Total paid out"
            value={globalStats ? `${formatUnits6(globalStats[2])} ${tokenSymbol}` : "—"}
          />
          <StatCard
            label="Pool balance"
            value={globalStats ? `${formatUnits6(globalStats[3])} ${tokenSymbol}` : "—"}
          />
        </div>
      </section>

      <section>
        <h2 className="mb-6 text-xl font-bold">Your position</h2>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatCard
            label="Your stake"
            value={stake ? `${formatUnits6(stake[0])} ${tokenSymbol}` : "0"}
            sub={stake && hasActiveStake ? `${PLAN_NAMES[Number(stake[1])]} tier` : hasExited ? "Exited" : "No active stake"}
          />
          <StatCard label="Pending reward" value={`${formatUnits6(pendingReward)} ${tokenSymbol}`} />
          <StatCard
            label="Wallet balance"
            value={`${formatUnits6(tokenBalance)} ${tokenSymbol}`}
          />
          <StatCard
            label="Referral reward"
            value={referralInfo ? `${formatUnits6(referralInfo[2])} ${tokenSymbol}` : "0"}
          />
        </div>
      </section>

      {isFreePeriod && (
        <div className="rounded-xl border border-brand-500/40 bg-brand-500/10 p-4 text-sm text-brand-300">
          Free promotional period is active: stake exactly 10 {tokenSymbol} at no cost to
          open a starter position.
        </div>
      )}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section className="card">
          <h3 className="mb-4 text-lg font-semibold">
            {hasActiveStake ? "Top up your stake" : "Stake"}
          </h3>
          <label className="label">Amount ({tokenSymbol})</label>
          <input
            className="input"
            placeholder="e.g. 500"
            value={stakeAmount}
            onChange={(e) => setStakeAmount(e.target.value)}
          />
          {!hasActiveStake && (
            <>
              <label className="label mt-4">Referrer address (optional)</label>
              <input
                className="input"
                placeholder="0x..."
                value={referrer}
                onChange={(e) => setReferrer(e.target.value)}
              />
            </>
          )}
          <div className="mt-4 flex gap-3">
            {needsApproval ? (
              <button className="btn-secondary" onClick={handleApprove}>
                Approve {tokenSymbol}
              </button>
            ) : hasActiveStake ? (
              <button
                className="btn-primary"
                disabled={!stakeAmount}
                onClick={() => topUpTx.call("topUp", [parseUnits6(stakeAmount)])}
              >
                Top Up
              </button>
            ) : (
              <button
                className="btn-primary"
                disabled={!stakeAmount || hasExited}
                onClick={() =>
                  stakeTx.call("stake", [
                    parseUnits6(stakeAmount),
                    referrer || "0x0000000000000000000000000000000000000000",
                  ])
                }
              >
                Stake
              </button>
            )}
          </div>
          <TxStatus {...(hasActiveStake ? topUpTx : stakeTx)} />
          {hasExited && (
            <p className="mt-2 text-xs text-slate-500">
              This address has already early-exited once and cannot open a new stake.
            </p>
          )}
        </section>

        <section className="card">
          <h3 className="mb-4 text-lg font-semibold">Manage your stake</h3>
          <div className="flex flex-wrap gap-3">
            <button className="btn-primary" disabled={pendingReward === 0n} onClick={() => claimTx.call("claim")}>
              Claim reward
            </button>
            <button
              className="btn-secondary"
              disabled={!referralInfo || referralInfo[2] === 0n}
              onClick={() => claimRefTx.call("claimRef")}
            >
              Claim referral
            </button>
            <button
              className="btn-secondary"
              disabled={!hasActiveStake}
              onClick={() => upgradeTx.call("upgradePlan")}
            >
              Upgrade plan
            </button>
            <button
              className="btn-secondary border-red-900/50 text-red-300 hover:bg-red-950/40"
              disabled={!hasActiveStake}
              onClick={() => exitTx.call("earlyExit")}
            >
              Early exit
            </button>
          </div>
          <TxStatus {...claimTx} />
          <TxStatus {...claimRefTx} />
          <TxStatus {...upgradeTx} />
          <TxStatus {...exitTx} />

          {isPaused && (
            <div className="mt-6 border-t border-slate-800 pt-4">
              <p className="mb-2 text-sm text-slate-400">
                Emergency withdrawal (only available once paused for 30+ consecutive days):
              </p>
              <button
                className="btn-secondary border-amber-900/50 text-amber-300 hover:bg-amber-950/40"
                disabled={!hasActiveStake}
                onClick={() => emergencyTx.call("emergencyWithdraw")}
              >
                Emergency withdraw
              </button>
              <TxStatus {...emergencyTx} />
            </div>
          )}
        </section>
      </div>

      <section className="card">
        <h3 className="mb-4 text-lg font-semibold">Referral overview</h3>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatCard label="Level" value={referralInfo ? referralInfo[4].toString() : "0"} />
          <StatCard label="Active referrals" value={referralInfo ? referralInfo[3].toString() : "0"} />
          <StatCard label="Direct referrals (F1)" value={f1Count.toString()} />
          <StatCard
            label="Team volume"
            value={teamVolume ? `${formatUnits6(teamVolume[2])} ${tokenSymbol}` : "0"}
          />
        </div>
        <p className="mt-4 text-xs text-slate-500">
          Share your address as a referrer link to earn multi-level commission on your
          referrals&apos; claimed rewards.
        </p>
      </section>
    </div>
  );
}
