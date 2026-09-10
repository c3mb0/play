#!/bin/bash
cd /Users/cem/play/pty-lab || exit 99
/bin/stty rows 24 cols 80 || exit 98
/usr/bin/env -i PATH=/usr/bin:/bin LANG=C TERM=xterm-256color /Users/cem/play/pty-lab/target/debug/topology_probe --snapshot /Users/cem/play/pty-lab/experiments/gate_001/scratch/observation.json
printf '%s\n' "$?" > /Users/cem/play/pty-lab/experiments/gate_001/scratch/terminal.exit
