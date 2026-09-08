#!/usr/bin/env bash
# lib/bashwrite.sh — the command-parsing half of post-bash-write.sh (C19,
# spec 003 G3(1)): "did this Bash command write a file?".
#
# Split out of post-bash-write.sh so both halves stay under the size guard's
# 400-line file limit, exactly as lib/hookpath.sh was split out of
# lib/hookout.sh. It defines functions only and is sourced, never executed.
#
# Public entry points: _pbw_strip_heredocs <cmd> and _pbw_is_writer <cmd>.

_PBW_TAB=$(printf '\t')

# _pbw_ltrim <var-by-value> — strip leading spaces/tabs, print the result.
_pbw_ltrim() {
	local s=$1
	while :; do
		case "$s" in
		' '*) s=${s# } ;;
		"$_PBW_TAB"*) s=${s#"$_PBW_TAB"} ;;
		*) break ;;
		esac
	done
	printf '%s' "$s"
}

# _pbw_heredoc_open <line> — rc 0 when the line opens a genuine heredoc,
# setting _PBW_HD_DELIM (the delimiter word) and _PBW_HD_DASH (1 for `<<-`).
# A bare `<<` is NOT enough: `echo "shift << 2"` and `grep foo <<< "$data"`
# contain `<<` without opening one, and treating them as one used to swallow
# every following line as body, hiding a real write. Each `<<` on the line is
# tested in turn, accepted only when (a) it's not `<<<` and (b) the token
# after it reduces, once quotes are removed, to a plain word.
_pbw_heredoc_open() {
	local rest=$1 marker first delim dash
	_PBW_HD_DELIM=""
	_PBW_HD_DASH=0
	while :; do
		case "$rest" in
		*'<<'*) rest=${rest#*<<} ;;
		*) return 1 ;;
		esac
		case "$rest" in
		'<'*)
			rest=${rest#<}
			continue
			;;
		esac
		marker=$rest
		dash=0
		case "$marker" in
		-*)
			dash=1
			marker=${marker#-}
			;;
		esac
		marker=$(_pbw_ltrim "$marker")
		first=${marker%%[[:space:];\|\&]*}
		delim=$first
		delim=${delim#\"}
		delim=${delim%\"}
		delim=${delim#\'}
		delim=${delim%\'}
		case "$delim" in
		[A-Za-z_]*)
			case "$delim" in
			*[!A-Za-z0-9_]*) continue ;;
			esac
			_PBW_HD_DELIM=$delim
			_PBW_HD_DASH=$dash
			return 0
			;;
		esac
	done
}

# _pbw_strip_heredocs <cmd> — drop heredoc BODY lines (never the marker line
# itself, so a head-token scan can still see `cat`/`tee`/`sponge`), so body
# text is never mistaken for a command part. If a delimiter line is never
# reached, the "heredoc" was a misread (a quoted `<<EOF` in prose, say), so
# the ORIGINAL text is returned instead: over-scanning risks a false
# positive, under-scanning loses a real write.
_pbw_strip_heredocs() {
	local cmd=$1 out="" line delim="" instrip=0 dash=0 chk
	while IFS= read -r line; do
		if [ "$instrip" -eq 1 ]; then
			chk=$line
			if [ "$dash" -eq 1 ]; then
				while :; do
					case "$chk" in
					"$_PBW_TAB"*) chk=${chk#"$_PBW_TAB"} ;;
					*) break ;;
					esac
				done
			fi
			[ "$chk" = "$delim" ] && instrip=0
			continue
		fi
		if _pbw_heredoc_open "$line"; then
			delim=$_PBW_HD_DELIM
			dash=$_PBW_HD_DASH
			instrip=1
		fi
		out="$out$line
"
	done <<PBWHDEOF
$cmd
PBWHDEOF
	if [ "$instrip" -eq 1 ]; then
		printf '%s' "$cmd"
		return 0
	fi
	printf '%s' "$out"
}

# _pbw_mask_quotes <cmd> — replace `>`, `<`, `&`, `;` and `|` that are DATA
# rather than syntax with `Q`, leaving every other character (and the quote
# delimiters) untouched. Four such contexts, one single-pass state machine:
#   - quoted spans (single, double, `$'…'`, state carried across newlines):
#     `echo "x>y"` writes nothing, nor does `git commit -m "wip; touch base"`
#     (a raw split on `;` floated `touch base"` out as its own bogus
#     writer-headed part — B2/FU-02, a separator rather than a redirect).
#   - a backslash escape: real bash writes nothing for `echo a \> b`.
#   - a `#` shell comment (line start or after whitespace) — the rest of the
#     line is DROPPED. Without this an unbalanced quote in a comment
#     (`# don't clobber`) flipped the masker into "inside a quote" for the
#     whole command and every later real `>` was masked away, silently
#     missing an oversized write: the exact B2/FU-02 gap. A `#` inside a word
#     (`${x#y}`, `http://a#b`) is data and stays.
#   - arithmetic `$(( … ))` / `(( … ))`, by paren depth so that nesting
#     (`echo $(( (1) > 0 ))`) masks too — a regex matched only the flat form.
# The last three are fix-round findings (comment handling: significant).
_pbw_mask_quotes() {
	printf '%s\n' "$1" | awk '
		BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); BS = sprintf("%c", 92)
			TB = sprintf("%c", 9); st = 0; ad = 0 }
		function m(c) { return (c == ">" || c == "<" || c == "&" || c == ";" || c == "|") ? "Q" : c }
		{
			out = ""
			n = length($0)
			for (i = 1; i <= n; i++) {
				c = substr($0, i, 1)
				if (ad > 0) {
					if (c == "(") ad++
					else if (c == ")") ad--
					out = out m(c)
				} else if (st == 0) {
					if (c == "#" && (i == 1 || substr($0, i - 1, 1) == " " || substr($0, i - 1, 1) == TB)) break
					if (c == "(" && substr($0, i + 1, 1) == "(") { ad = 2; out = out c c; i++; continue }
					if (c == BS) { out = out c; i++; if (i <= n) out = out m(substr($0, i, 1)); continue }
					if (c == SQ) { st = 1; out = out c; continue }
					if (c == DQ) { st = 2; out = out c; continue }
					out = out c
				} else if (st == 1) {
					if (c == SQ) { st = 0; out = out c; continue }
					out = out m(c)
				} else {
					if (c == BS) { out = out c; i++; if (i <= n) out = out m(substr($0, i, 1)); continue }
					if (c == DQ) { st = 0; out = out c; continue }
					out = out m(c)
				}
			}
			print out
		}
	'
}

