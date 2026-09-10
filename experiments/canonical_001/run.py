#!/usr/bin/env python3
"""Bounded custody and independent acceptance for the canonical input-delivery witness."""
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
    run = ROOT / "receipts" / ("canonical-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    run.mkdir()
    manifest = dict(start=now(), retries=0, outer_timeout_seconds=60,
        source_commit=subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT).decode().strip())
    env = os.environ.copy(); env.update(PTY_LAB_ROOT=str(ROOT),PTY_LAB_RUN=str(run))
    subject = ROOT / "target/debug/byte_witness"
    try:
        manifest["subject_sha256_before"] = digest(subject)
        result = subprocess.run(["mix","run",str(ROOT / "experiments/canonical_001/run.exs")],
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
            assert report["definition"]["order"] == ["canonical_on","canonical_off"]
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
                    assert bytes.fromhex(cell["requested_input_hex"]) == b"h\n"
                    assert bytes.fromhex(cell["observation"]["streams_hex"]["input_written"]) == b"h\n"
                    observed = cell["observation"]["terminal_observations"]
                    assert len(observed) == 1 and observed[0]["phase"] == "slave_before_spawn"
                    assert observed[0]["echo_mask"] == 8
                    assert observed[0]["canonical_mask"] == 256
                    assert observed[0]["vmin_index"] == 16 and observed[0]["vtime_index"] == 17
                    assert observed[0]["configuration"] == cell["observation"]["header"]["spec"]["terminal"]
                    raw = bytes.fromhex(cell["observation"]["streams_hex"]["pty_output"])
                    if cell["condition"] == "canonical_on":
                        assert raw == b"READY\r\nWINDOW NONE\r\nFINAL 680a\r\n"
                    else:
                        assert cell["condition"] == "canonical_off"
                        assert raw == b"READY\r\nWINDOW 68\r\nFINAL 680a\r\n"
                    writes = [e for e in events if e["event"] == "command" and e["data"]["command"] == "write"]
                    acks = [e for e in events if e["event"] == "helper_event" and e["data"]["event"] == "input_written"]
                    windows = [e for e in events if e["event"] == "canonical_window_observed"]
                    assert [bytes.fromhex(e["data"]["hex"]) for e in writes] == [b"h", b"\n"]
                    assert [bytes.fromhex(e["data"]["data"]["hex"]) for e in acks] == [b"h", b"\n"]
                    assert len(windows) == 1
                    assert writes[0]["seq"] < acks[0]["seq"] < windows[0]["seq"] < writes[1]["seq"] < acks[1]["seq"] < events[-1]["seq"]
                    output = b""
                    ready_seq = window_seq = None
                    for e in events:
                        if e["event"] == "helper_event" and e["data"]["event"] == "pty_output":
                            output += bytes.fromhex(e["data"]["data"]["hex"])
                            if ready_seq is None and b"READY\r\n" in output: ready_seq = e["seq"]
                            if window_seq is None and (b"WINDOW NONE\r\n" in output or b"WINDOW 68\r\n" in output): window_seq = e["seq"]
                    assert ready_seq < writes[0]["seq"]
                    assert acks[0]["seq"] < window_seq < windows[0]["seq"]
                    assert bytes.fromhex(windows[0]["data"]["hex"]) in [b"WINDOW NONE\r\n", b"WINDOW 68\r\n"]
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
        manifest["subject_sha256_after"] = digest(subject)
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
        manifest.update(outcome="pass", report_counts=checks, all_reported_pids_absent=sorted(pids), sessions=6)
    except subprocess.TimeoutExpired as error:
        (run / "mix.stdout").write_bytes(error.stdout or b""); (run / "mix.stderr").write_bytes(error.stderr or b"")
        manifest.update(outcome="outer_timeout",error=repr(error)); raise
    except Exception as error:
        manifest.update(outcome="failed",error=repr(error)); raise
    finally:
        manifest["end"]=now(); write_json(run / "manifest.json",manifest); seal(run); print(run)
if __name__ == "__main__": main()
