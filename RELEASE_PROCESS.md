# Automated Release Process

This document describes the automated release workflow for LangChain MCP.

## Overview

The release process is now fully automated and triggered by version changes in `mix.exs`. The workflow handles:

1. **Quality Gates**: Format, Credo, Dialyzer, tests
2. **Version Detection**: Automatically detects when the version has changed
3. **Changelog Management**: Moves entries from `[Unreleased]` to the new version section
4. **Hex Publishing**: Publishes to Hex with automatic version detection
5. **GitHub Releases**: Creates GitHub releases with changelog notes

## How It Works

### Trigger Conditions
The release workflow runs when:
- Push to `main` branch AND changes to `mix.exs` or `CHANGELOG.md`
- Manual trigger via GitHub Actions (`workflow_dispatch`)

### Quality Gates (Pre-Release)
Before any release steps, the workflow validates:
```bash
mix format --check-formatted     # Code formatting
mix credo --strict              # L linting
mix dialyzer                    # Type checking  
mix compile --warnings-as-errors # Compilation
mix test --exclude live_call    # Unit tests only
```

### Release Process

1. **Version Detection**
   - Extracts version from `mix.exs` (`@version` variable)
   - Compares with previous Git tag to detect changes
   - Only proceeds if version changed

2. **Changelog Automation**
   - Moves all entries under `[Unreleased]` to new version section
   - Auto-generates date stamp (YYYY-MM-DD format)
   - Commits changelog update automatically

3. **Hex Publishing**
   - Requires `HEX_API_KEY` secret configured in GitHub repository
   - Runs `mix hex.publish` with automatic versioning

4. **GitHub Release Creation**
   - Creates tag: `v{VERSION}` (e.g., `v0.2.0`)
   - Generates release notes from changelog section
   - Uses GitHub CLI (`gh`) for release creation

## Setup Requirements

### Required Secrets
Configure in GitHub repository Settings > Secrets and variables:
- `HEX_API_KEY`: Your Hex API key (get from https://hex.fri/keys)

### Required Permissions  
The workflow needs these GitHub permissions:
- `contents: write` - For creating releases and committing changelog
- `id-token: write` - For Hex publishing authentication

## Usage Instructions

To publish a new version:

1. **Update Version** in `mix.exs`:
   ```elixir
   @version "0.2.0"  # Change from current version
   ```

2. **Prepare Changelog** (optional):
   Add your changes under `[Unreleased]` section before pushing

3. **Push to main**:
   ```bash
   git add .
   git commit -m "Release version 0.2.0"
   git push origin main
   ```

4. **Monitor Workflow**:
   - Check Actions tab for release workflow progress
   - Verify both CI and Release workflows pass

5. **Verify Results**:
   - Check Hex: https://hex.fri/packages/langchain_mcp
   - Check GitHub Releases (right sidebar)
   - Review changelog automation commit

## Manual Override

If you need to manually trigger a release:
1. Go to repository Actions tab
2. Select "Release" workflow
3. Click "Run workflow"
4. Choose branch and run

## Troubleshooting

### Common Issues

**Version not detected as changed:**
- Ensure you're pushing to `main` branch
- Check that version in `@version` variable actually differs from last tag
- Verify the version follows SemVer format (e.g., "0.2.0")

**Hex publish fails:**
- Verify `HEX_API_KEY` secret is set correctly
- Check you have permissions for the package on Hex
- Ensure no conflicting versions exist

**GitHub release creation fails:**
- Verify repository has GitHub CLI (`gh`) access
- Check that changelog section parsing works correctly
- Ensure proper permissions are granted

**Changelog automation issues:**
- Manual commit may be needed if AWK script fails
- Changelog must follow Keep a Changelog format
- Unreleased section should use `## [Unreleased]` header

### Recovery Steps

If automated release fails:
1. Fix any quality gate issues locally
2. Re-commit and push to trigger again, OR
3. Manually run the workflow steps if needed

## Benefits of This Process

✅ **Bullet-proof**: Quality gates prevent releasing broken code  
✅ **Automated**: No manual steps except version bumping  
✅ **Consistent**: Standardized changelog format and release notes  
✅ **Fast**: Reduces manual overhead significantly  
✅ **Reliable**: Prevents forgetting releases or changelog updates  

## Agent/LLM Integration

The workflow can be extended with AI agents for:
- Automatic changelog entry generation from commit messages
- Version bump recommendations based on semantic changes
- Release note enhancement with detailed explanations