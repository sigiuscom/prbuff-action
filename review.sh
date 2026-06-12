#!/usr/bin/env bash
# prbuff review action: submit a review request and poll for the result.
#
# Reads config from PRBUFF_* env (set by action.yml). Never echoes secrets.
set -euo pipefail

# Mask secrets in workflow logs regardless of provider behaviour.
echo "::add-mask::${PRBUFF_API_KEY}"
echo "::add-mask::${PRBUFF_GH_TOKEN}"

# Reject pull_request_target: a malicious PR author could otherwise drive the
# action with an elevated token context (failure C4).
if [ "${PRBUFF_EVENT}" = "pull_request_target" ]; then
  echo "prbuff: pull_request_target is not supported; use pull_request" >&2
  exit 1
fi

# Fail fast when not running on a PR (failure L2).
if [ -z "${PRBUFF_PR:-}" ] || [ "${PRBUFF_PR}" = "null" ]; then
  echo "prbuff: pull-request-number is required when not running on a pull_request event" >&2
  exit 1
fi

api="${PRBUFF_API_URL%/}"
poll_timeout="${PRBUFF_POLL_TIMEOUT:-900}"   # 15 min
interval=10

body=$(cat <<JSON
{"owner":"${PRBUFF_OWNER}","repo":"${PRBUFF_REPO}","pull_number":${PRBUFF_PR},"command":"${PRBUFF_COMMAND}","head_sha":"${PRBUFF_HEAD_SHA}","github_token":"${PRBUFF_GH_TOKEN}"}
JSON
)

create() {
  curl -sS -w '\n%{http_code}' -X POST "${api}/v1/reviews" \
    -H "Authorization: Bearer ${PRBUFF_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${body}"
}

# --- submit, retrying on 429 (queue full) within the overall timeout (M11)
deadline=$(( SECONDS + poll_timeout ))
while :; do
  resp=$(create)
  code=$(printf '%s' "$resp" | tail -n1)
  json=$(printf '%s' "$resp" | sed '$d')
  if [ "$code" = "429" ]; then
    echo "prbuff: review queue is full, retrying..."
    sleep "$interval"; [ "$SECONDS" -lt "$deadline" ] && continue
    echo "prbuff: queue stayed full until timeout" >&2; exit 1
  fi
  if [ "$code" != "202" ]; then
    err=$(printf '%s' "$json" | grep -o '"error_code":"[^"]*"' | cut -d'"' -f4 || true)
    if [ "$err" = "token_insufficient_scope" ]; then
      echo "prbuff: GitHub token lacks pull-request write permission; add 'permissions: pull-requests: write' to the workflow" >&2
    else
      echo "prbuff: request rejected (${err:-error})" >&2
    fi
    exit 1
  fi
  break
done

run_id=$(printf '%s' "$json" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
echo "prbuff: review queued (run ${run_id})"

# --- poll until terminal or timeout, printing status transitions (M10)
last=""
while [ "$SECONDS" -lt "$deadline" ]; do
  sleep "$interval"
  resp=$(curl -sS "${api}/v1/reviews/${run_id}" -H "Authorization: Bearer ${PRBUFF_API_KEY}")
  status=$(printf '%s' "$resp" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  dry=$(printf '%s' "$resp" | grep -o '"dry_run":[a-z]*' | cut -d: -f2 || true)
  [ "$status" != "$last" ] && echo "prbuff: status=${status} (${SECONDS}s elapsed)" && last="$status"
  case "$status" in
    succeeded)
      if [ "$dry" = "true" ]; then
        echo "prbuff: review completed in dry-run mode, no comments posted"
      else
        echo "prbuff: review completed"
      fi
      exit 0 ;;
    failed|timeout|expired)
      err=$(printf '%s' "$resp" | grep -o '"error_code":"[^"]*"' | cut -d'"' -f4 || true)
      echo "prbuff: review ${status} (run ${run_id}, ${err:-no detail})" >&2
      exit 1 ;;
  esac
done

echo "prbuff: review still in progress, check the PR later (run ${run_id})"
exit 0