# _pbw_has_write_redirect <cmd> — rc 0 when the text contains a `>`/`>>`
# that is not a file-descriptor duplication form (2>&1, &>, >&, N>&M, ...)
# and whose target is not /dev/null. `N>file` (a digit immediately before the
# arrow, target a real path) IS a write — only the `&`-forms above and an
# explicit /dev/null target are not. Single-pass sed, not a per-character bash
# loop: the old O(n^2) scan stalled for a minute on a 100 KB command. `->`/`=>`
# are stripped first. Callers pass quote-masked text (_pbw_mask_quotes).
#
# G3(1)'s first wording listed bare `2>` among the fd-dup forms that are not
# writes. `N>file` with no trailing `&M` really does write `file`, so it stays
# a writer (test t_bw_digit_prefix_write_redirect_rc2) — reading that wording
# literally would miss the exact class this hook exists to catch. `&>`/`&>>`
# (an actual fd form) is still exempt below. Spec 003 G3(1) was amended to
# match at integration; this file and the spec now agree.
_pbw_has_write_redirect() {
	local s=$1 stripped
	stripped=$(printf '%s' "$s" | sed -E 's/->//g; s/=>//g')
	stripped=$(printf '%s' "$stripped" | sed -E 's/&>>?//g; s/[0-9]*>>?&[0-9]*//g')
	stripped=$(printf '%s' "$stripped" | sed -E "s#[0-9]*>>?[[:space:]]*[\"']?/dev/null[\"']?#Q#g")
	case "$stripped" in
	*'>'*) return 0 ;;
	esac
	return 1
}

# _pbw_is_writer <cmd> — rc 0 when the command looks like it wrote a file.
_pbw_is_writer() {
	local cmd=$1 masked parts part first rest second
	masked=$(_pbw_mask_quotes "$cmd")
	_pbw_has_write_redirect "$masked" && return 0
	# Portable split on `&& || ; & |`: `\n` in a sed REPLACEMENT is a GNU
	# extension (BSD sed emits a literal `n`), so normalise the two-character
	# operators to `;` with sed and let `tr` produce the newlines. Split
	# $masked, never raw $cmd: a quoted separator masks to `Q` above.
	parts=$(printf '%s\n' "$masked" | sed -E 's/&&/;/g; s/\|\|/;/g' | tr ';&|' '\n\n\n')
	while IFS= read -r part; do
		part=$(_pbw_ltrim "$part")
		[ -z "$part" ] && continue
		# Strip a leading `sudo` wrapper: `sudo tee big.py` still starts
		# with the writer token underneath (improvable finding).
		while :; do
			first=${part%%[[:space:]]*}
			case "$first" in
			sudo) part=$(_pbw_ltrim "${part#"$first"}") ;;
			*) break ;;
			esac
		done
		first=${part%%[[:space:]]*}
		rest=$(_pbw_ltrim "${part#"$first"}")
		second=${rest%%[[:space:]]*}
		case "$first" in
		tee | dd | install | cp | mv | rsync | truncate | patch | touch | sponge) return 0 ;;
		node | python | python3 | bun | deno | perl | ruby | php) return 0 ;;
		# sh/bash/zsh (and `sponge` above) widen G3(1)'s original head-token
		# list: masking quoted separators means `sh -c 'cp a b'` no longer
		# splits into a `cp`-headed part, so the wrapper must count to keep
		# coverage. Spec 003 G3(1) was amended to match at integration.
		sh | bash | zsh) return 0 ;;
		sed)
			case "$second" in -i* | --in-place*) return 0 ;; esac
			;;
		esac
		case "$part" in
		*'<<'*)
			case "$first" in
			cat | tee | sponge) return 0 ;;
			esac
			;;
		esac
	done <<PBWPEOF
$parts
PBWPEOF
	return 1
}
