import Link from "next/link";

const plans = [
  { name: "Starter", min: "10", rate: "1.20%", duration: "180 days" },
  { name: "Growth", min: "500", rate: "1.80%", duration: "150 days" },
  { name: "Advanced", min: "2,500", rate: "2.40%", duration: "120 days" },
  { name: "Elite", min: "10,000", rate: "3.00%", duration: "90 days" },
];

const features = [
  {
    title: "Tiered daily rewards",
    body: "Four staking tiers with fixed daily rates and durations, fully computed on-chain — check the math yourself in the verified contract source.",
  },
  {
    title: "Multi-level referrals",
    body: "Three-level referral commissions on every claim, paid automatically and tracked transparently per address.",
  },
  {
    title: "Real Polymarket integration",
    body: "The contract owner can route a bounded share of pool collateral into on-chain calls to Polymarket's official Conditional Tokens Framework contract — every split, merge, and redemption is a real, verifiable transaction, never a simulated number.",
  },
  {
    title: "Verified & auditable",
    body: "Full source code, unit tests, and an invariant test suite are public. The deployed bytecode matches the verified source 1:1 on PolygonScan.",
  },
];

export default function HomePage() {
  return (
    <div className="space-y-24 py-10">
      <section className="text-center">
        <p className="mx-auto mb-4 inline-block rounded-full border border-brand-500/30 bg-brand-500/10 px-4 py-1 text-xs font-semibold uppercase tracking-wide text-brand-400">
          Live on Polygon Mainnet · Verified Contract
        </p>
        <h1 className="mx-auto max-w-3xl text-4xl font-extrabold tracking-tight sm:text-6xl">
          Stake. Earn. <span className="text-brand-400">Refer.</span>
        </h1>
        <p className="mx-auto mt-6 max-w-xl text-lg text-slate-400">
          A transparent, on-chain staking and referral platform on Polygon — with a
          treasury strategy that includes real, verifiable interactions with
          Polymarket&apos;s official smart contracts.
        </p>
        <div className="mt-8 flex justify-center gap-4">
          <Link href="/dashboard" className="btn-primary">
            Open Dashboard
          </Link>
          <a
            href={`https://polygonscan.com/address/${process.env.NEXT_PUBLIC_CONTRACT_ADDRESS}#code`}
            target="_blank"
            rel="noreferrer"
            className="btn-secondary"
          >
            View Verified Source
          </a>
        </div>
      </section>

      <section>
        <h2 className="mb-8 text-center text-2xl font-bold">Staking tiers</h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {plans.map((p) => (
            <div key={p.name} className="card text-center">
              <p className="text-sm font-semibold text-brand-400">{p.name}</p>
              <p className="mt-3 text-3xl font-extrabold">{p.rate}</p>
              <p className="text-xs text-slate-500">per day</p>
              <div className="mt-4 space-y-1 text-sm text-slate-400">
                <p>Min stake: {p.min} USDC</p>
                <p>Duration: {p.duration}</p>
              </div>
            </div>
          ))}
        </div>
        <p className="mx-auto mt-6 max-w-2xl text-center text-xs text-slate-500">
          Rates are fixed, on-chain parameters — not a promise of profit. Review the
          verified contract before staking any funds.
        </p>
      </section>

      <section>
        <h2 className="mb-8 text-center text-2xl font-bold">How it works</h2>
        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
          {features.map((f) => (
            <div key={f.title} className="card">
              <h3 className="mb-2 text-lg font-semibold text-brand-400">{f.title}</h3>
              <p className="text-sm text-slate-400">{f.body}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="card text-center">
        <h2 className="text-2xl font-bold">Ready to get started?</h2>
        <p className="mx-auto mt-2 max-w-md text-sm text-slate-400">
          Connect your wallet, choose a tier, and start earning — every action is a
          direct, on-chain transaction you approve yourself.
        </p>
        <Link href="/dashboard" className="btn-primary mt-6 inline-flex">
          Open Dashboard
        </Link>
      </section>
    </div>
  );
}
