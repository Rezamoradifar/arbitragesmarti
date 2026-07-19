// Free public RPC endpoints only keep a shallow eth_getLogs history window
// (no paid "archive" tier) -- a full-range scan from the contract's deploy
// block routinely gets rejected once the range is more than ~100-150
// blocks deep. There's no backend indexer in this project (see contracts
// README "known simplifications"), so this falls back to a shallow,
// reliably-available window and flags that older history was skipped
// instead of hanging or silently showing an empty result as if nothing
// had ever happened.
const FALLBACK_DEPTH = 100n;

export async function getLogsSafe(publicClient, { address, event, fromBlock }) {
  try {
    const logs = await publicClient.getLogs({ address, event, fromBlock, toBlock: "latest" });
    return { logs, limitedHistory: false };
  } catch {
    const latest = await publicClient.getBlockNumber();
    const shallowFrom = latest > FALLBACK_DEPTH ? latest - FALLBACK_DEPTH : 0n;
    const logs = await publicClient.getLogs({ address, event, fromBlock: shallowFrom, toBlock: "latest" });
    return { logs, limitedHistory: true };
  }
}
