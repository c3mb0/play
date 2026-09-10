#!/usr/bin/env python3
"""External 60-second watchdog/custody for the Elixir experiment API acceptance."""
import hashlib
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
    run = ROOT / "receipts" / ("elixir-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    run.mkdir()
    manifest = dict(start=now(), retries=0, outer_timeout_seconds=60,
        source_commit=subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT).decode().strip())
    env = os.environ.copy(); env.update(PTY_LAB_ROOT=str(ROOT),PTY_LAB_RUN=str(run))
    try:
        result = subprocess.run(["mix","run",str(ROOT / "experiments/elixir_001/run.exs")],
            cwd=ROOT / "elixir/pty_lab_ex",env=env,capture_output=True,timeout=56)
        (run / "mix.stdout").write_bytes(result.stdout); (run / "mix.stderr").write_bytes(result.stderr)
        manifest["mix_exit_code"] = result.returncode
        if result.returncode: raise RuntimeError("Elixir acceptance failed; inspect reports and mix.stdout")
        pids = set()
        checks = {}
        for case,expected in {"normal":["pass"]*3,"mismatch":["pass","mismatch","pass"],
                              "execution-failure":["pass","execution_failure","pass"]}.items():
            report_file = run / case / "report.json"
            assert digest(report_file) == Path(str(report_file)+".sha256").read_text().strip()
            report = json.loads(report_file.read_text())
            assert [pair["outcome"] for pair in report["pairs"]] == expected
            assert report["definition"]["max_concurrency"] == 2
            assert report["definition"]["order"] == ["pipe","slave"]
            checks[case] = report["counts"]
            for pair in report["pairs"]:
                for cell in pair["cells"]:
                    journal = Path(cell["receipt"])
                    assert digest(journal) == cell["observation"]["sha256"]
                    assert digest(journal) == Path(str(journal)+".sha256").read_text().strip().lower()
                    events = [json.loads(line) for line in journal.read_bytes().splitlines()]
                    assert events[-1]["event"] == "session_terminal"
                    for event in events:
                        if event["event"] == "port_open": pids.add(event["data"]["helper_pid"])
                        if event["event"] == "helper_event" and event["data"]["event"] == "spawned":
                            pids.update(event["data"]["data"][k] for k in ["helper_pid","guardian_pid","pid"])
        cleanup_deadline = time.monotonic()+3
        while True:
            alive=[]
            for pid in pids:
                try: os.kill(pid,0)
                except ProcessLookupError: pass
                else: alive.append(pid)
            if not alive: break
            if time.monotonic() >= cleanup_deadline: raise AssertionError(f"remaining PIDs: {alive}")
            time.sleep(0.01)
        manifest.update(outcome="pass", report_counts=checks, all_reported_pids_absent=sorted(pids), sessions=18)
    except subprocess.TimeoutExpired as error:
        (run / "mix.stdout").write_bytes(error.stdout or b""); (run / "mix.stderr").write_bytes(error.stderr or b"")
        manifest.update(outcome="outer_timeout",error=repr(error)); raise
    except Exception as error:
        manifest.update(outcome="failed",error=repr(error)); raise
    finally:
        manifest["end"]=now(); write_json(run / "manifest.json",manifest); seal(run); print(run)
if __name__ == "__main__": main()
