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


GEN_RANK = {"": 0, "4": 4, "5": 5, "6": 6, "6E": 6.5, "7": 7}
GEN_NAME = {"4": "Wi-Fi 4 (802.11n)", "5": "Wi-Fi 5 (802.11ac)", "6": "Wi-Fi 6 (802.11ax)",
            "6E": "Wi-Fi 6E (802.11ax)", "7": "Wi-Fi 7 (802.11be)"}


def wifi_device():
    try:
        out = subprocess.run(["nmcli", "-t", "-f", "DEVICE,TYPE", "device"],
                             capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return None
    for line in out.splitlines():
        dev, _, dtype = line.partition(":")
        if dtype == "wifi":
            return dev
    return None


def scan_generations(device):
    """BSSID -> what the access point itself supports, from the capability
    elements in its beacons (`iw dev <dev> scan dump` reads the kernel's
    cached scan, no root needed). This is what phones label "Wi-Fi 6";
    the negotiated link can be lower when the laptop's adapter is older."""
    gens = {}
    if not device:
        return gens
    try:
        out = subprocess.run(["iw", "dev", device, "scan", "dump"],
                             capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return gens
    for block in re.split(r"^BSS ", out, flags=re.M)[1:]:
        bssid = block[:17].lower()
        freq_m = re.search(r"freq:\s*(\d+)", block)
        freq = float(freq_m.group(1)) if freq_m else 0
        if "EHT capabilities" in block:
            gen = "7"
        elif "HE capabilities" in block:
            gen = "6E" if freq >= 5925 else "6"
        elif "VHT capabilities" in block:
            gen = "5"
        elif "HT capabilities" in block:
            gen = "4"
        else:
            gen = ""
        gens[bssid] = gen
    return gens


def prefix_to_subnet(prefix):
    try:
        prefix = int(prefix)
    except (TypeError, ValueError):
        return ""
    mask = (0xffffffff << (32 - prefix)) & 0xffffffff if prefix > 0 else 0
    return ".".join(str((mask >> shift) & 0xff) for shift in (24, 16, 8, 0))


def get_connection_details(gens):
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
    # EHT = 802.11be/Wi-Fi 7; HE on 6 GHz (freq >= 5925 MHz) = Wi-Fi 6E.
    # "generation" is the short form for the panel's icon badge.
    generation, ap_bssid = "", ""
    try:
        link_out = subprocess.run(
            ["iw", "dev", device, "link"],
            capture_output=True, text=True, timeout=3,
        ).stdout
        freq_m = re.search(r"freq:\s*(\d+)", link_out)
        freq = float(freq_m.group(1)) if freq_m else 0
        bssid_m = re.search(r"Connected to ([0-9a-f:]{17})", link_out)
        ap_bssid = bssid_m.group(1).lower() if bssid_m else ""
        if "EHT-MCS" in link_out:
            generation = "7"
        elif "HE-MCS" in link_out:
            generation = "6E" if freq >= 5925 else "6"
        elif "VHT-MCS" in link_out:
            generation = "5"
        elif "MCS" in link_out:
            generation = "4"
    except Exception:
        pass
    # The router's own capability (what a phone shows) vs. the negotiated
    # link (capped by this laptop's adapter, e.g. Intel 8265 = Wi-Fi 5).
    ap_generation = gens.get(ap_bssid, "") or generation

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
        "technology": GEN_NAME.get(ap_generation, "Wi-Fi"),
        "apGeneration": ap_generation,
        "linkGeneration": generation,
        "linkTechnology": GEN_NAME.get(generation, ""),
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

    gens = scan_generations(wifi_device())
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
                "generation": gens.get(bssid.lower(), ""),
            }
        else:
            if band and band not in existing["band"]:
                existing["band"] = existing["band"] + " + " + band if existing["band"] else band
            g = gens.get(bssid.lower(), "")
            if GEN_RANK.get(g, 0) > GEN_RANK.get(existing["generation"], 0):
                existing["generation"] = g

    try:
        result["_connection"] = get_connection_details(gens)
    except Exception:
        result["_connection"] = None

    print(json.dumps(result))


if __name__ == "__main__":
    main()
