#!/usr/bin/env python3
"""External 60 s watchdog and source custody; experiment/lifecycle runs in OTP."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "experiments/gate_001"))
from reference import now, write_json, seal, digest


def main():
    run = ROOT / "receipts" / ("ownership-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    run.mkdir()
    manifest = dict(start=now(), platform=platform.platform(), protocol_version=1,
                    source_commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
                    source_diff=subprocess.check_output(["git", "diff", "--stat"], cwd=ROOT).decode(),
                    executable_sha256={n: digest(ROOT / "target/debug" / n)
                                       for n in ["topology_probe", "pty_helper", "lifetime_probe"]},
                    retries=0, outer_timeout_seconds=60)
    environment = os.environ.copy()
    environment["PTY_LAB_ROOT"] = str(ROOT)
    environment["PTY_LAB_RUN"] = str(run)
    command = ["erl", "-noshell", "-pa", str(ROOT / "erlang/pty_lab/_build/default/lib/pty_lab/ebin"),
               "-eval", 'try experiment_runner:run(os:getenv("PTY_LAB_ROOT"), os:getenv("PTY_LAB_RUN")) of ok -> halt(0) catch C:R:S -> io:format("~p:~p~n~p~n", [C,R,S]), halt(1) end.']
    try:
        result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, timeout=60)
        (run / "beam.stdout").write_bytes(result.stdout)
        (run / "beam.stderr").write_bytes(result.stderr)
        manifest["beam_exit_code"] = result.returncode
        if result.returncode:
            raise RuntimeError("OTP acceptance failed; inspect beam.stdout and journals")
        # Independently verify journal custody and identity/ordering completeness.
        for journal in run.glob("*.jsonl"):
            expected = (run / (journal.name + ".sha256")).read_text().strip().lower()
            assert digest(journal) == expected
            events = [json.loads(line) for line in journal.read_bytes().splitlines()]
            assert [e["seq"] for e in events] == list(range(1, len(events) + 1))
            assert all(e["identity"] == events[0]["identity"] for e in events)
            assert events[-1]["event"] == "session_terminal"
        assert len(list(run.glob("*.jsonl"))) == 9
        manifest["outcome"] = "pass"
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
