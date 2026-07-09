# ArbiSmart Frontend — VPS Deployment (PM2 + nginx)

Verified working: `npm run build` completes with exit code 0, and all three
routes (`/`, `/dashboard`, `/admin`) return HTTP 200 with real rendered
content when served with `npm run start`.

## 1. Install dependencies and configure environment

```bash
cd ~/projects/arbitragesmarti/frontend
npm install
cp .env.local.example .env.local
nano .env.local
```

Fill in real values:

| Variable | Value |
|---|---|
| `NEXT_PUBLIC_CONTRACT_ADDRESS` | Your deployed & verified ArbiSmartV2 address |
| `NEXT_PUBLIC_COLLATERAL_ADDRESS` | The collateral token address (must match `collateralToken()` on the contract) |
| `NEXT_PUBLIC_POLYGON_RPC_URL` | A Polygon RPC endpoint (a private provider like Alchemy/Infura is recommended over the public one for production traffic) |
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | Free project ID from https://cloud.walletconnect.com/ — required for the WalletConnect connector in RainbowKit to work |

## 2. Build

```bash
npm run build
```

Expect the route table to print with no errors (warnings about
`@react-native-async-storage/async-storage` and `pino-pretty` are expected —
they're optional dependencies of wallet-connector packages for
React Native / pretty dev logging, unused in this browser-only deployment).

## 3. Run with PM2

```bash
pm2 start ecosystem.config.js
pm2 save
```

Check it's up:
```bash
pm2 status
curl -I http://localhost:3000/
```

## 4. nginx reverse proxy (serve on your real domain over HTTPS)

Create `/etc/nginx/sites-available/arbismart`:

```nginx
server {
    listen 80;
    server_name yourdomain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Enable it and get a free TLS certificate:
```bash
ln -s /etc/nginx/sites-available/arbismart /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
certbot --nginx -d yourdomain.com
```

## 5. Redeploying after changes

```bash
cd ~/projects/arbitragesmarti/frontend
git pull
npm install
npm run build
pm2 restart arbismart-frontend
```

## Notes

- `NEXT_PUBLIC_*` variables are baked into the client-side bundle at build
  time — after changing `.env.local`, you must re-run `npm run build` (a PM2
  restart alone is not enough).
- The Admin page (`/admin`) checks the connected wallet against the
  contract's `owner()` on-chain and hides all controls for anyone else — but
  it is still public at the URL level. If you want it fully hidden from the
  public, put it behind an nginx `auth_basic` block or a separate subdomain.
- `npm audit` reports vulnerabilities in transitive dependencies of the
  wallet-connector ecosystem (`@reown/appkit-*`, `@walletconnect/*`) that are
  several layers deep inside RainbowKit's own dependency tree — this is
  common across the whole wagmi/RainbowKit ecosystem at the time of writing
  and not something this app's own code introduces. Re-run `npm audit` after
  future `npm install`s and update RainbowKit/wagmi when fixes land upstream.
