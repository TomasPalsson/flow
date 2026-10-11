#!/usr/bin/env bash
# test_infra_guard.sh — F07: infra-guard.sh asks (permissionDecision "ask")
# before a data-destroying infra command or an obfuscated shell pipeline, and
# says nothing at all otherwise.

# _t_ig_json <command> → a PreToolUse payload with the command JSON-escaped.
_t_ig_json() {
	local c=$1
	c=${c//\\/\\\\}
	c=${c//\"/\\\"}
	printf '{"tool_input":{"command":"%s"}}' "$c"
}

_t_ig_expect_ask() {
	run_hook "$SCAN_DIR/infra-guard.sh" "$(_t_ig_json "$1")"
	assert_rc 0 "$2 rc"
	assert_contains "$OUT" '"permissionDecision":"ask"' "$2 asks"
}

_t_ig_expect_silent() {
	run_hook "$SCAN_DIR/infra-guard.sh" "$(_t_ig_json "$1")"
	assert_rc 0 "$2 rc"
	assert_eq "$OUT" "" "$2 stdout empty"
	assert_eq "$ERR" "" "$2 stderr empty"
}

t_ig_terraform_destroy_asks() { _t_ig_expect_ask 'terraform destroy -auto-approve' "t_ig_terraform_destroy_asks"; }
t_ig_terraform_chdir_destroy_asks() { _t_ig_expect_ask 'terraform -chdir=infra destroy' "t_ig_terraform_chdir_destroy_asks"; }
t_ig_terraform_apply_destroy_asks() { _t_ig_expect_ask 'terraform apply -destroy' "t_ig_terraform_apply_destroy_asks"; }
t_ig_sst_remove_asks() { _t_ig_expect_ask 'bunx sst remove --stage prod' "t_ig_sst_remove_asks"; }
t_ig_s3_rm_recursive_asks() { _t_ig_expect_ask 'aws s3 rm s3://bucket/path --recursive' "t_ig_s3_rm_recursive_asks"; }
t_ig_s3_rm_recursive_first_asks() { _t_ig_expect_ask 'aws --profile p s3 rm --recursive s3://bucket' "t_ig_s3_rm_recursive_first_asks"; }
t_ig_s3_rb_force_asks() { _t_ig_expect_ask 'aws s3 rb s3://bucket --force' "t_ig_s3_rb_force_asks"; }
t_ig_drop_table_asks() { _t_ig_expect_ask 'psql -c "DROP TABLE users"' "t_ig_drop_table_asks"; }
t_ig_drop_database_lowercase_asks() { _t_ig_expect_ask 'mysql -e "drop database app"' "t_ig_drop_database_lowercase_asks"; }
t_ig_ifs_braces_asks() { _t_ig_expect_ask 'cat${IFS}/etc/passwd' "t_ig_ifs_braces_asks"; }
t_ig_base64_pipe_sh_asks() { _t_ig_expect_ask 'echo aGk= | base64 -d | sh' "t_ig_base64_pipe_sh_asks"; }
t_ig_base64_decode_pipe_bash_asks() { _t_ig_expect_ask 'base64 --decode payload.b64 | bash' "t_ig_base64_decode_pipe_bash_asks"; }

t_ig_terraform_plan_silent() { _t_ig_expect_silent 'terraform plan' "t_ig_terraform_plan_silent"; }
t_ig_terraform_plan_destroy_silent() { _t_ig_expect_silent 'terraform plan -destroy' "t_ig_terraform_plan_destroy_silent"; }
t_ig_terraform_apply_silent() { _t_ig_expect_silent 'terraform apply' "t_ig_terraform_apply_silent"; }
t_ig_s3_ls_silent() { _t_ig_expect_silent 'aws s3 ls' "t_ig_s3_ls_silent"; }
t_ig_s3_rm_single_object_silent() { _t_ig_expect_silent 'aws s3 rm s3://bucket/one.txt' "t_ig_s3_rm_single_object_silent"; }
t_ig_s3_rb_without_force_silent() { _t_ig_expect_silent 'aws s3 rb s3://bucket' "t_ig_s3_rb_without_force_silent"; }
t_ig_while_ifs_read_silent() { _t_ig_expect_silent 'while IFS= read -r l; do echo "$l"; done < f' "t_ig_while_ifs_read_silent"; }
t_ig_bare_ifs_silent() { _t_ig_expect_silent 'IFS=, read -ra a <<< "$x"' "t_ig_bare_ifs_silent"; }
t_ig_base64_decode_to_file_silent() { _t_ig_expect_silent 'base64 -d in.b64 > out.bin' "t_ig_base64_decode_to_file_silent"; }
t_ig_sst_deploy_silent() { _t_ig_expect_silent 'bunx sst deploy' "t_ig_sst_deploy_silent"; }
t_ig_empty_command_silent() { _t_ig_expect_silent '' "t_ig_empty_command_silent"; }

t_ig_env_switch_silences() {
	run_hook "$SCAN_DIR/infra-guard.sh" "$(_t_ig_json 'terraform destroy')" CC_NO_GIT_GUARD=1
	assert_eq "$OUT" "" "t_ig_env_switch_silences CC_NO_GIT_GUARD=1"
}

t_ig_flow_unsafe_silences() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/.claude"
	: >"$d/.claude/flow.unsafe"
	run_hook "$SCAN_DIR/infra-guard.sh" "$(_t_ig_json 'terraform destroy')" CLAUDE_PROJECT_DIR="$d"
	assert_eq "$OUT" "" "t_ig_flow_unsafe_silences .claude/flow.unsafe"
	rm -rf "$d"
}

t_ig_ask_reason_names_the_escape() {
	run_hook "$SCAN_DIR/infra-guard.sh" "$(_t_ig_json 'terraform destroy')"
	assert_contains "$OUT" "CC_NO_GIT_GUARD=1" "t_ig_ask_reason_names_the_escape"
}

t_ig_registered_in_hooks_json() {
	assert_contains "$(cat "$SCAN_DIR/hooks.json")" "hooks/infra-guard.sh" "t_ig_registered_in_hooks_json"
	if command -v jq >/dev/null 2>&1; then
		assert_eq "$(jq -r '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command' "$SCAN_DIR/hooks.json" | grep -c 'infra-guard.sh')" "1" "t_ig_registered_in_hooks_json on the PreToolUse Bash matcher"
	fi
}
