#!/usr/bin/env bash
# infra-guard.sh — PreToolUse/Bash hook. Asks the user (permissionDecision
# "ask") before a command that destroys infrastructure or data, or that hides
# what it runs. It never refuses and prints nothing for any other command.
#
# It matches the RAW command string, not git-guard's per-part view: git-guard
# splits on "|", so `base64 -d | sh` never reaches one part there. A regex over
# a command string raises the bar against a slip; it is not a security boundary.
#
# Escape hatches match git-guard: CC_NO_GIT_GUARD=1 for one session, or
# .claude/flow.unsafe here or in any ancestor (`flow off --unsafe`).
#
# Credit: adapted from garrytan/gstack careful/bin/check-careful.sh @ 5b9b837 (MIT).
set -u
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
[ "${CC_NO_GIT_GUARD:-}" = "1" ] && hook_ok
ig_dir=$(hook_project_dir)
while :; do
	[ -f "$ig_dir/.claude/flow.unsafe" ] && hook_ok
	case "$ig_dir" in */?*) ig_dir=${ig_dir%/*} ;; *) break ;; esac
	[ -z "$ig_dir" ] && ig_dir="/"
done
cmd=$(hook_field '.tool_input.command')
[ -z "$cmd" ] && hook_ok

# A shell word boundary before a command name: start, whitespace, ; & | ( or `.
B='(^|[[:space:];&|(`])'
# Anything inside one simple command (no separator), then a whole word.
S='[^;&|]*'

# ig_ask <what> <why>
ig_ask() { hook_ask "$1: $2 (escape: CC_NO_GIT_GUARD=1 for this session, or approve it when asked)"; }
# ig_has <ere> [grep flags]: the raw command matches.
ig_has() { printf '%s' "$cmd" | grep -Eq${2:-} -- "$1"; }

ig_has "${B}terraform[[:space:]]+(${S}[[:space:]])?destroy([[:space:]]|\$|[;&|)])" &&
	ig_ask "terraform destroy" "it deletes every resource in the state; terraform plan -destroy shows what would go"
ig_has "${B}terraform[[:space:]]+(${S}[[:space:]])?apply[[:space:]]+(${S}[[:space:]])?-destroy" &&
	ig_ask "terraform apply -destroy" "it deletes every resource in the state; terraform plan -destroy shows what would go"
ig_has "${B}sst[[:space:]]+remove([[:space:]]|\$|[;&|)])" &&
	ig_ask "sst remove" "it tears down the stage's deployed resources"
ig_has "${B}aws[[:space:]]+(${S}[[:space:]])?s3[[:space:]]+rm[[:space:]]${S}--recursive" &&
	ig_ask "aws s3 rm --recursive" "it deletes every object under the prefix; aws s3 ls lists them first"
ig_has "${B}aws[[:space:]]+(${S}[[:space:]])?s3[[:space:]]+rb[[:space:]]${S}--force" &&
	ig_ask "aws s3 rb --force" "it empties the bucket and then removes it"
ig_has 'drop[[:space:]]+(table|database)([[:space:]]|$|[^A-Za-z0-9_])' i &&
	ig_ask "DROP TABLE/DATABASE" "it discards the data irrecoverably unless a backup exists"
printf '%s' "$cmd" | grep -Fq -- '${IFS}' &&
	ig_ask '${IFS}' "it is a common way to hide word splitting from a reader of the command"
ig_has "base64[[:space:]]+${S}(-d|-D|--decode)([[:space:]]|\$)[^;&]*\\|[[:space:]]*(/[^[:space:]|]*/)?(sh|bash|zsh)([[:space:]]|\$|[;&|)])" &&
	ig_ask "base64 -d piped to a shell" "it runs text that cannot be read in the command"
hook_ok
