#!/usr/bin/env python3
"""External watchdog/custody for the OTP-owned constructed witness pair."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "experiments/gate_001"))
from reference import now, write_json, seal, digest


def main():
    run = ROOT / "receipts" / ("witness-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    run.mkdir()
    manifest = dict(start=now(), kind="constructed-behavioral-witness", pairs=1, retries=0,
                    source_commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
                    source_diff=subprocess.check_output(["git", "diff", "--stat"], cwd=ROOT).decode(),
                    witness_sha256=digest(ROOT / "target/debug/hello_witness"), outer_timeout_seconds=30)
    env = os.environ.copy()
    env.update(PTY_LAB_ROOT=str(ROOT), PTY_LAB_RUN=str(run))
    args = ["erl", "-noshell", "-pa", str(ROOT / "erlang/pty_lab/_build/default/lib/pty_lab/ebin"), "-eval",
            'try witness_experiment:run(os:getenv("PTY_LAB_ROOT"), os:getenv("PTY_LAB_RUN")) of ok -> halt(0) catch C:R:S -> io:format("~p:~p~n~p~n",[C,R,S]), halt(1) end.']
    try:
        result = subprocess.run(args, env=env, cwd=ROOT, capture_output=True, timeout=26)
        (run / "beam.stdout").write_bytes(result.stdout)
        (run / "beam.stderr").write_bytes(result.stderr)
        manifest["beam_exit_code"] = result.returncode
        if result.returncode:
            raise RuntimeError("witness pair failed; inspect journals and beam.stdout")
        pids = []
        timing = {}
        for mode in ["pipe", "slave"]:
            journal = run / (mode + ".jsonl")
            assert digest(journal) == Path(str(journal) + ".sha256").read_text().strip().lower()
            entries = [json.loads(line) for line in journal.read_bytes().splitlines()]
            assert [e["seq"] for e in entries] == list(range(1, len(entries) + 1))
            requests = [e["data"] for e in entries if e["event"] == "command"]
            assert [r["command"] for r in requests] == ["spawn", "write"]
            assert bytes.fromhex(requests[1]["hex"]) == b"hello\n"
            for entry in entries:
                if entry["event"] == "helper_event" and entry["data"]["event"] == "spawned":
                    pids.extend(entry["data"]["data"][k] for k in ["helper_pid", "guardian_pid", "pid"])
                if entry["event"] == "input_timing_observation":
                    timing[mode] = entry["data"]["delay_ns"]
                    assert timing[mode] >= 100_000_000
        deadline = time.monotonic() + 3
        while True:
            alive = []
            for pid in pids:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    pass
                else:
                    alive.append(pid)
            if not alive:
                break
            if time.monotonic() >= deadline:
                raise AssertionError(f"processes remain: {alive}")
            time.sleep(0.01)
        manifest.update(outcome="pass", all_reported_pids_absent=pids, input_request_delay_ns=timing)
    except subprocess.TimeoutExpired as error:
        (run / "beam.stdout").write_bytes(error.stdout or b"")
        (run / "beam.stderr").write_bytes(error.stderr or b"")
        manifest.update(outcome="outer_timeout", error=repr(error))
        raise
    except Exception as error:
        manifest.update(outcome="failed", error=repr(error))
        raise
    finally:
        manifest["end"] = now()
        write_json(run / "manifest.json", manifest)
        seal(run)
        print(run)


if __name__ == "__main__":
    main()
