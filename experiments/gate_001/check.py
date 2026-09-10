#!/usr/bin/env python3
"""Bounded Phase B check against frozen Phase A data, with failure preservation."""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import time
from reference import ROOT, ENV, ARGV, SNAPSHOT, SCRATCH, digest, now, write_json, seal


def projection(observation):
    return {
        "controlling_tty": observation["controlling_tty"]["accessible"],
        "stdio": [dict(isatty=fd["isatty"]["value"], termios=fd["termios"],
                       dimensions=fd["dimensions"],
                       foreground_is_subject_group=fd["foreground_pgrp"].get("value") == observation["pgrp"])
                  for fd in observation["stdio"]],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    args = parser.parse_args()
    reference = args.reference.resolve()
    for name, expected in json.loads((reference / "SHA256.json").read_text()).items():
        if digest(reference / name) != expected:
            raise RuntimeError(f"reference integrity mismatch: {name}")
    manifest = json.loads((reference / "manifest.json").read_text())
    if manifest["outcome"] != "captured" or manifest["argv"] != ARGV or manifest["environment"] != ENV:
        raise RuntimeError("reference definition mismatch")
    if digest(Path(ARGV[0])) != manifest["executable_sha256"]:
        raise RuntimeError("probe binary differs from frozen reference; preserve and investigate")
    terminal = json.loads((reference / "terminal.json").read_text())
    pipe = json.loads((reference / "pipe.json").read_text())
    assert all(not fd["isatty"]["value"] for fd in pipe["stdio"])
    helper = ROOT / "target/debug/pty_helper"
    run = ROOT / "receipts" / ("gate-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    run.mkdir()
    SCRATCH.mkdir(exist_ok=True)
    config = {key: terminal["stdio"][0][key] for key in ["termios", "dimensions"]}
    write_json(run / "terminal-config.json", config)
    receipt = dict(schema=1, kind="phase-b-checkpoint", start=now(),
                   platform=platform.platform(), reference=str(reference.relative_to(ROOT)),
                   reference_manifest_sha256=digest(reference / "manifest.json"),
                   argv=ARGV, environment=ENV, environment_sha256=manifest["environment_sha256"],
                   cwd=str(ROOT), executable_sha256=digest(Path(ARGV[0])),
                   helper_sha256=digest(helper), helper_version=None, protocol_version=None,
                   source_commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
                   input_hex="", retries=0, cells=[])

    def cell(name, mode, subject, deadline=8000):
        if SNAPSHOT.exists():
            raise RuntimeError("unclaimed snapshot exists; refusing overwrite")
        command = [str(helper), str(run / "terminal-config.json"), mode, str(deadline), "--"] + subject
        record = dict(cell=name, start=now(), command=command, outer_deadline_seconds=10)
        receipt["cells"].append(record)
        try:
            result = subprocess.run(command, env=ENV, cwd=ROOT, input=b"", capture_output=True,
                                    start_new_session=True, timeout=10)
        except subprocess.TimeoutExpired as error:
            record.update(end=now(), outcome="outer_timeout")
            (run / f"{name}.stdout").write_bytes(error.stdout or b"")
            (run / f"{name}.stderr").write_bytes(error.stderr or b"")
            raise
        record.update(end=now(), helper_exit_code=result.returncode)
        (run / f"{name}.stdout").write_bytes(result.stdout)
        (run / f"{name}.stderr").write_bytes(result.stderr)
        events = [json.loads(line) for line in result.stderr.splitlines()]
        record["events"] = events
        # A PID is checked immediately, with reuse treated as a failure, never ignored.
        for event in events:
            if event["event"] == "spawned":
                version = event["helper_version"]
                assert receipt["helper_version"] in (None, version)
                receipt["helper_version"] = version
                try:
                    os.kill(event["pid"], 0)
                except ProcessLookupError:
                    record["child_absent_after_helper_exit"] = True
                else:
                    raise AssertionError(f"child PID still exists: {event['pid']}")
        observation = None
        if SNAPSHOT.exists():
            SNAPSHOT.rename(run / f"{name}.json")
            observation = json.loads((run / f"{name}.json").read_text())
        return result, events, observation

    try:
        result, events, slave = cell("slave", "slave", ARGV)
        assert result.returncode == 0 and slave is not None
        assert json.loads(result.stdout) == slave
        assert all(fd["isatty"]["value"] for fd in slave["stdio"])
        assert not slave["controlling_tty"]["accessible"]
        for fd, ref in zip(slave["stdio"], terminal["stdio"]):
            assert fd["termios"] == ref["termios"]
            assert fd["dimensions"] == ref["dimensions"]
        # Only advance after slave attachment is observed and checked.
        result, events, ctty = cell("ctty", "ctty", ARGV)
        assert result.returncode == 0 and ctty is not None
        assert json.loads(result.stdout) == ctty
        write_json(run / "comparison.json", {
            "kind": "interpretation", "reference_projection": projection(terminal),
            "helper_projection": projection(ctty),
            "equal": projection(ctty) == projection(terminal),
            "excluded": ["pid", "ppid", "absolute sid", "absolute pgrp", "session leadership"],
        })
        assert projection(ctty) == projection(terminal)

        # Mechanism failures: distinct cells, never retries of an observation.
        result, events, _ = cell("missing-executable", "ctty", ["/nonexistent/pty-lab-subject"])
        assert result.returncode == 125
        assert any(e["event"] == "os_error" and e["errno"] == 2 for e in events)
        result, events, _ = cell("deadline", "ctty", ["/bin/sleep", "30"], deadline=50)
        assert result.returncode == 125
        assert any(e["event"] == "timeout" for e in events)
        assert not any(e["event"].startswith("cleanup_") for e in events)
        result, events, _ = cell("exit-seven", "ctty", ["/bin/sh", "-c", "exit 7"])
        assert result.returncode == 7
        assert any(e["event"] == "child_exit" and e["code"] == 7 for e in events)
        receipt["outcome"] = "pass"
    except Exception as error:
        receipt.update(outcome="failed", error=repr(error))
        if SNAPSHOT.exists():
            SNAPSHOT.rename(run / "unclaimed-observation.json")
        raise
    finally:
        receipt["end"] = now()
        write_json(run / "manifest.json", receipt)
        seal(run)
        print(run)


if __name__ == "__main__":
    main()
