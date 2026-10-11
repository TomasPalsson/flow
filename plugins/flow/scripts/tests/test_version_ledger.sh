#!/usr/bin/env bash
# test_version_ledger.sh — version-ledger-lint (F179) plus the pinned text and
# helper checks of the famous-repos tooling slice (F176/F177/F180/F183/F184).
# Sourced by run.sh; SCAN_DIR (flow/scripts) is already set. t_vledger_* prefix.

VL_LINT="$SCAN_DIR/version-ledger-lint"
VL_PLUGINS="$SCAN_DIR/../.."
VL_AA="$VL_PLUGINS/tooling/skills/agent-architecture/references"
VL_VA="$VL_PLUGINS/tooling/skills/version-audit"
VL_MCP="$VL_PLUGINS/tooling/skills/mcp-server"

# _vl_fixture <dir> — a target file plus a one-row ledger whose anchor is in it.
_vl_fixture() {
	local d=$1
	printf 'line one\ncache floor is 4,096 tokens\nline three\n' >"$d/target.md"
	cat >"$d/versions.md" <<'LEDGER'
# Versions

| Claim | File | Anchor | Verified | Re-verify |
|---|---|---|---|---|
| Haiku cache floor | target.md | `cache floor is 4,096 tokens` | 2026-10-01 | `curl -s https://example.invalid/docs` |
LEDGER
}

t_vledger_anchor_present_passes() {
	local d
	d=$(tmp_dir)
	_vl_fixture "$d"
	run_cmd python3 -I "$VL_LINT" "$d/versions.md"
	assert_rc 0 "fixture A: anchor present exits 0"
	assert_eq "$OUT$ERR" "" "fixture A: silent on the happy path"
}

t_vledger_anchor_deleted_fails_and_names_row() {
	local d
	d=$(tmp_dir)
	_vl_fixture "$d"
	printf 'line one\nline three\n' >"$d/target.md"
	run_cmd python3 -I "$VL_LINT" "$d/versions.md"
	assert_rc 1 "fixture B: anchor text deleted exits 1"
	assert_contains "$OUT$ERR" "Haiku cache floor" "fixture B: names the failing row"
	assert_contains "$OUT$ERR" "anchor not found" "fixture B: says the anchor is gone"
}

t_vledger_inserted_lines_above_anchor_still_pass() {
	local d
	d=$(tmp_dir)
	_vl_fixture "$d"
	printf 'new a\nnew b\nnew c\n%s\n' "$(cat "$d/target.md")" >"$d/target2.md"
	mv "$d/target2.md" "$d/target.md"
	run_cmd python3 -I "$VL_LINT" "$d/versions.md"
	assert_rc 0 "fixture C: lines inserted above the anchor still exit 0"
}

t_vledger_missing_reverify_fails() {
	local d
	d=$(tmp_dir)
	_vl_fixture "$d"
	sed 's#| `curl -s https://example.invalid/docs` |#| |#' "$d/versions.md" >"$d/v2.md"
	run_cmd python3 -I "$VL_LINT" "$d/v2.md"
	assert_rc 1 "a row with no re-verify command exits 1"
	assert_contains "$OUT$ERR" "no re-verify command" "names the missing re-verify command"
	assert_contains "$OUT$ERR" "Haiku cache floor" "names the row without the command"
}

t_vledger_missing_file_and_bad_date_fail() {
	local d
	d=$(tmp_dir)
	_vl_fixture "$d"
	sed 's/2026-10-01/last month/' "$d/versions.md" >"$d/v3.md"
	run_cmd python3 -I "$VL_LINT" "$d/v3.md"
	assert_rc 1 "a row with a non-ISO verified date exits 1"
	assert_contains "$OUT$ERR" "verified date" "names the bad date"
	rm -f "$d/target.md"
	run_cmd python3 -I "$VL_LINT" "$d/versions.md"
	assert_rc 1 "a row citing a missing file exits 1"
	assert_contains "$OUT$ERR" "file not found" "says the cited file is missing"
}

t_vledger_unreadable_input_exits_2() {
	run_cmd python3 -I "$VL_LINT" /nonexistent/versions.md
	assert_rc 2 "a ledger path that does not exist is a usage error (2)"
}

