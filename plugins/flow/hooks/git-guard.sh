#!/usr/bin/env bash
# git-guard.sh — PreToolUse/Bash hook. C22 budget: <= 160 lines with comments.
# This is a regex blocklist over a command string. It raises the bar against an
# ordinary mistake; it is not a security boundary — `bash -c`, `eval`, variable
# construction and a helper script written via Edit all evade it. CI is the real backstop.
set -u
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
# C-B: .claude/flow.off does NOT silence this hook. Its switches are CC_NO_GIT_GUARD=1
# (one session) and .claude/flow.unsafe (`flow off --unsafe`, here or in any ancestor).
[ "${CC_NO_GIT_GUARD:-}" = "1" ] && hook_ok
gg_dir=$(hook_project_dir)
while :; do
	[ -f "$gg_dir/.claude/flow.unsafe" ] && hook_ok
	case "$gg_dir" in */?*) gg_dir=${gg_dir%/*} ;; *) break ;; esac
	[ -z "$gg_dir" ] && gg_dir="/"
done
cmd=$(hook_field '.tool_input.command')
[ -z "$cmd" ] && hook_ok
gg_deny() { hook_deny "$1 (escape: CC_NO_GIT_GUARD=1 for this session, or ask the user to run it)"; }
# FU-22: literal command prefixes from flow.config.json "deny", one per line. Without jq the pipe exits 127 and hook_config returns "" anyway (frozen by C-A), so read the file with python3 instead — otherwise a project's deny list would be silently inert. With NEITHER jq nor python3 this hook judges nothing at all: hook_field cannot parse the payload, $cmd comes back empty and the check above allows every command (the C-A contract, and the behaviour before this slice too).
GG_DENY=$(hook_config deny | jq -r 'if type == "array" then .[] | select(type == "string") else empty end' 2>/dev/null || python3 -c 'import json,sys;d=json.load(open(sys.argv[1])).get("deny");print(chr(10).join(x for x in d if isinstance(x,str)) if isinstance(d,list) else "")' "$(hook_project_dir)/.claude/flow.config.json" 2>/dev/null || printf '')
# gg_denylist <text> <anchor>: anchor "" = <text> starts with the entry (a parsed part), "*" = the entry appears anywhere in <text> (the coarse path, which has no parts). Either way the entry must end on a non-alphanumeric boundary.
gg_denylist() {
	local p
	while IFS= read -r p; do
		[ -n "$p" ] && { if [ "$2" = '*' ]; then case "$1" in *"$p" | *"$p"[!A-Za-z0-9]*) gg_deny "\"$p\" is on this project's deny list (\"deny\" in .claude/flow.config.json)" ;; esac; else case "$1" in "$p" | "$p"[!A-Za-z0-9]*) gg_deny "\"$p\" is on this project's deny list (\"deny\" in .claude/flow.config.json)" ;; esac; fi; }
	done <<<"$GG_DENY"
}
# gg_coarse <cmd> <why>: >20000-char / >200-part cap (C22 1/3), and the fallback when the awk pass below emits no well-formed "N" record. <why> states the condition observed.
GG_BIG='git[[:space:]]+.*push[^;&|]*(-[a-zA-Z]*f|--force)|git[[:space:]]+.*reset[^;&|]*--hard|git[[:space:]]+.*clean[^;&|]*(-[a-zA-Z]*f|--force)|git[[:space:]]+.*checkout[^;&|]*--[[:space:]]*\.|git[[:space:]]+.*restore[^;&|]*\.|git[[:space:]]+.*branch[^;&|]*(-D|--delete)|git[[:space:]]+.*commit[^;&|]*(-[a-zA-Z]*n|--no-verify)|rm[[:space:]]+.*-[a-zA-Z]*([rR][a-zA-Z]*f|f[a-zA-Z]*[rR])[a-zA-Z]*|chmod.*(-R|--recursive).*777'
gg_coarse() {
	[ -n "$GG_DENY" ] && gg_denylist "$1" '*' # GG_BIG holds the builtin rules only, so the project deny list is checked separately here or it would fail open on this path
	printf '%s' "$1" | grep -Eq "$GG_BIG" && gg_deny "$2; matched a denied pattern (git push --force/-f, reset --hard, clean -f, checkout -- ., restore ., branch -D, commit --no-verify/-n, rm -rf on a root-like target, or chmod -R 777)"
	hook_ok
}
[ "${#cmd}" -gt 20000 ] && gg_coarse "$cmd" "command too large to parse safely"
# gg_scan <mode> <arg> <startidx> over the global token array T (0-indexed, count N),
# leaving the matched index in GG_IDX. eq=exact word; pre=prefix; short="-xyz" cluster
# (never "--...") with letter <arg>; git=the git binary at any path; sub=watched git
# subcommand; tgt=catastrophic rm target; nw=first token that is NOT a keyword/wrapper/
# VAR=value (awk's pp() already split a glued "(git …" and peeled a trailing ")"/"}" so wrappers never glue to a token).
gg_scan() {
	local mode=$1 arg=$2 j=$3 t
	while [ "$j" -lt "$N" ]; do
		t=${T[$j]} GG_IDX=$j
		case "$mode" in
		eq) [ "$t" = "$arg" ] && return 0 ;;
		pre) case "$t" in "$arg"*) return 0 ;; esac ;;
		short) case "$t" in --*) : ;; -*) case "$t" in *"$arg"*) return 0 ;; esac ;; esac ;;
		git) case "$t" in git | */git) return 0 ;; esac ;;
		sub) case "$t" in push | reset | clean | checkout | restore | branch | commit) return 0 ;; esac ;;
		tgt) case "$t" in '/' | '~' | '$HOME' | '.' | '..' | '*' | '/*' | '~'/ | '$HOME'/) return 0 ;; esac ;;
		nw) case "$t" in if | then | else | elif | fi | do | done | while | until | for | case | 'esac' | time | nohup | exec | '!' | '{' | '(' | sudo | env | command | builtin | *=*) : ;; *) return 0 ;; esac ;;
		esac
		j=$((j + 1))
	done
	return 1
}
gg_rule_rm() {
	local s=$1
	{ gg_scan eq --recursive "$s" || gg_scan short r "$s" || gg_scan short R "$s"; } || return 0
	{ gg_scan eq --force "$s" || gg_scan short f "$s"; } || return 0
	gg_scan tgt '' "$s" && gg_deny "rm -rf ${T[$GG_IDX]} is a catastrophic delete target; scope the path narrowly and confirm with ls first"
}
gg_rule_chmod() { { gg_scan eq --recursive "$1" || gg_scan short R "$1"; } && gg_scan eq 777 "$1" && gg_deny "chmod -R 777 makes every file world-writable recursively; set the minimum permission actually needed"; }
gg_rule_git() {
	local sub s
	gg_scan sub '' "$GG_START" || return 0
	sub=${T[$GG_IDX]} s=$((GG_IDX + 1))
	case "$sub" in
	push) { gg_scan eq --force "$s" || gg_scan short f "$s" || gg_scan pre --force= "$s"; } && gg_deny "git push --force/-f can overwrite remote history destructively; use --force-with-lease instead" ;;
	reset) gg_scan eq --hard "$s" && gg_deny "git reset --hard discards uncommitted work irrecoverably; use plain git reset or git stash instead" ;;
	clean) { gg_scan eq --force "$s" || gg_scan short f "$s"; } && gg_deny "git clean -f permanently deletes untracked files, and with -x the ignored build output too; git clean -n lists what it would delete" ;;
	checkout) gg_scan eq -- "$s" && [ "${T[$((GG_IDX + 1))]:-}" = . ] && gg_deny "git checkout -- . discards all uncommitted changes in the tree; use git stash or commit first" ;;
	restore) gg_scan eq . "$s" && ! { gg_scan eq --staged "$s" || gg_scan short S "$s"; } && gg_deny "git restore . discards all uncommitted changes in the tree; use git restore --staged . if you only meant to unstage" ;;
	branch) { gg_scan short D "$s" || { gg_scan eq --delete "$s" && gg_scan eq --force "$s"; }; } && gg_deny "git branch -D force-deletes a branch even if unmerged; use git branch -d to be warned first" ;;
	commit) { gg_scan eq --no-verify "$s" || gg_scan short n "$s"; } && gg_deny "git commit --no-verify/-n skips pre-commit hooks (format/lint/tests); fix what the hook flags instead" ;;
	esac
}
# B1/FU-01: skip leading keywords/wrappers/VAR=value so `then git push --force` and `nohup rm -rf /` are judged like their bare forms.
gg_check_part() {
	T=()
	read -r -a T <<<"$1"
	N=${#T[@]}
	local h w
	gg_scan nw '' 0 || return 0
	h=$GG_IDX w=0
	[ "$h" -gt 0 ] && w=1
	[ -n "$GG_DENY" ] && gg_denylist "${T[*]:$h}" ''
	GG_START=-1
	case "${T[$h]}" in
	git | */git) GG_START=$((h + 1)) ;;
	rm) gg_rule_rm $((h + 1)) ;;
	chmod) gg_rule_chmod $((h + 1)) ;;
	esac
	# A wrapper can leave git deeper in the part: `case x in a) git …`, `env -i git …`.
	[ "$GG_START" -lt 0 ] && [ "$w" -eq 1 ] && gg_scan git '' "$h" && GG_START=$((GG_IDX + 1))
	[ "$GG_START" -ge 0 ] && gg_rule_git
	return 0
}
# One awk pass: excise heredoc bodies (B16) so a script the model is WRITING is never
# read as commands, normalise quoting/backslashes, then split unquoted, unescaped
# ; && || | into parts, printing "N<norm>" then one "P<part>" per part. "\;" "\&" "\|"
# are inert in bash so both passes keep them atomic; any other "\X" unescapes to "X".
# RS is \004 (never in a command) so the WHOLE command is one record: paragraph mode
# split at a blank line INSIDE a heredoc body and read the rest of it as commands.
# hdopen() opens a body only for a real redirection — outside quotes, not `<<<`,
# delimiter followed by whitespace > | ; & or EOL, so `echo "cat <<EOF"` and
# `$((1 << N))` are not openers — with no interpreter anywhere on the line (`bash <<EOF`,
# `source /dev/stdin <<EOF`, `cat <<EOF | bash` EXECUTE it) and a terminator; without one the rest is scanned. A delimiter may be bare, '..', ".." or \EOF. An unquoted `#` that starts a word ends the line scan, so a `<<EOF` inside a comment opens no body (bash does not either).
PARTS=() saw_n=0
if have awk; then
	awk_out=$(printf '%s\n' "$cmd" | awk '
BEGIN{RS=sprintf("%c",4);SQ=sprintf("%c",39)}
function isinterp(w,   b){sub(/^[({!]+/,"",w); b=w; sub(/^.*\//,"",b); return (b ~ /^(\.|source|bash|sh|zsh|ksh|dash|fish|csh|tcsh|ssh|su|python|python3|node|perl|ruby|docker|kubectl)$/)}
function anyinterp(p,   m,A,k){m=split(p,A,/[ \t]+/); for(k=1;k<=m;k++)if(isinterp(A[k]))return 1; return 0}
function pp(b){gsub(/^ +| +$/,"",b); sub(/^[({!]+/,"( ",b); gsub(/ [({]+/," ( ",b); sub(/[)}]+$/,"",b); print "P" b}
function hdopen(l,   n,i,c,q,r,ln,tl,d){n=length(l); i=1; q=""; while(i<=n){c=substr(l,i,1)
if(q!=""){if(q=="\""&&c=="\\")i++; else if(c==q)q=""; i++; continue}
if(c=="\\"){i+=2; continue} if(c=="\""||c==SQ){q=c; i++; continue} if(c=="#"&&(i==1||index(" \t;&|(",substr(l,i-1,1))>0))return ""
if(c!="<"||substr(l,i+1,1)!="<"){i++; continue} if(substr(l,i+2,1)=="<"){i+=3; continue}
r=substr(l,i); ln=0; if(match(r,"^<<-?[ \t]*" SQ "[A-Za-z_][A-Za-z0-9_.-]*" SQ)||match(r,"^<<-?[ \t]*\"[A-Za-z_][A-Za-z0-9_.-]*\"")||match(r,"^<<-?[ \t]*\\\\?[A-Za-z_][A-Za-z0-9_.-]*"))ln=RLENGTH
tl=substr(r,ln+1,1)
if(ln>0&&(tl==""||tl==" "||tl=="\t"||tl==">"||tl=="|"||tl==";"||tl=="&")){if(anyinterp(l))return ""
d=substr(r,1,ln); sub(/^<<-?[ \t]*/,"",d); sub(/^\\/,"",d); gsub(/["]/,"",d); gsub(SQ,"",d); return d}
i+=2} return ""}
{s=$0; gsub(/\\\n/,"",s); sub(/\n+$/,"",s); if(index(s,"<<")){nl=split(s,L,"\n"); s=""; k=1
while(k<=nl){s=s L[k] "\n"; d=hdopen(L[k]); m=0
if(d!="")for(e=k+1;e<=nl;e++){t=L[e]; gsub(/^[ \t]+|[ \t]+$/,"",t); if(t==d){m=e; break}}
k=(m>0?m+1:k+1)} sub(/\n$/,"",s)}
n=length(s); out=""; i=1; while(i<=n){c=substr(s,i,1)
if(c=="\\"&&i<n){nx=substr(s,i+1,1); if(nx==";"||nx=="&"||nx=="|")out=out c nx; else out=out nx; i+=2; continue}
if(c=="\""||c==SQ){qc=c; j=i+1; content=""; special=0
while(j<=n){cj=substr(s,j,1)
if(qc=="\""&&cj=="\\"&&j<n){nx=substr(s,j+1,1); content=content cj nx; if(nx==" "||nx=="\t"||nx==";"||nx=="&"||nx=="|")special=1; j+=2; continue}
if(cj==qc){j+=1; break} content=content cj; if(cj==" "||cj=="\t"||cj=="\n"||cj==";"||cj=="&"||cj=="|")special=1; j+=1}
if(special)out=out "Q"; else out=out content; i=j; continue}
if(c=="\n"){out=out ";"; i+=1; continue} out=out c; i+=1}
gsub(/[ \t]+/," ",out); sub(/^ /,"",out); sub(/ $/,"",out); print "N" out
n2=length(out); buf=""; i=1; while(i<=n2){c=substr(out,i,1); c2=substr(out,i,2)
if(c=="\\"&&i<n2){nx=substr(out,i+1,1); if(nx==";"||nx=="&"||nx=="|"){buf=buf nx; i+=2; continue}}
if(c2=="&&"||c2=="||"){pp(buf); buf=""; i+=2; continue}
if(c==";"||c=="|"||c=="&"){pp(buf); buf=""; i+=1; continue}
buf=buf c; i+=1}
pp(buf)
}
')
	while IFS= read -r line; do
		case "$line" in N*) saw_n=1 ;; P*) PARTS+=("${line#P}") ;; esac
	done <<EOF
$awk_out
EOF
fi
{ [ "$saw_n" -eq 0 ] || [ "${#PARTS[@]}" -eq 0 ]; } && gg_coarse "$cmd" "$(have awk && printf 'this command could not be parsed' || printf 'awk is unavailable, so this command could not be parsed')"
[ "${#PARTS[@]}" -gt 200 ] && gg_coarse "$cmd" "command too large to parse safely" # whole raw text (C22 step 3), not a per-record N
for p in "${PARTS[@]}"; do gg_check_part "$p"; done
hook_ok
