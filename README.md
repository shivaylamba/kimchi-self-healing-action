# Kimchi Self-Healing Action

A GitHub Composite Action that automatically diagnoses and repairs failing CI pipelines using Kimchi's autonomous agent.

## What it does

1. Captures test failures and exit codes
2. Invokes Kimchi to analyze and fix the code
3. Re-runs tests to validate the fix
4. Checks that only allowed paths were modified
5. Opens a pull request if validation passes

> ⚠️ **Important:** `github-token` must be a **Personal Access Token (PAT)** with `repo` scope. The default `secrets.GITHUB_TOKEN` provided by GitHub Actions is **blocked** from creating pull requests.

## Usage

```yaml
- name: Self-healing via composite action
  if: steps.tests.outcome == 'failure'
  uses: shivaylamba/kimchi-self-healing-action@v1
  with:
    api-key: ${{ secrets.KIMCHI_API_KEY }}
    github-token: ${{ secrets.KIMCHI_PAT }}
    test-command: cd demo-app && npm test
    source-dir: demo-app
    kimchi-version: v0.1.21
```

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `api-key` | **Yes** | — | Kimchi API key |
| `github-token` | **Yes** | `${{ github.token }}` | GitHub token |
| `test-command` | **Yes** | — | Command to run tests |
| `source-dir` | **Yes** | `./` | Source directory |
| `allowed-paths` | No | `""` | Comma-separated glob list of allowed paths |
| `blocked-paths` | No | `.github/workflows/**,tests/**` | Comma-separated glob list of blocked paths |
| `kimchi-version` | **Yes** | — | Pinned Kimchi CLI version |
| `kimchi-sha256` | No | `""` | SHA-256 checksum of the tarball |
| `job-timeout` | No | `300` | Job timeout in seconds |

## Safety

- **Blocked paths** are never modified (`.github/workflows`, `tests`, etc.)
- **Allowed paths** restrict what Kimchi can touch
- **Validation gate** ensures tests pass before opening a PR
- **No sudo** is used during Kimchi installation
- **Version pinning** prevents unverified `latest` downloads

## License

MIT
