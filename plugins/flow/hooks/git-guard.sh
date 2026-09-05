#!/usr/bin/env bash
# git-guard.sh — PreToolUse/Bash hook.
#
# This is a regex blocklist over a command string. It raises the bar against
# an ordinary mistake; it is not a security boundary — `bash -c`, `eval`,
# variable construction, and a helper script written via Edit all evade it.
# CI is the real backstop.
set -u
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"; hook_skip_if_off # `flow off` marker: no judging hooks
cmd=$(hook_field '.tool_input.command')
[ -z "$cmd" ] && hook_ok

# gg_coarse: >20000-char / >200-part cap (C22 1/3), and the fallback when the awk pass below emits no well-formed "N" record (awk missing or broken).
GG_BIG='git[[:space:]]+.*push[^;&|]*(-[a-zA-Z]*f|--force)|git[[:space:]]+.*reset[^;&|]*--hard|git[[:space:]]+.*clean[^;&|]*(-[a-zA-Z]*f|--force)|git[[:space:]]+.*checkout[^;&|]*--[[:space:]]*\.|git[[:space:]]+.*restore[^;&|]*\.|git[[:space:]]+.*branch[^;&|]*(-D|--delete)|git[[:space:]]+.*commit[^;&|]*(-[a-zA-Z]*n|--no-verify)|rm[[:space:]]+.*-[a-zA-Z]*([rR][a-zA-Z]*f|f[a-zA-Z]*[rR])[a-zA-Z]*|chmod.*(-R|--recursive).*777'
gg_coarse() {
	printf '%s' "$1" | grep -Eq "$GG_BIG" && hook_deny "command too large to parse safely; matched a denied pattern (git push --force/-f, reset --hard, clean -f, checkout -- ., restore ., branch -D, commit --no-verify/-n, rm -rf on a root-like target, or chmod -R 777)"
	hook_ok
}
[ "${#cmd}" -gt 20000 ] && gg_coarse "$cmd"
# gg_scan <mode:eq|pre|short> <arg> <startidx> over global token array T
# (0-indexed, count N): eq=exact word; pre=prefix; short="-xyz" cluster
# (never "--...") containing letter <arg>.
gg_scan() {
	local mode=$1 arg=$2 j=$3 t
	while [ "$j" -lt "$N" ]; do
		t=${T[$j]}
		case "$mode" in
		eq) [ "$t" = "$arg" ] && return 0 ;;
		pre) case "$t" in "$arg"*) return 0 ;; esac ;;
		short) case "$t" in --*) : ;; -*) case "$t" in *"$arg"*) return 0 ;; esac ;; esac ;;
		esac
		j=$((j + 1))
	done
	return 1
}
gg_has() { gg_scan eq "$1" "$2"; }
gg_has_short() { gg_scan short "$1" "$2"; }
gg_has_prefix() { gg_scan pre "$1" "$2"; }
gg_has_pair() {
	local a=$1 b=$2 j=$3
	while [ "$((j + 1))" -lt "$N" ]; do
		[ "${T[$j]}" = "$a" ] && [ "${T[$((j + 1))]}" = "$b" ] && return 0
		j=$((j + 1))
	done
	return 1
}
# gg_find_git: GG_START=0-based subcommand-scan start, -1 if not git.
# Handles git, `command git`, `sudo git`, `env ... git`, path ending /git.
gg_find_git() {
	GG_START=-1
	case "${T[0]}" in
	git | */git) GG_START=1 ;;
	sudo | command) case "${T[1]:-}" in git | */git) GG_START=2 ;; esac ;;
	env)
		local i=1
		while [ "$i" -lt "$N" ]; do
			case "${T[$i]}" in
			*=* | -*) : ;;
			git | */git) GG_START=$((i + 1)) && return ;;
			*) return ;;
			esac
			i=$((i + 1))
		done
		;;
	esac
}
gg_rule_rm() {
	local s=$1 j t
	{ gg_has --recursive "$s" || gg_has_short r "$s" || gg_has_short R "$s"; } || return 0
	{ gg_has --force "$s" || gg_has_short f "$s"; } || return 0
	j=$s
	while [ "$j" -lt "$N" ]; do
		t=${T[$j]}
		case "$t" in
		'/' | '~' | '$HOME' | '.' | '..' | '*' | '/*' | '~/' | '$HOME/') hook_deny "rm -rf $t is a catastrophic delete target; scope the path narrowly and confirm with ls first" ;;
		esac
		j=$((j + 1))
	done
}
gg_rule_chmod() {
	{ gg_has --recursive 1 || gg_has_short R 1; } && gg_has 777 1 &&
		hook_deny "chmod -R 777 makes every file world-writable recursively; set the minimum permission actually needed"
}
gg_rule_git() {
	local i sub subi s
	sub="" subi=-1 i=$GG_START
	while [ "$i" -lt "$N" ]; do
		case "${T[$i]}" in
		push | reset | clean | checkout | restore | branch | commit | stash | rebase | merge) sub=${T[$i]} && subi=$i && break ;;
		esac
		i=$((i + 1))
	done
	[ -z "$sub" ] && return 0
	s=$((subi + 1))
	case "$sub" in
	push) { gg_has --force "$s" || gg_has_short f "$s" || gg_has_prefix --force= "$s"; } && hook_deny "git push --force/-f can overwrite remote history destructively; use --force-with-lease instead" ;;
	reset) gg_has --hard "$s" && hook_deny "git reset --hard discards uncommitted work irrecoverably; use plain git reset or git stash instead" ;;
	clean) { gg_has --force "$s" || gg_has_short f "$s"; } && hook_deny "git clean -f permanently deletes untracked files; run git clean -n first to preview" ;;
	checkout) gg_has_pair -- . "$s" && hook_deny "git checkout -- . discards all uncommitted changes in the tree; use git stash or commit first" ;;
	restore) gg_has . "$s" && ! { gg_has --staged "$s" || gg_has_short S "$s"; } && hook_deny "git restore . discards all uncommitted changes in the tree; use git restore --staged . if you only meant to unstage" ;;
	branch) { gg_has_short D "$s" || { gg_has --delete "$s" && gg_has --force "$s"; }; } && hook_deny "git branch -D force-deletes a branch even if unmerged; use git branch -d to be warned first" ;;
	commit) { gg_has --no-verify "$s" || gg_has_short n "$s"; } && hook_deny "git commit --no-verify/-n skips pre-commit hooks (format/lint/tests); fix what the hook flags instead" ;;
	esac
}
gg_check_part() {
	T=()
	read -r -a T <<<"$1"
	N=${#T[@]}
	[ "$N" -eq 0 ] && return 0
	case "${T[0]}" in rm) gg_rule_rm 1 ;; sudo) [ "${T[1]:-}" = rm ] && gg_rule_rm 2 ;; chmod) gg_rule_chmod ;; esac
	gg_find_git
	[ "$GG_START" -ge 0 ] && gg_rule_git
}
# One awk pass: normalise quoting/backslashes then split unquoted, unescaped
# ; && || | into parts, printing "N<norm>" then one "P<part>" per part.
# "\;" "\&" "\|" are inert in bash (escape the operator away, so
# `echo a\; git push --force` is one harmless echo) so both passes keep them
# atomic, never splitting there; any other "\X" unescapes to plain "X" (bash
# drops the backslash outside quotes: `--forc\e` really is `--force`). RS=""
# (paragraph mode) can split a blank-line-separated command into several
# records, so step 3's >200-part fallback greps $cmd, never a per-record N.
PARTS=() saw_n=0
if have awk; then
	awk_out=$(printf '%s\n\n' "$cmd" | awk '
BEGIN{RS="";SQ=sprintf("%c",39)}
{
s=$0; gsub(/\\\n/,"",s); n=length(s); out=""; i=1
while(i<=n){
c=substr(s,i,1)
if(c=="\\"&&i<n){nx=substr(s,i+1,1); if(nx==";"||nx=="&"||nx=="|")out=out c nx; else out=out nx; i+=2; continue}
if(c=="\""||c==SQ){qc=c; j=i+1; content=""; special=0
while(j<=n){cj=substr(s,j,1)
if(qc=="\""&&cj=="\\"&&j<n){nx=substr(s,j+1,1); content=content cj nx; if(nx==" "||nx=="\t"||nx==";"||nx=="&"||nx=="|")special=1; j+=2; continue}
if(cj==qc){j+=1; break}
content=content cj; if(cj==" "||cj=="\t"||cj=="\n"||cj==";"||cj=="&"||cj=="|")special=1; j+=1}
if(special)out=out "Q"; else out=out content; i=j; continue}
if(c=="\n"){out=out ";"; i+=1; continue}; out=out c; i+=1}
gsub(/[ \t]+/," ",out); sub(/^ /,"",out); sub(/ $/,"",out); print "N" out
n2=length(out); buf=""; i=1
while(i<=n2){c=substr(out,i,1); c2=substr(out,i,2)
if(c=="\\"&&i<n2){nx=substr(out,i+1,1); if(nx==";"||nx=="&"||nx=="|"){buf=buf nx; i+=2; continue}}
if(c2=="&&"||c2=="||"){gsub(/^ +| +$/,"",buf); print "P" buf; buf=""; i+=2; continue}
if(c==";"||c=="|"||c=="&"){gsub(/^ +| +$/,"",buf); print "P" buf; buf=""; i+=1; continue}
buf=buf c; i+=1}
gsub(/^ +| +$/,"",buf); print "P" buf
}
')
	while IFS= read -r line; do
		case "$line" in N*) saw_n=1 ;; P*) PARTS+=("${line#P}") ;; esac
	done <<EOF
$awk_out
EOF
fi
{ [ "$saw_n" -eq 0 ] || [ "${#PARTS[@]}" -eq 0 ]; } && gg_coarse "$cmd"
[ "${#PARTS[@]}" -gt 200 ] && gg_coarse "$cmd" # whole raw text (C22 step 3), not a per-record N
for p in "${PARTS[@]}"; do gg_check_part "$p"; done
hook_ok