t_vledger_shipped_ledgers_are_clean() {
	run_cmd python3 -I "$VL_LINT"
	assert_rc 0 "no args: every shipped versions.md ledger passes"
	assert_eq "$OUT$ERR" "" "no args: silent when clean"
	assert_file_exists "$VL_AA/versions.md" "agent-architecture ledger exists"
	assert_file_exists "$VL_PLUGINS/aws/skills/strands-agentcore/references/versions.md" "strands-agentcore ledger exists"
	assert_file_exists "$VL_MCP/references/versions.md" "mcp-server ledger exists"
}

t_vledger_default_scan_finds_the_ledgers() {
	local out
	out=$(python3 -I "$VL_LINT" --list)
	assert_contains "$out" "agent-architecture/references/versions.md" "--list shows the agent-architecture ledger"
	assert_contains "$out" "strands-agentcore/references/versions.md" "--list shows the strands ledger"
	assert_contains "$out" "mcp-server/references/versions.md" "--list shows the mcp-server ledger"
}

# ---- F176: MCP annotations and result contract ----
t_vledger_tool_design_mcp_contract() {
	local t
	t=$(cat "$VL_AA/tool-design.md")
	assert_contains "$t" "readOnlyHint" "tool-design: annotations section names readOnlyHint"
	assert_contains "$t" "destructiveHint" "tool-design: names destructiveHint"
	assert_contains "$t" "confirmation_required" "tool-design: structured confirmation result"
	assert_contains "$t" "isError" "tool-design: retryable vs terminal errors as isError"
	assert_contains "$t" "never readOnlyHint on an exec tool" "tool-design: pins the exec-tool rule"
	assert_contains "$t" "parallel-safe" "tool-design: typed-tool promotion names parallel-safe"
	assert_contains "$t" "@ dbd4588" "tool-design: credits anthropics/skills at its sha"
	assert_contains "$t" "@ a9fd216" "tool-design: credits claude-plugins-official at its sha"
}

# ---- F180: anti-patterns ----
t_vledger_gallery_and_multi_agent_additions() {
	local g m n
	g=$(cat "$VL_AA/anti-pattern-gallery.md")
	m=$(cat "$VL_AA/multi-agent.md")
	assert_contains "$g" "sort_keys" "gallery: cache-invalidator grep table names sort_keys"
	assert_contains "$g" "cache_read_input_tokens > 0" "gallery: standing cache-hit test assertion"
	assert_contains "$g" "model-call sites" "gallery: call-site counting"
	assert_contains "$m" "first streamed token" "multi-agent: fan out after the first streamed token"
	n=$(grep -c '^### `cache_read_input_tokens` stays 0' "$VL_AA/anti-pattern-gallery.md")
	assert_eq "$n" "1" "gallery has exactly one cache-hit-zero entry"
}

