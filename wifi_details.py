#!/usr/bin/env python3
"""Extra per-network Wi-Fi detail (band/channel/frequency/speed/detailed
security string/BSSID) that Quickshell.Networking's own WifiNetwork type
doesn't expose (confirmed against its real qmltypes: only `signalStrength`
and a coarse `security` enum — no band/channel/frequency/BSSID at all).
`nmcli`'s own richer `device wifi list` fills that gap. Also includes a
special "_connection" key with detail about the currently-active Wi-Fi
connection (IP/subnet/gateway/DHCP-or-static/MAC-privacy) — the panel's
right-click detail view for the connected network needs this and none of
it comes from Quickshell.Networking's WifiNetwork either.

Usage: wifi_details.py
Prints one JSON object to stdout:
    {
      "<ssid>": {"bssid", "channel", "band", "freq", "rate", "security"}, ...
      "_connection": {"ip", "prefix", "subnet", "gateway", "method", "privacy", "proxy"} | null
    }

Multiple access points can share one SSID (dual-band routers broadcasting
the same name on 2.4GHz and 5GHz, or a mesh/repeater setup) — nmcli's own
list is already sorted strongest-signal-first, so the first entry seen for
a given SSID sets its representative bssid/channel/freq/rate/security, and
every band seen across all its entries is collected into that one entry's
"band" field (e.g. "2.4 GHz + 5 GHz") instead of silently dropping the
weaker duplicate.
"""
import json
import re
import subprocess

FIELDS = ["SSID", "BSSID", "CHAN", "BAND", "FREQ", "RATE", "SECURITY"]

# nmcli's `-t` terse mode separates fields with a bare ':' and escapes any
# literal ':' inside a field's own value (e.g. a BSSID) as '\:' — splitting
# on an unescaped colon via negative lookbehind, then un-escaping each
# field, recovers the real values.
SPLIT_RE = re.compile(r"(?<!\\):")


def unescape(field):
    return field.replace("\\:", ":")


def nmcli_field(fields, *extra_args):
    try:
        out = subprocess.run(
            ["nmcli", "-t", "-f", ",".join(fields), *extra_args],
            check=True, capture_output=True, text=True, timeout=10,
        ).stdout
    except Exception:
        return {}
    values = {}
    for line in out.splitlines():
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        values[key] = value
    return values


def prefix_to_subnet(prefix):
    try:
        prefix = int(prefix)
    except (TypeError, ValueError):
        return ""
    mask = (0xffffffff << (32 - prefix)) & 0xffffffff if prefix > 0 else 0
    return ".".join(str((mask >> shift) & 0xff) for shift in (24, 16, 8, 0))


def get_connection_details():
    # Which device (if any) currently has an active Wi-Fi connection.
    dev_out = subprocess.run(
        ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"],
        check=True, capture_output=True, text=True, timeout=10,
    ).stdout
    device = None
    conn_name = None
    for line in dev_out.splitlines():
        parts = line.split(":")
        if len(parts) < 4:
            continue
        dev, dtype, state, conn = parts[0], parts[1], parts[2], ":".join(parts[3:])
        if dtype == "wifi" and state == "connected" and conn:
            device, conn_name = dev, conn
            break
    if not device:
        return None

    ip_info = nmcli_field(["IP4.ADDRESS", "IP4.GATEWAY"], "device", "show", device)
    address = ip_info.get("IP4.ADDRESS[1]", "")
    ip, _, prefix = address.partition("/")
    gateway = ip_info.get("IP4.GATEWAY", "")

    conn_info = nmcli_field(
        ["ipv4.method", "802-11-wireless.cloned-mac-address"],
        "connection", "show", conn_name,
    )
    method = "DHCP" if conn_info.get("ipv4.method", "auto") != "manual" else "Static"
    mac_setting = conn_info.get("802-11-wireless.cloned-mac-address", "").strip()
    privacy = {
        "": "Default", "preserve": "Default", "permanent": "Device MAC",
        "random": "Randomized", "stable": "Stable random",
    }.get(mac_setting, mac_setting or "Default")

    # 802.11 generation, from the actual negotiated PHY rate — `iw`'s own
    # link output names the MCS table in use (HE = 802.11ax/Wi-Fi 6,
    # VHT = 802.11ac/Wi-Fi 5, plain MCS = 802.11n/Wi-Fi 4), which is the
    # same signal Android's own "Wi-Fi 6" label is built from. Nothing in
    # nmcli reports this at all.
    technology = "Wi-Fi"
    try:
        link_out = subprocess.run(
            ["iw", "dev", device, "link"],
            capture_output=True, text=True, timeout=3,
        ).stdout
        if "HE-MCS" in link_out:
            technology = "Wi-Fi 6"
        elif "VHT-MCS" in link_out:
            technology = "Wi-Fi 5"
        elif "MCS" in link_out:
            technology = "Wi-Fi 4"
    except Exception:
        pass

    proxy = "None"
    try:
        mode = subprocess.run(
            ["gsettings", "get", "org.gnome.system.proxy", "mode"],
            capture_output=True, text=True, timeout=3,
        ).stdout.strip().strip("'")
        if mode and mode != "none":
            proxy = mode.capitalize()
    except Exception:
        pass

    return {
        "technology": technology,
        "ip": ip,
        "prefix": prefix,
        "subnet": prefix_to_subnet(prefix),
        "gateway": gateway,
        "method": method,
        "privacy": privacy,
        "proxy": proxy,
    }


def main():
    try:
        out = subprocess.run(
            ["nmcli", "-t", "-f", ",".join(FIELDS), "device", "wifi", "list"],
            check=True, capture_output=True, text=True, timeout=10,
        ).stdout
    except Exception:
        print("{}")
        return

    result = {}
    for line in out.splitlines():
        if not line:
            continue
        parts = SPLIT_RE.split(line)
        if len(parts) != len(FIELDS):
            continue
        ssid, bssid, chan, band, freq, rate, security = (unescape(p) for p in parts)
        if not ssid:
            continue
        existing = result.get(ssid)
        if existing is None:
            result[ssid] = {
                "bssid": bssid,
                "channel": chan,
                "band": band,
                "freq": freq,
                "rate": rate,
                "security": security or "Open",
            }
        elif band and band not in existing["band"]:
            existing["band"] = existing["band"] + " + " + band if existing["band"] else band

    try:
        result["_connection"] = get_connection_details()
    except Exception:
        result["_connection"] = None

    print(json.dumps(result))


if __name__ == "__main__":
    main()
