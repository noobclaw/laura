#!/usr/bin/env python3
"""Static checks that stand in for some test cases. Prints JSON {tc_id: "passed"|"failed: why"}."""
import json, os, plistlib, re, glob, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
src = {p: open(p, encoding="utf-8").read() for p in glob.glob(os.path.join(root, "Spindle", "**", "*.swift"), recursive=True)}
r = {}
def check(tc, ok, why=""):
    r[tc] = "passed" if ok else "failed: " + why

# TC-IAP-04: StoreKit purchase calls only inside ProStore.
offenders = [os.path.basename(p) for p, s in src.items()
             if not p.endswith("ProStore.swift") and re.search(r"(?<!pro)\.purchase\(", s.replace("pro.purchase(", ""))]
check("TC-IAP-04", not offenders, ", ".join(offenders))

# TC-RVW-07: no reward-for-review, no home-made stars.
bad = [os.path.basename(p) for p, s in src.items() if re.search(r"star\.fill.*rating|rateForReward|reviewReward|unlock.*review", s, re.I)]
check("TC-RVW-07", not bad, ", ".join(bad))

# TC-SYS-01: iPhone only, portrait only, background mode audio only.
info = plistlib.load(open(os.path.join(root, "Spindle", "Info.plist"), "rb"))
yml = open(os.path.join(root, "project.yml")).read()
ok = info.get("UISupportedInterfaceOrientations") == ["UIInterfaceOrientationPortrait"] and info.get("UIBackgroundModes") == ["audio"] \
     and 'TARGETED_DEVICE_FAMILY: "1"' in yml
check("TC-SYS-01", ok, "orientation/background/device family")

# TC-SYS-02: privacy manifest with UserDefaults and file timestamp reasons.
pm = plistlib.load(open(os.path.join(root, "Spindle", "Resources", "PrivacyInfo.xcprivacy"), "rb"))
cats = {d["NSPrivacyAccessedAPIType"] for d in pm.get("NSPrivacyAccessedAPITypes", [])}
check("TC-SYS-02", pm.get("NSPrivacyTracking") is False and {"NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryFileTimestamp"} <= cats, str(cats))

# TC-SYS-03: the only hard-coded hosts are our support/privacy pages and the App Store.
hosts = set()
for s in src.values():
    hosts |= set(re.findall(r"https?://([a-zA-Z0-9.-]+)", s))
allowed = {"256btc.com", "apps.apple.com", "192.168.1.20", "127.0.0.1", "nas.local"}  # last three: examples in prompts and tests
extra = hosts - allowed
banned_sdk = [p for p, s in src.items() if re.search(r"import (Firebase|Mixpanel|Amplitude|Segment|AppsFlyer|Adjust|GoogleMobileAds)", s)]
check("TC-SYS-03", not extra and not banned_sdk, f"hosts {sorted(extra)} sdk {banned_sdk}")

# TC-L10N-03: Info.plist strings localized in all 10 languages.
cat = json.load(open(os.path.join(root, "Spindle", "Resources", "InfoPlist.xcstrings")))["strings"]
need = ["NSLocalNetworkUsageDescription", "NSPhotoLibraryAddUsageDescription", "CFBundleDisplayName"]
miss = [k for k in need if len(cat.get(k, {}).get("localizations", {})) < 10]
check("TC-L10N-03", not miss, ", ".join(miss))

print(json.dumps(r, ensure_ascii=False, indent=1))
sys.exit(0 if all(v == "passed" for v in r.values()) else 1)
