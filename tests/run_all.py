#!/usr/bin/env python3
"""
Builds and runs the tests (Windows, Delphi command-line compiler).

  python tests/run_all.py                 offline suite against tests/fake_server.py
  python tests/run_all.py --live          also the live suite against Ollama (tev1:4b)
  python tests/run_all.py --bds "C:\\Program Files (x86)\\Embarcadero\\Studio\\23.0"

The fake server is started and stopped here; nothing is left running.
Exit code 0 only if every suite passed.
"""
import argparse
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 9099


def build(bds, dpr):
    out = os.path.join(HERE, "bin")
    dcu = os.path.join(HERE, "dcu")
    os.makedirs(out, exist_ok=True)
    os.makedirs(dcu, exist_ok=True)
    cmd = [os.path.join(bds, "bin", "dcc32.exe"), "-Q", "-B", "-E" + out, "-N0" + dcu,
           "-U" + os.path.join(HERE, "..", "sources"), os.path.join(HERE, dpr)]
    print("== build", dpr)
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout, r.stderr)
        sys.exit("build failed: " + dpr)
    return os.path.join(out, os.path.splitext(dpr)[0] + ".exe")


def run(exe, *args):
    print("== run", os.path.basename(exe), *args)
    return subprocess.run([exe, *args]).returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bds", default=os.environ.get("BDS", r"C:\Program Files (x86)\Embarcadero\Studio\37.0"))
    ap.add_argument("--live", action="store_true", help="also test against Ollama on localhost:11434")
    a = ap.parse_args()
    if not os.path.exists(os.path.join(a.bds, "bin", "dcc32.exe")):
        sys.exit("no dcc32.exe under %s: pass --bds or set BDS" % a.bds)

    failed = []
    offline = build(a.bds, "SystemOneTest.dpr")
    server = subprocess.Popen([sys.executable, os.path.join(HERE, "fake_server.py"), str(PORT)])
    try:
        for _ in range(50):  # wait for the fake server
            try:
                urllib.request.urlopen("http://127.0.0.1:%d/_last" % PORT, timeout=1)
                break
            except Exception:
                time.sleep(0.1)
        if run(offline, "http://127.0.0.1:%d" % PORT) != 0:
            failed.append("offline")
    finally:
        server.terminate()
        server.wait()

    if a.live:
        live = build(a.bds, "SystemOneLiveTest.dpr")
        if run(live) != 0:
            failed.append("live")

    print("\nFAILED: " + ", ".join(failed) if failed else "\nALL SUITES PASSED")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
