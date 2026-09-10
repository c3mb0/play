root = System.fetch_env!("PTY_LAB_ROOT")
directory = System.fetch_env!("PTY_LAB_RUN")

cases = [
  {"normal", %{}, ["pass", "pass", "pass"]},
  {"mismatch", %{input_overrides: %{2 => "oops\n"}}, ["pass", "mismatch", "pass"]},
  {"execution-failure", %{executable_overrides: %{2 => "/nonexistent/pty-lab-subject"}},
   ["pass", "execution_failure", "pass"]}
]

Enum.each(cases, fn {name, overrides, expected} ->
  options =
    Map.merge(
      %{
        root: root,
        directory: Path.join(directory, name),
        name: name,
        pairs: 3,
        max_concurrency: 2
      },
      overrides
    )

  {:ok, report} = PtyLab.Experiment.run_hello_pairs(options)
  actual = Enum.map(report.pairs, & &1.outcome)

  if actual != expected,
    do: raise("#{name}: expected #{inspect(expected)}, got #{inspect(actual)}")

  cells = Enum.flat_map(report.pairs, & &1.cells)
  identities = Enum.map(cells, & &1.identity)
  if length(Enum.uniq(identities)) != 6, do: raise("duplicate cell identity")

  Enum.each(cells, fn cell ->
    unless File.exists?(cell.receipt), do: raise("missing receipt #{cell.receipt}")
    unless cell.observation.analysis.integrity == "verified", do: raise("unverified receipt")
  end)

  if name == "mismatch" do
    checks = Enum.at(report.pairs, 1).checks

    unless checks.same_input and checks.same_definition and not checks.declared_input,
      do: raise("fault must preserve matching input and violate the declared expectation")
  end

  IO.puts("#{name}: #{Enum.join(actual, ", ")}")
end)

existing = Path.join(directory, "normal/report.json")
before = File.read!(existing)

rejected =
  try do
    PtyLab.Experiment.run_hello_pairs(%{root: root, directory: Path.join(directory, "normal")})
    false
  rescue
    MatchError -> true
  end

unless rejected and before == File.read!(existing),
  do: raise("existing report directory was overwritten")
