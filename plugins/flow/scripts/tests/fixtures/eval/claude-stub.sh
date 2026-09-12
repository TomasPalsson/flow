#!/usr/bin/env bash
# claude-stub.sh — stand-in for the `claude` CLI in test_eval_cli.sh
# (Slice 5, .claude/slices/5-brief.md). Reads `--json <path>` from its argv,
# copies the fixture aggregate named by CLAUDE_STUB_RESULT (default
# aggregate-ok) from EVAL_FIXTURES_DIR (default: this script's own
# directory) to that path, then exits CLAUDE_STUB_EXIT (default 0).
set -u

json_path=""
while [ $# -gt 0 ]; do
  case "$1" in
  --json)
    json_path=$2
    shift 2
    ;;
  *)
    shift
    ;;
  esac
done

fixtures_dir=${EVAL_FIXTURES_DIR:-$(cd "$(dirname "$0")" && pwd -P)}
result=${CLAUDE_STUB_RESULT:-aggregate-ok}

if [ -n "$json_path" ]; then
  cp "$fixtures_dir/${result}.json" "$json_path"
fi

exit "${CLAUDE_STUB_EXIT:-0}"
