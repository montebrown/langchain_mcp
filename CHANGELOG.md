# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Status Monitor**: Lightweight solution for monitoring MCP clients in real-time with uptime percentage tracking
- **Langchain.MCP.Client wrapper**: Decouples Anubis from application, removing dependency requirement
- **Automated release process**: CI workflow automation for streamlined publishing

### Changed

- **Default test server port**: Changed from 4000 to 5000 to avoid conflicts with Phoenix applications
- **Folder structure reorganization**: Flattened paths (`lib/langchain/mcp` → `langchain_mcp`, `test/langchain/mcp` → `test/langchain_mcp`)
- **Markdown formatting**: Auto-formatted documentation files using CommonMark standards

### Fixed

- ToolExecutor issues resolved
- Test flakiness problems fixed with centralized client management (`async: false` and proper cleanup)
- Registry test bleed eliminated through centralized deregistration
- Dialyzer type checking issues resolved
- Credo linting readability/refactoring opportunities addressed

## [0.1.0] - Initial release

### Added

- `LangChain.MCP.Adapter` for converting MCP tools to LangChain functions
- `LangChain.MCP.SchemaConverter` for JSON Schema to FunctionParam conversion
- `LangChain.MCP.ToolExecutor` for executing MCP tools
- `LangChain.MCP.ContentMapper` for multi-modal content mapping
- `LangChain.MCP.ErrorHandler` for error translation
- Fallback client support for resilient tool execution
- Configurable tool caching
- Test infrastructure with mcp/time Docker server
- Comprehensive documentation and examples
