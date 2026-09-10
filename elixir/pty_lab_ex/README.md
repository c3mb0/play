# Bounded witness experiment API

Elixir defines and compares experiments; Erlang owns sessions and raw receipts;
Rust owns process and terminal mechanisms. This layer adds no OS control code.

From the repository root, with Rust, OTP, rebar3 and Elixir on PATH:

```sh
make elixir-build
make elixir-test
make elixir-check
```

The acceptance command creates new evidence for three normal pairs and separate
three-pair mismatch and execution-failure experiments. It has a 60-second outer
bound, including cleanup verification. It never retries an experiment.

For a single experiment, start `iex -S mix` in this directory after building:

```elixir
root = Path.expand("../..")
PtyLab.Experiment.run_hello_pairs(%{
  root: root,
  directory: Path.join(root, "receipts/my-first-pairs"),
  name: "hello_pairs",
  pairs: 3,
  max_concurrency: 2
})
```

The output directory must not exist and its parent must exist. Use a unique
basename per run: that basename supplies the run identity. Pair counts are
bounded to 1..100 and concurrency to 1..4. Each pair executes pipe then PTY slave;
pairs may overlap. Each session has a five-second Erlang deadline; each pair task
has a twenty-second bound. The API itself has no single whole-experiment deadline.

The executable, argv, environment, cwd, input and frozen terminal configuration
are matched. Input is requested 100 ms after receiving spawned; this fixes a
policy, not scheduler timing. Expected input is `hello\n`. Exact pipe and PTY
output predicates retain echo and CRLF bytes, allowing the two declared prompt/
echo orders. Optional `input_overrides: %{2 => "oops\n"}` and
`executable_overrides: %{2 => "/nonexistent/pty-lab-subject"}` affect both cells
of that numbered pair and exist for explicit anomaly experiments.

The returned map and exclusive read-only `report.json` distinguish `pass`,
`mismatch` and `execution_failure`. Any anomalous pair makes the experiment
outcome `anomalies`; remaining pairs still run. Raw Erlang journals and seals
remain separate from this interpretation and are never normalized or repaired.
A missing/incomplete receipt cannot become a behavioral mismatch. Reusing an
output directory raises instead of overwriting evidence.

Report cleanup fields remain unverified: a session result is not proof of OS
process absence. The external acceptance runner independently checks reported
PIDs. These are local checksummed artifacts, not WORM storage. The hello-world API validates its
constructed witness on macOS; this is not a general experiment DSL.

## Installed ls witness

`PtyLab.Experiment.run_ls_pairs/1` takes the same root, fresh directory, name,
pairs and max_concurrency options. It uses `/bin/ls`, empty argv, the committed
`experiments/ls_001/fixture` directory, and no input writes or input delay.
Its predicate requires one filename per pipe line and a single PTY row separated
by ASCII spaces/tabs. All raw bytes remain in the journals. Use `make ls-check`
for the outer fixture, subject fingerprint, scheduling and process-absence checks.
Those checks are acceptance-runner responsibilities, not claims made by calling
the Elixir function alone. The installed macOS ls witness now joins the
constructed hello-world witness; other platforms remain untested.

## PTY echo witness

`PtyLab.Experiment.run_echo_pairs/1` uses the same options with conditions echo_on
then echo_off. Both attach the existing hello_witness through a PTY slave. The
macOS-only experiment clears just ECHO (0x8) and its redundant configuration
boolean for the second cell; ICANON and all other terminal settings stay fixed.
Input/timing matches run_hello_pairs. Rust's pre-spawn slave readback must match
both requested configurations, including its native ECHO mask. Calling this API
on another OS is explicitly rejected rather than assuming portable flag numbers.

`make echo-check` adds external receipt/subject-hash, ordering/concurrency and
bounded PID checks. It preserves exact PTY bytes and the two predeclared echo-on
prompt orders. The inherited pipe_output predicate name means the control output
for this PTY/PTY experiment; cell condition and actual attachment are recorded
separately. No canonical/raw, resize, EOF or signal matrix has been implemented.