# ---- F177: mcp-server skill ----
t_vledger_mcp_server_skill() {
	local all f
	assert_file_exists "$VL_MCP/SKILL.md" "mcp-server SKILL.md exists"
	all=$(cat "$VL_MCP"/SKILL.md "$VL_MCP"/references/*.md)
	assert_contains "$all" "stderr" "mcp-server: stdout/stderr hygiene"
	assert_contains "$all" "Origin" "mcp-server: Origin validation"
	assert_contains "$all" "CIMD" "mcp-server: Claude auth via CIMD"
	assert_contains "$all" "elicitation" "mcp-server: elicitation"
	assert_contains "$all" "inspector" "mcp-server: Inspector smoke test"
	assert_contains "$all" "*.pc" "mcp-server: reconciles the LAN dev-server rule"
	assert_contains "$all" "@ a9fd216" "mcp-server: credit line carries the sha"
	assert_contains "$(cat "$VL_MCP/SKILL.md")" "0.0.0.0:8000/mcp" "mcp-server: AgentCore MCP port matches the ledger (8000, not 8080)"
	assert_not_contains "$all" "8080" "mcp-server: no 8080 port claim"
	assert_not_contains "$all" "rm -rf" "mcp-server: no destructive payload in a checklist an agent ticks"
	for f in auth apps local-security hygiene versions; do
		assert_file_exists "$VL_MCP/references/$f.md" "mcp-server references/$f.md exists"
		assert_contains "$(cat "$VL_MCP/SKILL.md")" "references/$f.md" "SKILL.md loads references/$f.md"
	done
}

# ---- F183: Claude model IDs ----
_vl_ids_fixture() { # <dir> — a client call, a capability gate, a registry, a suffixed variant
	mkdir -p "$1/src"
	cat >"$1/src/client.py" <<'PY'
import anthropic
client = anthropic.Anthropic()
resp = client.messages.create(model="claude-3-5-sonnet-20241022", max_tokens=10, messages=[])
PY
	cat >"$1/src/gate.py" <<'PY'
def supports_feature(model):
    if 'sonnet-4-5' in model:
        return True
PY
	cat >"$1/src/registry.py" <<'PY'
MODELS = {
    "sonnet": "claude-sonnet-4-5-20250929",
}
PY
	cat >"$1/src/route.py" <<'PY'
ROUTE = "claude-opus-4-6-fast"
PY
	cat >"$1/src/bedrock.py" <<'PY'
m = BedrockModel(model_id="us.anthropic.claude-opus-4-5-20250514-v1:0")
PY
	cat >"$1/catalog.txt" <<'CAT'
claude-sonnet-4-5-20250929 current
claude-sonnet-4-5 current
claude-opus-4-5-20251101 legacy
claude-3-5-sonnet-20241022 retired 2025-10-28
claude-3-haiku-20240307 deprecated 2026-04-19
CAT
}

t_vledger_model_ids_classifies() {
	local d
	d=$(tmp_dir)
	_vl_ids_fixture "$d"
	run_cmd node "$VL_VA/scripts/model-ids.mjs" "$d" --catalog "$d/catalog.txt"
	assert_rc 0 "model-ids scan exits 0 (advisory)"
	assert_contains "$OUT" "src/client.py:3 retired caller claude-3-5-sonnet-20241022" "client call with a retired ID is retired + caller"
	assert_contains "$OUT" "src/gate.py:2 gate add-alongside" "substring capability gate is an add-alongside gate"
	assert_contains "$OUT" "src/registry.py:2 current definer claude-sonnet-4-5-20250929" "registry entry is a definer"
	assert_contains "$OUT" "src/route.py:1 unknown suffixed claude-opus-4-6-fast" "-fast variant is suffixed"
	assert_contains "$OUT" "src/bedrock.py:1 unknown caller us.anthropic.claude-opus-4-5-20250514-v1:0" "regional Bedrock ID not in the catalog is unknown with file:line"
}

t_vledger_model_ids_marker_and_no_catalog() {
	local d
	d=$(tmp_dir)
	_vl_ids_fixture "$d"
	printf '# KEEP IN SYNC with the model table\nX = 1\n' >"$d/src/marker.py"
	run_cmd node "$VL_VA/scripts/model-ids.mjs" "$d"
	assert_rc 0 "no catalog: still exits 0"
	assert_contains "$OUT" "src/marker.py:1 marker" "sync markers are listed first"
	assert_contains "$OUT" "unverified" "no catalog: IDs are unverified, never current"
	assert_not_contains "$OUT" " current " "no catalog: nothing is called current"
}

t_vledger_version_audit_model_id_section() {
	local s
	s=$(cat "$VL_VA/SKILL.md")
	assert_contains "$s" "## Claude model IDs" "version-audit: Claude model IDs section"
	assert_contains "$s" "references/claude-model-ids.md" "version-audit: loads the model-id reference"
	assert_contains "$s" "scripts/model-ids.mjs" "version-audit: names the model-id scanner"
	assert_contains "$s" "list-foundation-models" "version-audit: Bedrock catalog command"
	assert_contains "$s" "KEEP IN SYNC" "version-audit: sync markers first"
	assert_contains "$(cat "$VL_VA/references/claude-model-ids.md")" "@ dbd4588" "model-id reference credits anthropics/skills"
}

# ---- F184: major upgrade plan ----
_vl_next_fixture() { # <dir> — Next 14 app, sync cookies() in one route, no next/legacy/image
	mkdir -p "$1/app/api/me" "$1/app/ui"
	cat >"$1/package.json" <<'JSON'
{"dependencies":{"next":"14.2.5","react":"18.3.1"}}
JSON
	cat >"$1/app/api/me/route.ts" <<'TS'
import { cookies } from 'next/headers'
export async function GET() {
  const c = cookies().get('sid')
  return Response.json({ c })
}
TS
	cat >"$1/app/ui/hero.tsx" <<'TS'
import Image from 'next/image'
export const Hero = () => <Image src="/a.png" alt="" width={1} height={1} />
TS
	cat >"$1/app/ui/note.md" <<'MD'
Docs mention next/legacy/image only in prose.
MD
	cat >"$1/rules.json" <<'JSON'
[
 {"id":"D1","name":"cookies() is async","pattern":"\\bcookies\\(\\)","include":["*.ts","*.tsx"],
  "codemod":{"name":"@next/codemod next-async-request-api"}},
 {"id":"D2","name":"next/legacy/image removed","pattern":"next/legacy/image","include":["*.ts","*.tsx"]}
]
JSON
}

t_vledger_delta_scan_intersects_with_code() {
	local d
	d=$(tmp_dir)
	_vl_next_fixture "$d"
	run_cmd node "$VL_VA/scripts/delta-scan.mjs" "$d" --rules "$d/rules.json"
	assert_rc 0 "delta-scan exits 0 (advisory)"
	assert_contains "$OUT" "D1 confirmed app/api/me/route.ts:3" "cookies() hit is listed at its file:line"
	assert_contains "$OUT" "D2 not-hit" "unused legacy/image is not-hit"
	assert_not_contains "$OUT" "app/ui/note.md" "prose files outside include are never matched"
	assert_contains "$OUT" "codemod present, not run" "codemod row says present, not run"
}

t_vledger_delta_scan_codemod_states() {
	local d
	d=$(tmp_dir)
	_vl_next_fixture "$d"
	run_cmd node "$VL_VA/scripts/delta-scan.mjs" "$d" --rules "$d/rules.json" --ran "@next/codemod next-async-request-api"
	assert_contains "$OUT" "codemod ran" "--ran marks a codemod that actually ran"
	run_cmd node "$VL_VA/scripts/delta-scan.mjs" "$d" --rules "$d/rules.json" --json
	assert_contains "$OUT" '"state": "confirmed"' "--json carries the row state"
}

t_vledger_delta_scan_wrong_site() {
	local d
	d=$(tmp_dir)
	_vl_next_fixture "$d"
	mkdir -p "$d/node_modules/x"
	printf 'const c = cookies()\n' >"$d/node_modules/x/i.ts"
	printf '// cookies() was sync before 15\n' >"$d/app/ui/c.ts"
	run_cmd node "$VL_VA/scripts/delta-scan.mjs" "$d" --rules "$d/rules.json"
	assert_contains "$OUT" "wrong-site app/ui/c.ts:1" "a comment-only hit is wrong-site"
	assert_not_contains "$OUT" "node_modules/x" "node_modules is never scanned"
}

t_vledger_version_audit_major_plan_section() {
	local s
	s=$(cat "$VL_VA/SKILL.md")
	assert_contains "$s" "## Major upgrade plan" "version-audit: Major upgrade plan section"
	assert_contains "$s" "references/delta-catalog.md" "version-audit: loads the delta catalog reference"
	assert_contains "$s" "scripts/delta-scan.mjs" "version-audit: names the delta scanner"
	assert_contains "$s" "T000" "version-audit: T000 baseline"
	assert_contains "$s" "pilot" "version-audit: pilot unit"
	assert_contains "$s" "present, not run" "version-audit: codemod states"
	assert_contains "$(cat "$VL_VA/references/delta-catalog.md")" "@ a9fd216" "delta-catalog credits claude-plugins-official"
}

t_vledger_major_plan_tasks_shape_passes_flow_lint() {
	local d tasks base
	d=$(tmp_repo)
	mkdir -p "$d/.specs/001-next15"
	tasks="$d/.specs/001-next15/TASKS.md"
	base=$(git -C "$d" rev-parse --short HEAD)
	# the exact skeleton the Major upgrade plan section tells the agent to write
	sed -n '/^```markdown tasks-skeleton$/,/^```$/p' "$VL_VA/references/delta-catalog.md" | sed '1d;$d' |
		sed "s/<base>/$base/" >"$tasks"
	assert_contains "$(cat "$tasks")" "T000" "the skeleton was extracted from delta-catalog.md"
	run_cmd bash "$SCAN_DIR/flow-lint" "$tasks"
	assert_rc 0 "the TASKS.md skeleton in delta-catalog.md passes flow-lint"
	assert_not_contains "$(cat "$tasks")" "Approved:" "the written plan has no Approved line"
}

t_vledger_header_typo_or_empty_table_fails() {
	local d
	d=$(tmp_dir)
	_vl_fixture "$d"
	sed 's/| Re-verify |/| Reverify |/' "$d/versions.md" >"$d/v2.md"
	mv "$d/v2.md" "$d/versions.md"
	run_cmd python3 -I "$VL_LINT" "$d/versions.md"
	assert_rc 1 "a ledger whose header lacks a required column is not silently clean"
	assert_contains "$OUT" "no ledger rows" "the failure names the problem"
}

t_vledger_non_utf8_ledger_exits_2() {
	local d
	d=$(tmp_dir)
	_vl_fixture "$d"
	printf '\xff' >>"$d/versions.md"
	run_cmd python3 -I "$VL_LINT" "$d/versions.md"
	assert_rc 2 "a non-UTF-8 ledger is an unreadable ledger (2), not a traceback"
	assert_not_contains "$OUT" "Traceback" "no traceback"
}

t_vledger_model_ids_mythos_and_bedrock_version() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/src"
	cat >"$d/src/a.py" <<'PY'
m = Client(model="claude-mythos-5-1")
n = Client(model_id="us.anthropic.claude-mythos-preview-v1:0")
if "mythos-5" in m:
    pass
k = Client(model_id="anthropic.claude-opus-4-5-v2:0")
PY
	printf 'claude-mythos-5-1\nanthropic.claude-opus-4-5-v1:0\tLEGACY\n' >"$d/catalog.txt"
	run_cmd node "$VL_VA/scripts/model-ids.mjs" "$d" --catalog "$d/catalog.txt"
	assert_contains "$OUT" "a.py:1 current caller claude-mythos-5-1" "mythos IDs are listed"
	assert_contains "$OUT" "a.py:2 unknown caller us.anthropic.claude-mythos-preview-v1:0" "mythos Bedrock ID is listed"
	assert_contains "$OUT" "a.py:3 gate add-alongside mythos-5" "mythos gate is listed"
	assert_contains "$OUT" "a.py:5 unknown caller anthropic.claude-opus-4-5-v2:0" "a different Bedrock version is not the cataloged model"
}

t_vledger_model_ids_mistyped_snapshot_unknown_and_catalog_skipped() {
	local d
	d=$(tmp_dir)
	printf 'ref: anthropic.claude-opus-4-5-20250514-v1:0\n' >"$d/SKILL.md"
	printf 'claude-sonnet-4-5 ACTIVE\nanthropic.claude-sonnet-4-5-20250929-v1:0\tLEGACY\n' >"$d/catalog.txt"
	run_cmd node "$VL_VA/scripts/model-ids.mjs" "$d" --catalog "$d/catalog.txt"
	assert_contains "$OUT" "SKILL.md:1 unknown opaque anthropic.claude-opus-4-5-20250514-v1:0" "the mistyped snapshot date is reported unknown"
	assert_not_contains "$OUT" "catalog.txt:" "the catalog file inside the scanned tree is not scanned"
}

t_vledger_model_ids_legacy_status_not_current() {
	local d
	d=$(tmp_dir)
	printf 'm = Client(model_id="anthropic.claude-3-haiku-20240307-v1:0")\n' >"$d/a.py"
	printf 'anthropic.claude-3-haiku-20240307-v1:0\tLEGACY\n' >"$d/cat.txt"
	run_cmd node "$VL_VA/scripts/model-ids.mjs" "$d" --catalog "$d/cat.txt"
	assert_contains "$OUT" "a.py:1 legacy caller anthropic.claude-3-haiku-20240307-v1:0" "a LEGACY lifecycle row is reported legacy"
}

t_vledger_delta_scan_runnable_state() {
	local d
	d=$(tmp_dir)
	_vl_next_fixture "$d"
	run_cmd node "$VL_VA/scripts/delta-scan.mjs" "$d" --rules "$d/rules.json" --runnable "@next/codemod next-async-request-api"
	assert_contains "$OUT" "codemod runnable here, not run" "--runnable marks the middle state"
}
