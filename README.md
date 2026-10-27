# warpbox — Cloudflare WARP in a Docker container (macOS, Ubuntu)

> This README covers macOS. On Ubuntu, follow [docs/ubuntu.md](docs/ubuntu.md).

Run a Cloudflare Zero Trust (WARP) client inside a small Docker container instead of on the Mac.
The WARP client then sees only the container — not your Mac's apps, Wi-Fi details or battery — and
only the traffic you choose goes through the tunnel. Everything else goes straight to the
internet.

```
Mac browser / ssh / curl
        │  only the domains/IPs you list in .env
        ▼
127.0.0.1:1080  (SOCKS5 proxy)  ──►  warpbox container  ──►  WARP tunnel  ──►  your organization
127.0.0.1:1081  (proxy.pac for the browser)
```

The container enrolls as a normal device in your organization and reports honestly as a Linux
device. Check that your organization allows this before relying on it — device posture rules may
reject it.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Ubuntu 24.04 + official `cloudflare-warp` + `microsocks` (SOCKS5 proxy) |
| `entrypoint.sh` | Starts WARP, connects if already enrolled, generates and serves `proxy.pac`, runs the proxy |
| `compose.yaml` | Container settings; ports are published on `127.0.0.1` only |
| `.env.example` | Settings template — copy to `.env` |
| `warpbox` | The command you use day to day |
| `data/` | Created on first run: your WARP device registration. **Git-ignored — never share it** |

## Requirements

- macOS with Docker Desktop
- No other WARP client running on the Mac (two clients fight over DNS and routes)

## Setup

1. **Settings:**
   ```bash
   cp .env.example .env
   ```
   Set `WARP_ORG` (your Zero Trust team name), `PAC_DOMAINS` (domain suffixes that should go
   through warpbox) and optionally `PAC_IPS`. `PAC_RULES` sends specific hosts elsewhere, e.g. to
   another local proxy: `PAC_RULES="vpn-only.example.com=PROXY 127.0.0.1:1090"` (quote it).

2. **Make `warpbox` a plain command** (run inside the warpbox folder):
   ```bash
   mkdir -p ~/.local/bin && ln -sf "$PWD/warpbox" ~/.local/bin/warpbox
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   ```
   Skip it and use the full path instead (`/path/to/warpbox/warpbox status`) if you prefer.

3. **Start:**
   ```bash
   warpbox up
   ```

4. **Enroll (once):**
   ```bash
   warpbox login
   ```
   - Open the printed `https://<team>.cloudflareaccess.com/…` URL and log in.
   - On the **Success** page, **right-click** "Open Cloudflare WARP" → **Copy Link** (left-clicking
     hands the login to any WARP app installed on the Mac instead).
   - Finish with the copied link:
     ```bash
     warpbox token 'com.cloudflare.warp://<team>.cloudflareaccess.com/auth?token=…'
     ```
   - Expect `Status update: Connected`. The link is a one-time login key — don't share it.

5. **Browser:** apply the PAC to your network service (macOS may ask for your password):
   ```bash
   warpbox pac on
   ```
   Then quit and reopen the browser. In Chrome you can instead open
   `chrome://net-internals/#proxy` → **Re-apply settings**.

6. **SSH (optional):** for hosts that should go through warpbox, add to `~/.ssh/config`:
   ```
   Host my-internal-host
       ProxyCommand nc -X 5 -x 127.0.0.1:1080 %h %p
   ```

## Daily routine

**Start of day**
1. Make sure Docker Desktop is running (whale icon in the menu bar).
2. `warpbox up`
3. Work as usual — internal sites open in the browser, `ssh` to configured hosts works.

**End of day**
```bash
warpbox down
```
Nothing runs and nothing is reported until the next `warpbox up`. Internal sites stop loading;
everything else is unaffected.

## Usage

```bash
warpbox up        # start — the tunnel is available
warpbox down      # stop — nothing runs, nothing is reported
warpbox status    # container + WARP state, enrolled organization
```

| Need | How |
|---|---|
| Open an internal site | `warpbox up`, then browse normally (the PAC routes it) |
| SSH to an internal host | `warpbox up`, then `ssh my-internal-host` |
| One command through warpbox | `warpbox run curl https://internal.example.com/` |
| Several commands in this shell | `eval "$(warpbox env)"` |
| SSH without editing the config | `ssh -o ProxyCommand='nc -X 5 -x 127.0.0.1:1080 %h %p' host` |
| WARP logs | `warpbox logs` |
| Shell inside the container | `warpbox shell` |
| Browser rule off / on | `warpbox pac off` / `warpbox pac on` |

When warpbox is down, the PAC URL is unreachable and browsers go direct; internal sites simply
don't load.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `warpbox status` → `Failed to perform happy eyeballs` | Docker Desktop lost outbound UDP (seen after network changes on the Mac, e.g. uninstalling a VPN). Restart Docker Desktop (`docker desktop restart`), then `warpbox up`. This stops your other containers; ones without a restart policy need `docker start` again |
| Browser `ERR_CONNECTION_CLOSED` on an internal site | `warpbox status`; if not connected, `warpbox up` |
| Browser lands on your organization's login page instead of the site | The request didn't go through warpbox: `warpbox pac` should show `Enabled: Yes`; quit and reopen the browser |
| `ssh` hangs | warpbox is down, or the host has no `ProxyCommand` |
| `Registration Missing` | `data/` was removed — enroll again (setup step 4) |
| `set WARP_ORG in …/.env` | Create `.env` from `.env.example` |
| `zsh: command not found: warpbox` | `~/.local/bin` is not in your PATH — do setup step 2, or use the full path to the `warpbox` script |

Quick check:
```bash
curl -s -o /dev/null -w '%{http_code}\n' --socks5-hostname 127.0.0.1:1080 https://internal.example.com/
```

## What the organization can see

| | Visible? |
|---|---|
| Your Mac's apps, Wi-Fi name/signal, battery, hardware model | No — the client sees only the container |
| Traffic that doesn't go through warpbox, and your Mac's own DNS lookups | No |
| CPU / RAM totals | The Docker VM's, not your Mac's apps |
| Your public IP and rough location | Yes — true of any VPN |
| Everything you send through warpbox | Yes — that is what the tunnel is for |
| When you are online | Only while warpbox is up |

Keep personal files and tools out of the container — anything inside it is visible to the client.

## Uninstall

```bash
warpbox pac off
warpbox down
docker image rm warpbox:local
rm -rf /path/to/warpbox ~/.local/bin/warpbox
```
Remove any `ProxyCommand` lines you added to `~/.ssh/config`.
