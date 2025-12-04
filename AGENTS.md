# Agent Guidelines for LangChain MCP

## Build/Lint/Test Commands

**Primary Commands:**

- `mix test` - Run all tests
- `mix test --exclude live_call` - Run only unit tests
- `mix test test/specific_test.exs` - Run single test file
- `mix format --check-formatted` - Check code formatting
- `mix test --cover --exclude live_call` - check code coverage  
- `mix quality_check` - Run all quality checks (format, credo, dialyzer, tests)
- `mix credo --strict` - Run linting checks
- `mix dialyzer` - Run type checking
- `mix compile --warnings-as-errors` - Compile with strict warnings

**Integration Tests:**

```bash
# Terminal 1: Start test server
mix test_server

# Terminal 2: Run integration tests
mix test --include live_call
```

## Code Style Guidelines

**Formatting:**

- Line length: 100 characters (`.formatter.exs`)
- Use `mix format` for consistent formatting

**Testing:**

- Unit tests use `Mimic` for mocking, tagged `:live_call` for integration tests
- Tests in `test/` directory follow ExUnit patterns
- Integration tests require running test server (`mix test_server`)

**Architecture:**

- Core modules: `LangChain.MCP.*` (Adapter, Config, SchemaConverter, ContentMapper)
- Use proper error handling with `{:ok, _}` / `{:error, _}` tuples
- Follow Elixir naming conventions: snake_case functions, PascalCase modules

**Dependencies:**

- Uses `:langchain`, `:anubis_mcp`, `:credo`, `:dialyxir`
- Dev/test deps include mocking (`:mimic`) and docs (`:ex_doc`)
