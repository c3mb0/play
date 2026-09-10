#!/usr/bin/env python3
"""Bounded custody and independent acceptance for the installed ls witness."""
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
    run = ROOT / "receipts" / ("ls-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    run.mkdir()
    manifest = dict(start=now(), retries=0, outer_timeout_seconds=60,
        source_commit=subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT).decode().strip())
    env = os.environ.copy(); env.update(PTY_LAB_ROOT=str(ROOT),PTY_LAB_RUN=str(run))
    fixture = ROOT / "experiments/ls_001/fixture"
    def snapshot():
        return {p.name: dict(regular=p.is_file() and not p.is_symlink(),
                            mode=p.stat().st_mode, size=p.stat().st_size, sha256=digest(p))
                for p in sorted(fixture.iterdir())}
    try:
        before = snapshot()
        write_json(run / "fixture-before.json", before)
        assert set(before) == {"alpha", "bravo", "charlie"}
        assert all(v["regular"] and v["size"] == 0 for v in before.values())
        manifest["subject_sha256_before"] = digest(Path("/bin/ls"))
        manual = subprocess.run(["/bin/bash", "-c", "man ls | col -b"],
                                capture_output=True, timeout=3, check=True).stdout.decode()
        lines = manual.splitlines()
        selected = []
        for index, line in enumerate(lines):
            if "Force multi-column output" in line or "Force output to be one entry per line" in line:
                selected.extend(lines[index:index+2])
        (run / "installed-manual-excerpt.txt").write_text("\n".join(selected)+"\n")
        result = subprocess.run(["mix","run",str(ROOT / "experiments/ls_001/run.exs")],
            cwd=ROOT / "elixir/pty_lab_ex",env=env,capture_output=True,timeout=53)
        (run / "mix.stdout").write_bytes(result.stdout); (run / "mix.stderr").write_bytes(result.stderr)
        manifest["mix_exit_code"] = result.returncode
        if result.returncode: raise RuntimeError("Elixir acceptance failed; inspect reports and mix.stdout")
        pids = set()
        checks = {}
        for case,expected in {"pairs":["pass"]*3}.items():
            report_file = run / case / "report.json"
            assert digest(report_file) == Path(str(report_file)+".sha256").read_text().strip()
            report = json.loads(report_file.read_text())
            assert [pair["outcome"] for pair in report["pairs"]] == expected
            assert report["definition"]["max_concurrency"] == 2
            assert report["definition"]["order"] == ["pipe","slave"]
            checks[case] = report["counts"]
            intervals = []
            identities = []
            for pair in report["pairs"]:
                pair_intervals = []
                for cell in pair["cells"]:
                    journal = Path(cell["receipt"])
                    assert digest(journal) == cell["observation"]["sha256"]
                    assert digest(journal) == Path(str(journal)+".sha256").read_text().strip().lower()
                    events = [json.loads(line) for line in journal.read_bytes().splitlines()]
                    assert events[-1]["event"] == "session_terminal"
                    identities.append(json.dumps(cell["identity"], sort_keys=True))
                    start = events[0]["unix_ns"]
                    end = events[-1]["unix_ns"]
                    assert end >= start
                    pair_intervals.append((start, end))
                    intervals.extend([(start, 1), (end, -1)])
                    assert cell["requested_input_hex"] == ""
                    assert cell["observation"]["streams_hex"]["input_written"] == ""
                    assert bytes.fromhex(cell["observation"]["header"]["executable"]["sha256"]) == bytes.fromhex(manifest["subject_sha256_before"])
                    for event in events:
                        if event["event"] == "port_open": pids.add(event["data"]["helper_pid"])
                        if event["event"] == "helper_event" and event["data"]["event"] == "spawned":
                            pids.update(event["data"]["data"][k] for k in ["helper_pid","guardian_pid","pid"])
                assert pair_intervals[0][1] <= pair_intervals[1][0]
            assert len(set(identities)) == 6
            active = maximum = 0
            for _, delta in sorted(intervals):
                active += delta
                maximum = max(maximum, active)
            assert active == 0 and maximum <= 2
            manifest["maximum_observed_concurrent_sessions"] = maximum
        after = snapshot()
        write_json(run / "fixture-after.json", after)
        assert before == after
        manifest["subject_sha256_after"] = digest(Path("/bin/ls"))
        assert manifest["subject_sha256_before"] == manifest["subject_sha256_after"]
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
        manifest.update(outcome="pass", report_counts=checks, all_reported_pids_absent=sorted(pids), sessions=6, fixture_unchanged=True)
    except subprocess.TimeoutExpired as error:
        (run / "mix.stdout").write_bytes(error.stdout or b""); (run / "mix.stderr").write_bytes(error.stderr or b"")
        manifest.update(outcome="outer_timeout",error=repr(error)); raise
    except Exception as error:
        manifest.update(outcome="failed",error=repr(error)); raise
    finally:
        manifest["end"]=now(); write_json(run / "manifest.json",manifest); seal(run); print(run)
if __name__ == "__main__": main()
