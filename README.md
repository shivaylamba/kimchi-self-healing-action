# Kimchi Self-Healing Action

A GitHub Composite Action that automatically diagnoses and repairs failing CI pipelines using [Kimchi](https://docs.kimchi.dev).

When your tests fail, this action:

1. Captures the failure output.
2. Installs the Kimchi CLI on the runner.
3. Runs Kimchi in headless / non-interactive mode to analyze the failure.
4. Applies the minimal code fix.
5. Re-runs tests to confirm the fix.
6. Creates a Pull Request with the proposed changes.

---

## Prerequisites

- A GitHub repository with a test suite.
- A Kimchi account and API key.
- `gh` CLI must be available on the runner (pre-installed on `ubuntu-latest`).

---

## Quick Start

### 1. Add the Kimchi API key as a repository secret

1. Go to **Settings → Secrets and variables → Actions** in your repo.
2. Click **New repository secret**.
3. Name: `KIMCHI_API_KEY`
4. Secret: your Kimchi API key.

### 2. Add the action to your workflow

Create or edit `.github/workflows/ci.yml`:

```yaml
name: CI with Self-Healing

on:
  push:
    branches: [main, master]

jobs:
  test-and-heal:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      # Example: set up Node.js for JavaScript projects
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm install

      - name: Run tests
        run: npm test
        continue-on-error: true

      - name: Self-Healing with Kimchi
        if: failure()
        uses: shivaylamba/kimchi-self-healing-action@v1
        with:
          api-key: ${{ secrets.KIMCHI_API_KEY }}
          test-command: 'npm test'
          working-directory: '.'
          branch-prefix: 'kimchi-auto-fix-'
          pr-title: '[Kimchi Auto-Fix] Resolve failing CI pipeline'
```

> **Note:** `continue-on-error: true` on the test step lets the workflow proceed to the self-healing action even when tests fail. The action detects failures from the captured log.

---

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-key` | **true** | — | Kimchi API key. Store as `KIMCHI_API_KEY` secret. |
| `test-command` | false | `npm test` | Command to run tests (e.g. `pytest`, `go test ./...`). |
| `working-directory` | false | `.` | Directory containing the code, relative to repo root. |
| `branch-prefix` | false | `kimchi-auto-fix-` | Prefix for the auto-fix branch name. |
| `pr-title` | false | `[Kimchi Auto-Fix] Resolve failing CI pipeline` | Title of the Pull Request. |
| `commit-message` | false | `[Kimchi Auto-Fix] ...` | Commit message body. |
| `safety-mode` | false | `true` | Enable safety guards during repair. |

---

## How It Works

```
Run tests  ──►  Capture failure log  ──►  Install Kimchi  ──►  Kimchi investigates & patches  ──►  Re-run tests  ──►  Create PR
```

### Safety

- The action temporarily writes `a-w` on `.github/workflows/` and `.git/` while Kimchi is running.
- Kimchi is instructed **not** to disable tests, remove assertions, or modify CI files.
- The action skips PR creation if no source changes were made.

---

## Permissions

Your workflow job needs:

```yaml
permissions:
  contents: write
  pull-requests: write
```

You may also need to enable **Allow GitHub Actions to create and approve pull requests** under **Settings → Actions → General → Workflow permissions**.

---

## Troubleshooting

### "GitHub Actions is not permitted to create or approve pull requests"

Go to **Settings → Actions → General → Workflow permissions** and enable:
- **Read and write permissions**
- **Allow GitHub Actions to create and approve pull requests**

### "Kimchi CLI is not installed"

The action downloads Kimchi from GitHub Releases automatically. If this fails, check that the runner has internet access and that `curl` is available.

### No PR created after tests fail

Check the **Run Kimchi repair agent** step logs. Kimchi may not have found a fix, or the `safety-mode` guards may have blocked unsafe edits. Look for `[run-kimchi] No changes were made by Kimchi.`

---

## License

MIT
