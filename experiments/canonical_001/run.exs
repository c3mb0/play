root = System.fetch_env!("PTY_LAB_ROOT")
directory = System.fetch_env!("PTY_LAB_RUN")
{:ok, report} = PtyLab.Experiment.run_canonical_pairs(%{
  root: root, directory: Path.join(directory, "pairs"), pairs: 3, max_concurrency: 2
})
actual = Enum.map(report.pairs, & &1.outcome)
IO.puts("canonical: #{Enum.join(actual, ", ")}")
unless actual == ["pass", "pass", "pass"], do: raise("canonical witness did not pass")
