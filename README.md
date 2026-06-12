# prbuff

AI code review for your pull requests. Add one workflow, drop in an API key, and prbuff posts inline and summary review comments on your PRs.

## Quick start

1. Get an API key from prbuff and store it as a repository secret named `PRBUFF_API_KEY`.
2. Add `.github/workflows/prbuff.yml`:

```yaml
name: prbuff review
on:
  pull_request:

permissions:
  contents: read
  pull-requests: write   # required so prbuff can post review comments

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: sigiuscom/prbuff-action@v1
        with:
          api-key: ${{ secrets.PRBUFF_API_KEY }}
          review-command: run-summary
```

The default `GITHUB_TOKEN` is passed automatically; you do not provide it.

## Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `api-key` | (required) | Your prbuff API key |
| `review-command` | `run-summary` | Review mode (see below) |
| `pull-request-number` | triggering PR | PR number to review |
| `api-url` | `https://api.prbuff.com` | prbuff API base URL |

## Review commands

| Command | What it does |
|---------|--------------|
| `run` | Full review (inline + summary) |
| `run-inline` | Line-by-line comments on the diff |
| `run-context` | Cross-file analysis |
| `run-summary` | High-level summary comment |
| `run-inline-reply` | Reply within an inline thread |
| `run-summary-reply` | Reply within the summary thread |

## Troubleshooting

- **`review failed` with a permissions hint** — add `permissions: pull-requests: write` to the workflow. The default token is read-only in many orgs.
- **`pull_request_target is not supported`** — trigger on `pull_request`, not `pull_request_target`.
- **No comments appear, status succeeded** — the service may be in dry-run mode; the log line will say so.

Every review prints a run id; include it when contacting support.
