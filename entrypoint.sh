#!/usr/bin/env bash
set -euo pipefail

: "${WARP_ORG:?Set WARP_ORG in .env (see .env.example)}"

mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# Organization to enroll into (no secrets here — login happens in the browser)
mkdir -p /var/lib/cloudflare-warp
cat > /var/lib/cloudflare-warp/mdm.xml <<XML
<dict>
    <key>organization</key>
    <string>${WARP_ORG}</string>
</dict>
XML

# Browser PAC: only PAC_DOMAINS / PAC_IPS go through warpbox (SOCKS5 = DNS resolved in here).
# When warpbox is down the PAC URL is unreachable and browsers go DIRECT.
mkdir -p /pac
to_js_array() { local IFS=,; local out=""; for v in $1; do v="${v// /}"; [[ -n "$v" ]] && out+="\"$v\","; done; echo "[${out%,}]"; }
# PAC_RULES: extra exact-host rules, "host=PROXY SPEC;host2=PROXY SPEC" (checked first)
to_js_rules() { local IFS=';'; local out=""; for r in $1; do [[ "$r" == *=* ]] || continue; out+="\"${r%%=*}\":\"${r#*=}\","; done; echo "{${out%,}}"; }
cat > /pac/proxy.pac <<PAC
function FindProxyForURL(url, host) {
    var viaWarp = "SOCKS5 127.0.0.1:1080; SOCKS 127.0.0.1:1080";
    var rules = $(to_js_rules "${PAC_RULES:-}");
    if (rules.hasOwnProperty(host)) return rules[host];
    var domains = $(to_js_array "${PAC_DOMAINS:-}");
    var ips = $(to_js_array "${PAC_IPS:-}");
    for (var i = 0; i < domains.length; i++)
        if (host === domains[i] || dnsDomainIs(host, "." + domains[i])) return viaWarp;
    for (var j = 0; j < ips.length; j++)
        if (host === ips[j]) return viaWarp;
    return "DIRECT";
}
PAC

warp-svc >/var/log/warp-svc.log 2>&1 &

for _ in $(seq 1 30); do
    warp-cli --accept-tos status >/dev/null 2>&1 && break
    sleep 1
done

# Already enrolled (registration kept in the data volume) → connect right away
if warp-cli --accept-tos registration show >/dev/null 2>&1; then
    warp-cli --accept-tos connect || true
fi

python3 -m http.server 1081 --bind 0.0.0.0 --directory /pac >/dev/null 2>&1 &
exec microsocks -i 0.0.0.0 -p 1080
