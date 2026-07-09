import type { Metadata } from "next";
import "./globals.css";
import { Web3Providers } from "@/lib/wagmi";
import { NavBar } from "@/components/NavBar";

export const metadata: Metadata = {
  title: "ArbiSmart — Polygon Staking & Referral Platform",
  description:
    "Stake, earn, and refer on Polygon. Transparent on-chain rewards with a verified smart contract.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Web3Providers>
          <NavBar />
          <main className="mx-auto max-w-6xl px-4 pb-24 pt-6 sm:px-6 lg:px-8">{children}</main>
          <footer className="border-t border-slate-900 py-8 text-center text-sm text-slate-500">
            ArbiSmart runs on a verified, open-source smart contract on Polygon.{" "}
            <a
              className="text-brand-400 underline underline-offset-2"
              href={`https://polygonscan.com/address/${process.env.NEXT_PUBLIC_CONTRACT_ADDRESS}`}
              target="_blank"
              rel="noreferrer"
            >
              View contract on PolygonScan
            </a>
          </footer>
        </Web3Providers>
      </body>
    </html>
  );
}
