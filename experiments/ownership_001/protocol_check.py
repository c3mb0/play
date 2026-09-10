#!/usr/bin/env python3
"""Exercise actual relay framing independently of OTP. Every case is bounded."""
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "experiments/gate_001"))
from reference import now, write_json, seal, digest


def frame(value):
    raw = json.dumps(value).encode()
    return struct.pack(">I", len(raw)) + raw


def main():
    directory = ROOT / "receipts" / ("protocol-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    directory.mkdir()
    helper = ROOT / "target/debug/pty_helper"
    identity = {"experiment": "protocol-check", "cell": "framing", "session": "framing"}
    status = {"v": 1, "seq": 1, "identity": identity, "command": "status"}
    cases = [
        ("fragmented-and-coalesced", [frame(status)[:1], frame(status)[1:3], frame(status)[3:] + frame(dict(status, seq=2))], ["status", "status"]),
        ("bad-version", [frame(dict(status, v=999))], ["error"]),
        ("oversized", [struct.pack(">I", 1048577)], ["error"]),
        ("zero-length", [struct.pack(">I", 0)], ["error"]),
        ("bad-json", [struct.pack(">I", 1) + b"{"], ["error"]),
    ]
    receipt = dict(start=now(), helper_sha256=digest(helper), cases=[], retries=0)
    try:
        for name, chunks, expected in cases:
            process = subprocess.Popen([str(helper), "--port"], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            raw = bytearray()
            events = []
            try:
                for chunk in chunks:
                    process.stdin.write(chunk)
                    process.stdin.flush()
                deadline = time.monotonic() + 2
                consumed = 0
                while len(events) < len(expected):
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
                        raise TimeoutError(f"{name}: no prompt framed event")
                    chunk = os.read(process.stdout.fileno(), 8192)
                    if not chunk:
                        raise RuntimeError(f"{name}: premature EOF")
                    raw.extend(chunk)
                    while len(raw) - consumed >= 4:
                        n = struct.unpack(">I", raw[consumed:consumed + 4])[0]
                        if len(raw) - consumed < n + 4:
                            break
                        events.append(json.loads(raw[consumed + 4:consumed + 4 + n]))
                        consumed += n + 4
                assert [e["event"] for e in events] == expected
                process.stdin.close()
                process.wait(timeout=2)
                assert process.returncode == 0
                receipt["cases"].append(dict(name=name, outcome="pass", events=events))
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=2)
                (directory / (name + ".wire")).write_bytes(raw)
                (directory / (name + ".stderr")).write_bytes(process.stderr.read())
        receipt["outcome"] = "pass"
    except Exception as error:
        receipt.update(outcome="failed", error=repr(error))
        raise
    finally:
        receipt["end"] = now()
        write_json(directory / "manifest.json", receipt)
        seal(directory)
        print(directory)


if __name__ == "__main__":
    main()
