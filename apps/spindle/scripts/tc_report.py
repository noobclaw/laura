#!/usr/bin/env python3
"""Builds qa/TC-RESULT-<build>.md: every case in TEST-CASES.md with its result.

Usage: tc_report.py <build> <test-log> [<test-log> ...] --static static.json [--manual qa/manual.md]

- Automated results come from xcodebuild logs: "Test Case '-[Target.Class test_TC_LIB_01_x]' passed".
  A test name can carry several ids (test_TC_SRC_08_TC_IAP_01_...). A case with several tests fails if any fails.
- Static checks (tc_static.py JSON) cover some U cases.
- Manual results: lines "| TC-XXX-NN | passed|failed | note |" in qa/manual.md.
- A case whose method includes U or A but has no result is "untested" and fails the gate.
  Cases that are only M/D are "manual" until recorded.
Exit 1 if any case failed or any automatable case is untested.
"""
import json, os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, "..")
args = sys.argv[1:]
build = args.pop(0)
static, manual, logs = {}, {}, []
while args:
    a = args.pop(0)
    if a == "--static":
        p = args.pop(0)
        if os.path.exists(p):
            try: static = json.load(open(p))
            except Exception: static = {}
    elif a == "--manual":
        p = args.pop(0)
        if os.path.exists(p):
            for line in open(p, encoding="utf-8"):
                m = re.match(r"\|\s*(TC-[A-Z0-9]+-\d+)\s*\|\s*(passed|failed)\s*\|", line)
                if m: manual[m.group(1)] = m.group(2)
    else:
        logs.append(a)

# Cases from TEST-CASES.md
cases = []
for line in open(os.path.join(root, "TEST-CASES.md"), encoding="utf-8"):
    m = re.match(r"\|\s*(TC-[A-Z0-9]+-\d+)\s*\|", line)
    if not m: continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    prio = next((c for c in cells if c in ("P0", "P1", "P2")), "")
    method = cells[-1]
    cases.append((m.group(1), prio, method, cells[1] if len(cells) > 1 else ""))

auto = {}       # id -> list of (test, result)
for path in logs:
    if not os.path.exists(path): continue
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.search(r"Test Case '-\[\S+ (test\w+)\]' (passed|failed)", line)
        if not m: continue
        name, res = m.group(1), m.group(2)
        for a, b in re.findall(r"TC_([A-Z0-9]+)_(\d+)", name):
            auto.setdefault(f"TC-{a}-{b}", []).append((name, res))

rows, failed, untested, manual_pending = [], [], [], []
counts = {"passed": 0, "failed": 0, "untested": 0, "manual": 0}
for tc, prio, method, src in cases:
    results = [r for _, r in auto.get(tc, [])]
    if tc in static:
        results.append("passed" if static[tc] == "passed" else "failed")
    if tc in manual:
        results.append(manual[tc])
    automatable = "U" in method or "A" in method
    if results:
        status = "failed" if "failed" in results else "passed"
    elif automatable:
        status = "untested"
    else:
        status = "manual"
    counts[status] += 1
    if status == "failed": failed.append(tc)
    if status == "untested": untested.append(tc)
    if status == "manual": manual_pending.append(tc)
    evidence = ", ".join(n for n, _ in auto.get(tc, [])) or ("tc_static.py" if tc in static else ("qa/manual.md" if tc in manual else "—"))
    mark = {"passed": "✅ passed", "failed": "❌ failed", "untested": "⚠️ untested", "manual": "🖐 manual"}[status]
    rows.append(f"| {tc} | {prio} | {method} | {mark} | {evidence} |")

os.makedirs(os.path.join(root, "qa"), exist_ok=True)
out = os.path.join(root, "qa", f"TC-RESULT-{build}.md")
with open(out, "w", encoding="utf-8") as fh:
    fh.write(f"# Spindle — test-case results, build {build}\n\n")
    fh.write(f"Cases: {len(cases)} · passed {counts['passed']} · failed {counts['failed']} · untested {counts['untested']} · manual pending {counts['manual']}\n\n")
    fh.write("Gate: no failed case and no untested automatable case. Manual (M/D) cases are listed for the acceptance run.\n\n")
    if failed: fh.write("**Failed:** " + ", ".join(failed) + "\n\n")
    if untested: fh.write("**Untested (automatable, no result):** " + ", ".join(untested) + "\n\n")
    fh.write("| Case | Priority | Method | Result | Evidence |\n|---|---|---|---|---|\n")
    fh.write("\n".join(rows) + "\n")
print(open(out, encoding="utf-8").read().split("\n\n")[1])
print("failed:", failed)
print("untested:", untested)
sys.exit(1 if failed or untested else 0)
