#!/usr/bin/env bash
set -euo pipefail

# Local Agentia quality gates (macOS / Linux).
# Edit this script to match your project. Agentia runs it from the repo root during
# `agentia cicd work test` (local by default) and `agentia cicd work submit` (unless --skip-local-tests).
# The script must exit non-zero if any check fails.
#
# Each gate is declared with an "agentia-gate: <id> - <description>" comment and guarded by an AGENTIA_GATES check.
# `agentia cicd work test --gate lint` runs only the lint gate (AGENTIA_GATES=lint);
# without --gate (or with --all) every gate runs. Add your own gates with a new id.

# Code Analyzer scope: "changed" (default) scans only files changed on this branch versus its base branch
# (committed, uncommitted and untracked; Agentia exports the base as AGENTIA_BASE_BRANCH). It falls back to a
# full scan when git or the base branch is unavailable. For a full scan once:
#   agentia cicd work test --gate lint -e LINT_SCOPE=all     (or change the default below)
LINT_SCOPE="${LINT_SCOPE:-changed}"

# agentia-gate: lint - Salesforce Code Analyzer (changed files by default, see LINT_SCOPE)
if [[ "${AGENTIA_GATES:-all}" == "all" || ",${AGENTIA_GATES}," == *",lint,"* ]]; then
  scan=all
  if [[ "$LINT_SCOPE" == "changed" ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    base="${AGENTIA_BASE_BRANCH:-main}"
    for ref in "origin/$base" "$base"; do
      git rev-parse --verify --quiet "$ref" >/dev/null || continue
      mb="$(git merge-base HEAD "$ref" 2>/dev/null)" || continue
      [[ -n "$mb" ]] || continue
      files="$({ git -c core.quotepath=off diff --name-only --diff-filter=ACMR "$mb"; git -c core.quotepath=off ls-files --others --exclude-standard; } | sort -u)" && scan=changed
      break
    done
  fi

  if [[ "$scan" == "changed" ]]; then
    targets=()
    while IFS= read -r file; do
      if [[ -n "$file" && -f "$file" ]]; then targets+=(--target "$file"); fi
    done <<< "$files"
    if (( ${#targets[@]} == 0 )); then
      echo "## Code Analyzer: no changed files, skipping"
    else
      echo "## Running Code Analyzer on $(( ${#targets[@]} / 2 )) changed file(s)"
      sf code-analyzer run "${targets[@]}"
    fi
  else
    echo "## Running Code Analyzer on the whole project"
    sf code-analyzer run
  fi
fi

# agentia-gate: apex - Apex tests (classes from --apex-test-classes)
if [[ "${AGENTIA_GATES:-all}" == "all" || ",${AGENTIA_GATES}," == *",apex,"* ]]; then
  echo "## Running apex tests (if --apex-test-classes= was specified)"
  agentia cicd work test --gate apex --apex-test-classes="${AGENTIA_APEX_TEST_CLASSES:-}" ${AGENTIA_APEX_RERUN_FAILED:-}
fi

# agentia-gate: lwc - LWC Jest tests
if [[ "${AGENTIA_GATES:-all}" == "all" || ",${AGENTIA_GATES}," == *",lwc,"* ]]; then
  echo "## Running LWC tests"
  npx sfdx-lwc-jest -- --passWithNoTests
fi
