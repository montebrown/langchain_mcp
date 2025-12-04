defmodule Mix.Tasks.QualityCheck do
  @moduledoc """
  Runs all quality checks: format, linting, type checking, and tests.

  ## Usage

      mix quality_check

  This runs the same checks as CI:
  - Code formatting validation
  - Credo linting (strict mode)
  - Dialyzer type checking  
  - Unit tests (excludes live_call integration tests)

  Use before committing to ensure code meets quality standards.
  """

  @shortdoc "Run all quality checks"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    IO.puts("🔍 Running quality checks...\n")

    check_formatting()
    check_linting()
    check_types()
    run_tests()

    IO.puts("\n🎉 All quality checks passed!")
  end

  defp check_formatting do
    IO.puts("📋 Checking formatting...")

    if Mix.shell().cmd("mix format --check-formatted") != 0 do
      IO.puts("�️ Formatting issues found - run 'mix format' to fix")
      System.halt(1)
    else
      IO.puts("✅ Formatting OK")
    end
  end

  defp check_linting do
    IO.puts("\n🔋 Running Credo linting...")

    if Mix.shell().cmd("mix credo --strict") != 0 do
      IO.puts("�️ Linting issues found - run 'mix credo' to see details")
      System.halt(1)
    else
      IO.puts("✅ Code quality OK")
    end
  end

  defp check_types do
    IO.puts("\n🔋 Running Dialyzer type checking...")

    if Mix.shell().cmd("mix dialyzer") != 0 do
      IO.puts("�️ Type issues found - run 'mix dialyzer' to see details")
      System.halt(1)
    else
      IO.puts("✅ Type checking OK")
    end
  end

  defp run_tests do
    IO.puts("\n🧪 Running unit tests...")
    {_, exit_code} = System.cmd("mix", ["test", "--exclude", "live_call"])

    if exit_code != 0 do
      IO.puts("�️ Test failures - check output above")
      System.halt(1)
    else
      IO.puts("✅ All tests pass")
    end
  end
end
