---
name: aws-context
description: Detect active AWS environment — profile, region, account ID, credential validity. Used by aws-explore and other AWS-related workflows.
---

# AWS Context Detection

Before running AWS exploration or debugging commands, verify the environment is configured.

## Detection Steps

1. **Check credentials are valid**:
   ```bash
   aws sts get-caller-identity --no-cli-pager --query '{Account:Account,Arn:Arn}' 2>/dev/null
   ```
   If this fails, tell the user to run `aws sso login` to authenticate.

2. **Identify active context**:
   - `$AWS_PROFILE` — which profile is active
   - `$AWS_DEFAULT_REGION` — active region (defaults to `eu-west-1` if unset)
   - Account ID and ARN from `sts get-caller-identity`

3. **Check for `.envrc`** in the current directory — if present, direnv should have loaded the profile automatically. If `$AWS_PROFILE` is empty but `.envrc` exists, the user may need to run `direnv allow`.

4. **Compare with the account the repo intends.** Look for a declared account in this order and stop at the first hit: `CLAUDE.md`, `.envrc`, `sst.config.ts`, the terraform backend or provider block. A 12-digit id counts, and so does a profile name; resolve a profile name to an id with:
   ```bash
   aws configure get sso_account_id --profile <profile>
   ```
   Compare that id with the `Account` from step 1.
   - **Different:** report both ids and stop before any read or plan. Running against the wrong client account is the failure this step exists to prevent.
   - **Nothing declared (or a profile that does not resolve):** report `ACCOUNT_MATCH=unverified` and continue. Absence never blocks, or every repo without a declaration would stop.

## Output

Report to the calling workflow:
- `AWS_PROFILE`: the active profile name (or "default")
- `AWS_REGION`: the active region
- `AWS_ACCOUNT`: the 12-digit account ID
- `AWS_IDENTITY`: the ARN of the caller (role or user)
- `CREDS_VALID`: true/false
- `ACCOUNT_MATCH`: true|false|unverified (false means stop; the intended and actual ids are in the report)

## NEVER Do

- **NEVER run `aws sso login` programmatically** — it requires browser interaction
- **NEVER modify `~/.aws/config` or `~/.aws/credentials`** — only read them
- **NEVER cache or store AWS credentials** in any file
