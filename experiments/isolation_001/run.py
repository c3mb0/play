#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
import time
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "experiments/gate_001"))
from reference import now, write_json, seal

def main():
    run = ROOT / "receipts" / ("isolation-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    run.mkdir()
    manifest = dict(start=now(), retries=0, source_commit=subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT).decode().strip())
    env = os.environ.copy(); env.update(PTY_LAB_ROOT=str(ROOT), PTY_LAB_RUN=str(run))
    args = ["erl","-noshell","-pa",str(ROOT / "erlang/pty_lab/_build/default/lib/pty_lab/ebin"),"-eval",
            'try isolation_experiment:run(os:getenv("PTY_LAB_ROOT"),os:getenv("PTY_LAB_RUN")) of ok -> halt(0) catch C:R:S -> io:format("~p:~p~n~p~n",[C,R,S]),halt(1) end.']
    try:
        result = subprocess.run(args,env=env,cwd=ROOT,capture_output=True,timeout=60)
        (run / "beam.stdout").write_bytes(result.stdout); (run / "beam.stderr").write_bytes(result.stderr)
        manifest["beam_exit_code"] = result.returncode
        if result.returncode: raise RuntimeError("isolation acceptance failed; inspect preserved evidence")
        manifest["outcome"] = "pass"
    except subprocess.TimeoutExpired as error:
        (run / "beam.stdout").write_bytes(error.stdout or b""); (run / "beam.stderr").write_bytes(error.stderr or b"")
        manifest.update(outcome="outer_timeout",error=repr(error)); raise
    except Exception as error:
        manifest.update(outcome="failed",error=repr(error)); raise
    finally:
        manifest["end"] = now(); write_json(run / "manifest.json",manifest); seal(run); print(run)
if __name__ == "__main__": main()
