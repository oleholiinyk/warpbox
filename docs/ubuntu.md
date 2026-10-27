# warpbox on Ubuntu

Same idea as on macOS: the Cloudflare WARP client runs inside a Docker container and sees only
the container. Your desktop reaches your organization through a local SOCKS5 proxy
(`127.0.0.1:1080`) and a PAC file (`127.0.0.1:1081`); everything else goes straight to the
internet.

> Written for Ubuntu 22.04 / 24.04 with the GNOME desktop. The container itself is identical to the
> macOS one; only the host-side steps differ.

## Differences from macOS

| | macOS | Ubuntu |
|---|---|---|
| Docker | Docker Desktop | Docker Engine (`docker.io` or Docker's apt repo) |
| Restart Docker | `docker desktop restart` | `sudo systemctl restart docker` |
| Browser proxy (`warpbox pac`) | `networksetup` (System Settings) | GNOME proxy via `gsettings` |
| Firefox | follows macOS settings | needs **Use system proxy settings** (see below) |
| Shell config for PATH | `~/.zshrc` | `~/.bashrc` (or `~/.zshrc` if you use zsh) |
| Remove a host WARP client | uninstaller in the app bundle | `sudo apt purge cloudflare-warp` |

## Requirements

1. **Docker Engine with the compose plugin:**
   ```bash
   sudo apt update
   sudo apt install -y docker.io docker-compose-v2
   sudo usermod -aG docker "$USER"     # then log out and back in
   docker compose version               # should print a version
   ```
2. **`/dev/net/tun`** exists (it does on standard Ubuntu): `ls -l /dev/net/tun`.
3. **`nc` with SOCKS support** for SSH — Ubuntu's default `netcat-openbsd` has it:
   `sudo apt install -y netcat-openbsd`.
4. **No WARP client on the host.** If one is installed, remove it first — two clients fight over
   DNS and routes:
   ```bash
   warp-cli disconnect 2>/dev/null; sudo apt purge -y cloudflare-warp
   ```

## Setup

1. **Get the files and settings:**
   ```bash
   git clone https://github.com/oleholiinyk/warpbox.git ~/warpbox
   cd ~/warpbox
   cp .env.example .env
   ```
   In `.env`, set `WARP_ORG` (your Zero Trust team name), `PAC_DOMAINS` (domain suffixes that
   should go through warpbox) and optionally `PAC_IPS`. `WARPBOX_NET_SERVICE` is macOS-only —
   ignore it.

2. **Make `warpbox` a plain command:**
   ```bash
   mkdir -p ~/.local/bin && ln -sf ~/warpbox/warpbox ~/.local/bin/warpbox
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```
   On many Ubuntu installs `~/.local/bin` is already in PATH after the next login.

3. **Start:**
   ```bash
   warpbox up
   ```
   The first run builds the image (a minute or two).

4. **Enroll (once):**
   ```bash
   warpbox login
   ```
   - Open the printed `https://<team>.cloudflareaccess.com/…` URL and log in.
   - On the **Success** page, **right-click** "Open Cloudflare WARP" → **Copy Link**.
   - Finish with the copied link:
     ```bash
     warpbox token 'com.cloudflare.warp://<team>.cloudflareaccess.com/auth?token=…'
     ```
   - Expect `Status update: Connected`. The link is a one-time login key — don't share it.

5. **Browser:**
   ```bash
   warpbox pac on
   ```
   This sets GNOME's system proxy to *Automatic* with the PAC URL
   (Settings → Network → Network Proxy shows it).
   - **Chrome / Chromium:** follow the GNOME setting. Restart the browser.
   - **Firefox:** Settings → Network Settings → **Use system proxy settings** (or choose
     *Automatic proxy configuration URL* and enter `http://127.0.0.1:1081/proxy.pac`).
   - **Not GNOME** (KDE, etc.): set the automatic proxy URL `http://127.0.0.1:1081/proxy.pac` in
     your desktop's or browser's proxy settings by hand.

6. **SSH (optional):** for hosts that should go through warpbox, add to `~/.ssh/config`:
   ```
   Host my-internal-host
       ProxyCommand nc -X 5 -x 127.0.0.1:1080 %h %p
   ```

## Daily routine

**Start of day**
```bash
warpbox up
```
Docker Engine starts with the system, so there is nothing else to open.

**End of day**
```bash
warpbox down
```
Nothing runs and nothing is reported until the next `warpbox up`.

Everything else — `warpbox status`, `run`, `env`, `logs`, `shell` — works as described in the
main [README](../README.md#usage).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `permission denied … /var/run/docker.sock` | You are not in the `docker` group yet: `sudo usermod -aG docker "$USER"`, then log out and back in |
| `warpbox status` → `Failed to perform happy eyeballs` | Container lost outbound UDP — `sudo systemctl restart docker`, then `warpbox up` |
| `docker compose` → `unknown command` | Install the compose plugin: `sudo apt install docker-compose-v2` |
| Browser lands on your organization's login page | The request didn't go through warpbox: `warpbox pac` should show `mode: 'auto'`; in Firefox check **Use system proxy settings** |
| `warpbox pac` → `No system proxy tool found` | Not a GNOME desktop — set `http://127.0.0.1:1081/proxy.pac` in the browser by hand |
| `ssh` hangs | warpbox is down, or the host has no `ProxyCommand`; check `nc -h 2>&1 \| grep -- -X` shows the SOCKS option |
| `command not found: warpbox` | Setup step 2, or use `~/warpbox/warpbox` |
| Other problems | See the main [README troubleshooting](../README.md#troubleshooting) |

## Uninstall

```bash
warpbox pac off
warpbox down
docker image rm warpbox:local
rm -rf ~/warpbox ~/.local/bin/warpbox
```
Remove any `ProxyCommand` lines you added to `~/.ssh/config`.
