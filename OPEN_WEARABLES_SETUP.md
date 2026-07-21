# Deploying Open Wearables (replacing direct Whoop/Oura integration)

This replaces Soma's direct Whoop/Oura OAuth integration with
[open-wearables](https://github.com/the-momentum/open-wearables), a
self-hosted platform that unifies many wearable providers behind one API,
so Soma can support more devices (Garmin, Polar, Strava, Fitbit,
Ultrahuman, Suunto, in addition to Whoop/Oura) without building a direct
integration for each one.

**What it actually is**, so the steps below make sense: 7 always-on
containers -- Postgres, Redis, the FastAPI app, 2 Celery processes
(worker + beat scheduler), Flower (Celery monitoring), Svix (webhook
delivery), and a React admin portal. Not a function that spins up on
demand -- a real server that needs to stay running and be kept secure,
because it holds real OAuth tokens for your users' wearables.

Config files referenced below are already prepared in
[`open-wearables-deploy/`](open-wearables-deploy) in this project:
`docker-compose.prod.secure.yml`, `Caddyfile`, `backend.env.template`,
`root.env.template`.

## Why the hardened compose file

Upstream's `docker-compose.prod.yml` publishes Postgres (5432), Redis
(6379), and Flower (5555) straight to `0.0.0.0` -- on a public cloud VM
that means anyone on the internet can reach your database and cache
directly. `docker-compose.prod.secure.yml` in this repo removes all of
that: only Caddy is bound to the host (ports 80/443), and it reverse-proxies
to `app`/`frontend` over Docker's internal network. Everything else is
only reachable from other containers on the same VM.

## 1. Create the Oracle Cloud account (manual -- your identity/payment info)

1. Go to [cloud.oracle.com/free](https://cloud.oracle.com/free) and sign
   up. Oracle requires a card for identity verification even for the
   Always Free tier -- it states clearly it won't charge you as long as
   you stay within Always Free limits.
2. Verify your email and phone number, complete signup.

## 2. Create the VM

1. Console → **Compute → Instances → Create Instance**.
2. **Image and shape** → Edit shape → choose **Ampere (Arm-based)** →
   `VM.Standard.A1.Flex`. Set **4 OCPUs / 24 GB memory** -- this is the
   full Always Free Ampere allowance in one box, plenty for all 7
   containers.
3. **Image**: Canonical Ubuntu (24.04 or latest LTS, aarch64/arm64).
4. **Networking**: keep the default VCN/subnet so it gets a public IP.
5. **SSH keys**: generate a pair locally first --
   ```
   ssh-keygen -t ed25519 -f ~/.ssh/open-wearables-vm -C "open-wearables"
   ```
   paste the contents of `~/.ssh/open-wearables-vm.pub` into the console's
   "Add SSH keys" step. Keep the private key (`open-wearables-vm`, no
   `.pub`) -- you'll need it to connect.
6. Create the instance, note its **public IP address**.

## 3. Open only the ports we actually need

Console → your instance → **Subnet** link → **Security Lists** (or
create a **Network Security Group**) → **Add Ingress Rules**:
- TCP 22 (SSH) -- ideally restrict the source CIDR to your own IP, not `0.0.0.0/0`
- TCP 80 (HTTP, needed for Let's Encrypt's certificate challenge)
- TCP 443 (HTTPS)

Do **not** open 5432, 6379, 5555, 8000, or 3000 -- the hardened compose
file never publishes them, so there's nothing there to reach anyway, but
don't open them at the cloud firewall layer either.

Ubuntu images on Oracle also ship with `iptables` rules that block
non-SSH traffic by default. Once connected (`ssh -i ~/.ssh/open-wearables-vm ubuntu@<public-ip>`), run:
```
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

## 4. Free domain names (DuckDNS)

Let's Encrypt (which Caddy uses automatically) needs real domain names,
not a bare IP. [duckdns.org](https://www.duckdns.org) gives free
subdomains -- sign in (GitHub/Google/etc.), create two:
- `api-soma.duckdns.org` → your VM's public IP
- `admin-soma.duckdns.org` → same IP

(Names are illustrative -- pick whatever's available, then use your real
choice everywhere below instead of these placeholders.)

## 5. Install Docker on the VM

```
ssh -i ~/.ssh/open-wearables-vm ubuntu@<public-ip>
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
```

## 6. Clone the repo and drop in the prepared config

```
git clone https://github.com/the-momentum/open-wearables.git
cd open-wearables
mkdir -p backend/config
```

From your Mac, copy the 4 prepared files onto the VM (run these from
`SOMA V1/` on your Mac, adjusting the key path/IP):
```
scp -i ~/.ssh/open-wearables-vm open-wearables-deploy/docker-compose.prod.secure.yml ubuntu@<public-ip>:~/open-wearables/
scp -i ~/.ssh/open-wearables-vm open-wearables-deploy/Caddyfile ubuntu@<public-ip>:~/open-wearables/
scp -i ~/.ssh/open-wearables-vm open-wearables-deploy/root.env.template ubuntu@<public-ip>:~/open-wearables/.env
scp -i ~/.ssh/open-wearables-vm open-wearables-deploy/backend.env.template ubuntu@<public-ip>:~/open-wearables/backend/config/.env
```

Back on the VM, edit both env files to replace the placeholder domains
with your real DuckDNS names, and fill in your real Whoop/Oura client
ID/secret (the redirect URI to add in each provider's developer portal is
spelled out in `backend/config/.env`'s comments):
```
nano .env                        # API_DOMAIN, ADMIN_DOMAIN, VITE_API_URL
nano backend/config/.env         # replace *_PLACEHOLDER, add WHOOP/OURA credentials
```

## 7. Bring it up

```
docker compose -f docker-compose.prod.secure.yml up -d
docker compose -f docker-compose.prod.secure.yml exec app uv run alembic upgrade head
```

Check everything's healthy:
```
docker compose -f docker-compose.prod.secure.yml ps
docker compose -f docker-compose.prod.secure.yml logs -f app
```

Caddy needs DNS to actually resolve before it can get a certificate --
give DuckDNS a few minutes to propagate if the first request to
`https://admin-soma.duckdns.org` fails.

## 8. First login

1. Open `https://admin-soma.duckdns.org` in a browser.
2. Log in with `ADMIN_EMAIL` / `ADMIN_PASSWORD` from `backend/config/.env`
   -- **change the password immediately** from the admin UI.
3. Confirm Whoop and Oura show up under connected providers (they read
   their credentials from `backend/config/.env` automatically).
4. **API Keys** section → generate a key. This is what Soma's Supabase
   Edge Functions will use to call this API server-to-server -- keep it
   secret, we'll add it to `supabase secrets set` in the next phase.
5. **Outgoing Webhooks** section → add an endpoint. The URL will point at
   a new Supabase Edge Function (`open-wearables-webhook`) -- I'll build
   that and give you the exact URL once you confirm the server's up.

## What's next

Once this is live and you've generated an API key, tell me and I'll
build the Soma-side integration:
- A new Supabase Edge Function to receive Open Wearables' outgoing
  webhooks and write into `daily_snapshot` (same table `generate-recommendation`
  already reads from -- its decision-engine logic doesn't need to change).
- A `users.open_wearables_user_id` column mapping your Supabase users to
  Open Wearables' internal user IDs.
- Replacing `WhoopOAuthManager`/`OuraOAuthManager` in the iOS app with a
  single "connect via Open Wearables" flow that lists every provider it
  supports on the Connect Device screen.
