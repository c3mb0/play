#!/usr/bin/env python3
"""Independent watchdog, evidence custody and fixture-only emergency cleanup."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'experiments/gate_001'))
from reference import now, write_json, seal, digest


RUN_DEADLINE = None

def process(pid):
    remaining = 1 if RUN_DEADLINE is None else min(1, RUN_DEADLINE - time.monotonic())
    if remaining <= 0:
        raise TimeoutError('outer observation deadline')
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'comm='], capture_output=True, timeout=remaining)
    return result.stdout.decode().strip() if result.returncode == 0 else None


def known_processes(run):
    known = {}
    custody = run / 'custody.jsonl'
    if custody.exists():
        for line in custody.read_bytes().splitlines():
            try:
                row = json.loads(line)
                known[row['pid']] = row['executable']
            except (ValueError, KeyError):
                continue  # Original torn bytes remain evidence, never repaired.
    for file in run.glob('*/holder.pid'):
        known[int(file.read_text().strip())] = str(ROOT / 'target/debug/operator_subject')
    # Recover already-reported IDs even if the caller died before custody logging.
    for file in run.glob('*/session.jsonl'):
        for line in file.read_bytes().splitlines():
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get('event') == 'port_open':
                known[row['data']['helper_pid']] = str(ROOT / 'target/debug/pty_helper')
            if row.get('event') == 'helper_event' and row['data']['event'] == 'spawned':
                data = row['data']['data']
                for key in ['helper_pid', 'guardian_pid']:
                    known[data[key]] = str(ROOT / 'target/debug/pty_helper')
                known[data['pid']] = '/bin/cat' if file.parent.name == 'input_wait' else str(ROOT / 'target/debug/operator_subject')
    return known


def cleanup(run):
    actions = []
    known = known_processes(run)
    for pid, executable in known.items():
        current = process(pid)
        if current is None:
            continue
        if current != executable:
            actions.append(dict(pid=pid, outcome='identity_mismatch_not_signalled', observed=current, expected=executable))
            continue
        # Fixture-only fallback: do not leave a stopped guardian or bounded holder.
        for sig in [signal.SIGCONT, signal.SIGKILL]:
            try:
                os.kill(pid, sig)
                actions.append(dict(pid=pid, signal=sig.name, outcome='sent', observed=current))
            except ProcessLookupError:
                actions.append(dict(pid=pid, signal=sig.name, outcome='already_absent'))
    deadline = min(time.monotonic() + 3, RUN_DEADLINE)
    while True:
        remaining = [pid for pid in known if process(pid) is not None]
        if not remaining or time.monotonic() >= deadline:
            return dict(actions=actions, known_pids=sorted(known), remaining=remaining)
        time.sleep(.02)


def main():
    global RUN_DEADLINE
    RUN_DEADLINE = time.monotonic() + 59
    run = ROOT / 'receipts' / ('operator-' + time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()))
    run.mkdir()
    manifest = dict(start=now(), retries=0, outer_timeout_seconds=60,
                    source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip())
    env = os.environ.copy()
    env.update(PTY_LAB_ROOT=str(ROOT), PTY_LAB_RUN=str(run))
    failure = None
    try:
        result = subprocess.run(['mix', 'run', str(ROOT / 'experiments/operator_001/run.exs')],
                                cwd=ROOT / 'elixir/pty_lab_ex', env=env, capture_output=True, timeout=45)
        (run / 'mix.stdout').write_bytes(result.stdout)
        (run / 'mix.stderr').write_bytes(result.stderr)
        manifest['mix_exit_code'] = result.returncode
        if result.returncode:
            raise RuntimeError('operator exhibit failed; original evidence retained')
        report = json.loads((run / 'report.json').read_text())
        expected = ['input_wait', 'blocked_output', 'stopped', 'held_output', 'caller_death', 'worker_death_descendant']
        assert [case['case'] for case in report['cases']] == expected
        for case in report['cases']:
            assert case['acceptance'] == 'pass'
            journal = Path(case['receipt'])
            assert digest(journal) == Path(str(journal) + '.sha256').read_text().strip().lower()
            events = [json.loads(line) for line in journal.read_bytes().splitlines()]
            assert events[-1]['event'] == 'session_terminal'
            assert all(e['identity'] == case['identity'] for e in events)
        actions = [json.loads(line) for line in (run / 'interventions.jsonl').read_bytes().splitlines()]
        requests = {a['action_id']: a for a in actions if a['phase'] == 'request'}
        responses = {a['action_id']: a for a in actions if a['phase'] == 'response'}
        assert requests.keys() == responses.keys()
        assert all(requests[k]['sequence'] < responses[k]['sequence'] for k in requests)
        assert any(a.get('response') == '{:error, :session_closed}' for a in responses.values())
        manifest.update(outcome='pass', cases=expected, sessions=6, intervention_requests=len(requests))
    except subprocess.TimeoutExpired as error:
        (run / 'mix.stdout').write_bytes(error.stdout or b'')
        (run / 'mix.stderr').write_bytes(error.stderr or b'')
        failure = error
        manifest.update(outcome='outer_timeout', error=repr(error))
    except Exception as error:
        failure = error
        manifest.update(outcome='failed', error=repr(error))
    finally:
        try:
            observed = cleanup(run)
            write_json(run / 'independent-cleanup.json', observed)
            # An emergency intervention is preserved, but never converted into success.
            if observed['actions'] or observed['remaining']:
                manifest.update(outcome='failed', cleanup_required=True)
                failure = failure or RuntimeError('emergency cleanup required')
            manifest['known_pids_absent'] = observed['known_pids'] if not observed['remaining'] else []
        except Exception as error:
            manifest.update(outcome='cleanup_failed', cleanup_error=repr(error))
            failure = failure or error
        manifest['end'] = now()
        write_json(run / 'manifest.json', manifest)
        seal(run)
        print(run)
    if failure:
        raise failure

if __name__ == '__main__':
    main()
