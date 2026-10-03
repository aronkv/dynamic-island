#!/usr/bin/env python3
"""Wi-Fi based geolocation for WeatherMonitor.qml.

Reads the nearby access points from NetworkManager's cached scan, asks
Apple's Wi-Fi positioning service (the unofficial gs-loc.apple.com endpoint
iOS/macOS use — global coverage, no key) for their coordinates, and falls
back to BeaconDB (open, MLS-compatible) if Apple knows none of them. The
result is reverse-geocoded to a place name via OpenStreetMap Nominatim.

Prints one JSON line {"lat","lon","accuracy","city","countryCode","source"}
on success; prints nothing and exits 1 when no Wi-Fi fix is possible, so the
caller falls back to IP geolocation. Stdlib only.
"""
import json
import subprocess
import sys
import urllib.parse
import urllib.request

MAX_APS = 12
TIMEOUT = 6


def scan():
    out = subprocess.run(["nmcli", "-t", "-f", "BSSID,SIGNAL", "dev", "wifi", "list", "--rescan", "no"],
                         capture_output=True, text=True, timeout=10).stdout
    aps = []
    for line in out.splitlines():
        # nmcli -t escapes the colons inside the BSSID as "\:".
        bssid, _, signal = line.replace("\\:", "-").partition(":")
        bssid = bssid.replace("-", ":").lower()
        if len(bssid) == 17 and signal.isdigit():
            aps.append((bssid, int(signal)))
    aps.sort(key=lambda a: -a[1])
    return aps[:MAX_APS]


# ── minimal protobuf encode/decode (only what the wloc message needs) ──
def _varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def _field(num, wire, payload):
    key = _varint((num << 3) | wire)
    if wire == 0:
        return key + _varint(payload)
    return key + _varint(len(payload)) + payload


def _parse(buf):
    """Yields (field_number, wire_type, value) for one message level."""
    i = 0
    while i < len(buf):
        key, i = _read_varint(buf, i)
        num, wire = key >> 3, key & 7
        if wire == 0:
            val, i = _read_varint(buf, i)
        elif wire == 2:
            ln, i = _read_varint(buf, i)
            val, i = buf[i:i + ln], i + ln
        elif wire == 1:
            val, i = buf[i:i + 8], i + 8
        elif wire == 5:
            val, i = buf[i:i + 4], i + 4
        else:
            return
        yield num, wire, val


def _read_varint(buf, i):
    shift = result = 0
    while True:
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, i
        shift += 7


def _signed(v):
    return v - (1 << 64) if v >= 1 << 63 else v


def apple(aps):
    msg = b"".join(_field(2, 2, _field(1, 2, b.encode())) for b, _ in aps)
    msg += _field(3, 0, 0) + _field(4, 0, 1)  # return only the requested BSSIDs
    head = (b"\x00\x01\x00\x05en_US\x00\x13com.apple.locationd\x00\x0a8.1.12B411"
            b"\x00\x00\x00\x01\x00\x00")
    body = head + len(msg).to_bytes(2, "big") + msg
    req = urllib.request.Request("https://gs-loc.apple.com/clls/wloc", data=body, headers={
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "*/*",
        "User-Agent": "locationd/1753.17 CFNetwork/889.9 Darwin/17.2.0",
    })
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        data = r.read()[10:]
    signal = dict(aps)
    hits = []
    for num, _, dev in _parse(data):
        if num != 2:
            continue
        bssid, loc = None, None
        for n, _, v in _parse(dev):
            if n == 1:
                bssid = v.decode()
            elif n == 2:
                loc = {k: _signed(x) for k, _, x in _parse(v) if k in (1, 2, 3)}
        # Unknown BSSIDs come back with latitude -180°.
        if not bssid or not loc or loc.get(1, -18000000000) == -18000000000:
            continue
        # Apple drops leading zeros in each octet ("1c:61:b4:da:b0:7").
        key = ":".join(p.zfill(2) for p in bssid.split(":"))
        hits.append((loc[1] * 1e-8, loc[2] * 1e-8, loc.get(3, 100), signal.get(key, 50)))
    if not hits:
        return None
    # Signal-weighted centroid of the known access points.
    w = sum(h[3] for h in hits)
    lat = sum(h[0] * h[3] for h in hits) / w
    lon = sum(h[1] * h[3] for h in hits) / w
    return lat, lon, min(h[2] for h in hits), "apple"


def beacondb(aps):
    body = json.dumps({"considerIp": False, "wifiAccessPoints": [
        {"macAddress": b, "signalStrength": s // 2 - 100} for b, s in aps]}).encode()
    req = urllib.request.Request("https://api.beacondb.net/v1/geolocate", data=body, headers={
        "Content-Type": "application/json", "User-Agent": "dynamic-island-quickshell"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            d = json.load(r)
    except urllib.error.HTTPError:
        return None  # 404 = no estimate for these access points
    return d["location"]["lat"], d["location"]["lng"], d.get("accuracy", 0), "beacondb"


def reverse(lat, lon):
    q = urllib.parse.urlencode({"lat": lat, "lon": lon, "format": "jsonv2", "zoom": 10})
    req = urllib.request.Request("https://nominatim.openstreetmap.org/reverse?" + q,
                                 headers={"User-Agent": "dynamic-island-quickshell/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            a = json.load(r).get("address", {})
    except Exception:
        return "", ""
    city = a.get("city") or a.get("town") or a.get("village") or a.get("municipality") or ""
    return city, a.get("country_code", "").upper()


def main():
    aps = scan()
    if not aps:
        return 1
    fix = None
    for provider in (apple, beacondb):
        try:
            fix = provider(aps)
        except Exception:
            fix = None
        if fix:
            break
    if not fix:
        return 1
    lat, lon, acc, source = fix
    city, cc = reverse(lat, lon)
    print(json.dumps({"lat": round(lat, 5), "lon": round(lon, 5), "accuracy": acc,
                      "city": city, "countryCode": cc, "source": source}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
