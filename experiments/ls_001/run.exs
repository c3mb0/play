root = System.fetch_env!("PTY_LAB_ROOT")
directory = System.fetch_env!("PTY_LAB_RUN")
{:ok, report} = PtyLab.Experiment.run_ls_pairs(%{
  root: root, directory: Path.join(directory, "pairs"), pairs: 3, max_concurrency: 2
})
actual = Enum.map(report.pairs, & &1.outcome)
IO.puts("ls: #{Enum.join(actual, ", ")}")
unless actual == ["pass", "pass", "pass"], do: raise("ls witness did not pass")
