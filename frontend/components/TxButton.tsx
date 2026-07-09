"use client";

import { useEffect } from "react";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import { CONTRACT_ADDRESS, CONTRACT_ABI } from "@/lib/contract";

export function useContractTx(onSuccess?: () => void) {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isConfirmed) onSuccess?.();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConfirmed]);

  function call(functionName: string, args: unknown[] = []) {
    writeContract({
      address: CONTRACT_ADDRESS,
      abi: CONTRACT_ABI,
      functionName,
      args,
    });
  }

  return { call, hash, isPending, isConfirming, isConfirmed, error, reset };
}

export function TxStatus({
  isPending,
  isConfirming,
  isConfirmed,
  error,
  hash,
}: {
  isPending: boolean;
  isConfirming: boolean;
  isConfirmed: boolean;
  error: Error | null;
  hash?: string;
}) {
  if (error) {
    return <p className="mt-2 text-sm text-red-400">{error.message.split("\n")[0]}</p>;
  }
  if (isPending) return <p className="mt-2 text-sm text-slate-400">Confirm in your wallet…</p>;
  if (isConfirming) return <p className="mt-2 text-sm text-slate-400">Waiting for confirmation…</p>;
  if (isConfirmed)
    return (
      <p className="mt-2 text-sm text-brand-400">
        Success!{" "}
        {hash && (
          <a
            className="underline underline-offset-2"
            href={`https://polygonscan.com/tx/${hash}`}
            target="_blank"
            rel="noreferrer"
          >
            View transaction
          </a>
        )}
      </p>
    );
  return null;
}
