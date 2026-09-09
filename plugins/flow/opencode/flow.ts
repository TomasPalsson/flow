/**
 * flow — opencode plugin shim (spec 007, D-02).
 *
 * Translates opencode's plugin hooks into Claude-Code-shaped hook JSON and runs
 * the SAME bash scripts in ../hooks. The bash stays the single source of truth:
 * 3067 lines and 15 shell test files are reused, not reimplemented.
 *
 * Install: symlink this file into a plugin dir opencode scans. The loader globs
 * `{plugin,plugins}/*.{ts,js}` with symlink:true, so a symlink is fine:
 *   ln -s <repo>/plugins/flow/opencode/flow.ts ~/.config/opencode/plugin/flow.ts
 *
 * Event map (verified against anomalyco/opencode@dev, plugin API 1.18.x):
 *   SessionStart      -> experimental.chat.system.transform, once per session
 *   UserPromptSubmit  -> chat.message
 *   PreToolUse        -> tool.execute.before   (throw == deny)
 *   PostToolUse       -> tool.execute.after    (mutate output.output)
 *   SubagentStop      -> tool.execute.after, tool "task"
 *   PreCompact        -> experimental.session.compacting
 *   Stop              -> NO BLOCKING EQUIVALENT. Best effort only: see onIdle.
 *   SessionEnd        -> dispose (per instance, not per session)
 *
 * Not ported, deliberately:
 *   format-lint.sh  — opencode formats inside edit/write/patch before the tool
 *                     returns (tool/edit.ts L112, tool/write.ts L65). Use the
 *                     `formatter` config key instead of a second formatter.
 *   notify.sh       — opencode has no inbound Notification hook.
 */

import { spawn } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// ── Types (local, so this file has zero dependencies) ────────────────────────

type Bag = Record<string, any>;
type ToolInput = { tool: string; sessionID: string; callID: string; args?: Bag };
type ToolOutput = { title: string; output: string; metadata: Bag };

type Verdict =
  | { kind: 'ok' }
  | { kind: 'deny'; reason: string }
  | { kind: 'context'; text: string };

type Ctx = {
  root: string;
  client: Bag;
  seen: Set<string>;
  stop: Map<string, { inFlight: boolean; consecutive: number }>;
  guard: <T>(what: string, fn: () => Promise<T>) => Promise<T | undefined>;
};

// ── Where the bash lives ─────────────────────────────────────────────────────

const HOOKS_DIR =
  process.env.FLOW_HOOKS_DIR ||
  resolve(dirname(realpathSync(fileURLToPath(import.meta.url))), '..', 'hooks');

// Timeouts mirror hooks.json. opencode imposes NO hook timeout of its own and
// tool.execute.before carries no AbortSignal, so an unbounded shell here would
// be uncancellable — the user's escape key never reaches it.
const TIMEOUT_MS: Record<string, number> = {
  'session-context.sh': 10_000,
  'codebase-map.sh': 20_000,
  'worklog-hook.sh': 15_000,
  'turn-stamp.sh': 5_000,
  'tool-stamp.sh': 5_000,
  'git-guard.sh': 10_000,
  'spec-gate.sh': 15_000,
  'size-guard.sh': 20_000,
  'tamper-notice.sh': 10_000,
  'post-bash-write.sh': 90_000,
  'stop-gate.sh': 600_000,
  'pre-compact-backup.sh': 20_000,
  'postcompact-context.sh': 10_000,
  'subagent-log.sh': 10_000,
};

const CLAUDE_TOOL: Record<string, string> = {
  bash: 'Bash',
  edit: 'Edit',
  write: 'Write',
  patch: 'Edit',
  task: 'Task',
};

const EDIT_TOOLS = ['edit', 'write', 'patch'];

// ── Run one bash hook and read Claude's hook protocol back out of it ─────────

export function runHook(script: string, payload: Bag, directory: string): Promise<Verdict> {
  return new Promise((done) => {
    const child = spawn('bash', [resolve(HOOKS_DIR, script)], {
      cwd: directory,
      env: { ...process.env, CLAUDE_PROJECT_DIR: directory },
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    let out = '';
    let err = '';
    let settled = false;
    const finish = (v: Verdict) => {
      if (settled) return;
      settled = true;
      done(v);
    };

    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      // Fail OPEN on timeout: a wedged formatter must not brick the session.
      finish({ kind: 'context', text: `[flow] ${script} timed out; check skipped.` });
    }, TIMEOUT_MS[script] ?? 30_000);

    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (err += d));
    child.on('error', (e) =>
      finish({ kind: 'context', text: `[flow] ${script} could not run: ${e.message}` })
    );
    child.on('close', (code) => {
      clearTimeout(timer);
      finish(interpret(code ?? 0, out, err, script));
    });

    child.stdin.end(JSON.stringify(payload));
  });
}

/**
 * The bash side speaks Claude's hook protocol via lib/hookout.sh:
 *   hook_deny     stdout {"hookSpecificOutput":{...,"permissionDecision":"deny",...}}
 *   hook_block    stdout {"decision":"block","reason":...}
 *   hook_feedback stderr + exit 2
 *   hook_note     stdout {"systemMessage":...}
 *   hook_soft     stdout {"hookSpecificOutput":{...,"additionalContext":...}}
 *   hook_ok       exit 0, silent
 * Anything else on stdout is plain context (session-context.sh does this).
 */
export function interpret(code: number, out: string, err: string, script: string): Verdict {
  if (code === 2) {
    return { kind: 'deny', reason: err.trim() || `${script} refused this action.` };
  }

  const text = out.trim();
  if (!text) return { kind: 'ok' };

  if (text.startsWith('{')) {
    try {
      const j = JSON.parse(text);
      const hs = j.hookSpecificOutput;
      if (hs?.permissionDecision === 'deny') {
        return { kind: 'deny', reason: String(hs.permissionDecisionReason ?? script) };
      }
      if (j.decision === 'block') return { kind: 'deny', reason: String(j.reason ?? script) };
      if (hs?.additionalContext) return { kind: 'context', text: String(hs.additionalContext) };
      if (j.systemMessage) return { kind: 'context', text: String(j.systemMessage) };
      return { kind: 'ok' };
    } catch {
      // not JSON after all — fall through and treat it as context
    }
  }
  return { kind: 'context', text };
}

// Run several hooks in order; the first deny wins, context accumulates.
async function runAll(scripts: string[], payload: Bag, directory: string) {
  const notes: string[] = [];
  for (const s of scripts) {
    const v = await runHook(s, payload, directory);
    if (v.kind === 'deny') return { deny: v.reason, notes };
    if (v.kind === 'context') notes.push(v.text);
  }
  return { deny: null as string | null, notes };
}

// ── opencode arg shapes -> Claude's tool_input shape ────────────────────────

export function toolInput(tool: string, args: Bag = {}): Bag {
  switch (tool) {
    case 'bash':
      return { command: args.command ?? '', description: args.description ?? '' };
    case 'edit':
      return {
        file_path: args.filePath ?? '',
        old_string: args.oldString ?? '',
        new_string: args.newString ?? '',
      };
    case 'write':
      return { file_path: args.filePath ?? '', content: args.content ?? '' };
    case 'patch':
      return { file_path: args.filePath ?? '', content: args.patch ?? '' };
    default:
      return { ...args };
  }
}

function denyError(reason: string) {
  const e: any = new Error(reason);
  e.__flowDeny = true;
  return e;
}

// ── Handlers, one per opencode hook ─────────────────────────────────────────

// SessionStart. opencode has no session-start event, so the context is pushed
// on the first LLM request of each session and de-duped by session id.
const onSystemTransform = (c: Ctx) => (input: Bag, output: { system: string[] }) =>
  c.guard('session-context', async () => {
    const id = input.sessionID;
    if (!id || c.seen.has(id)) return;
    c.seen.add(id);
    const { notes } = await runAll(
      ['session-context.sh', 'codebase-map.sh', 'worklog-hook.sh'],
      { session_id: id, source: 'startup', cwd: c.root },
      c.root
    );
    // Mutate in place — opencode reads the original array, not a reassignment.
    for (const n of notes) output.system.push(n);
  });

// UserPromptSubmit.
const onChatMessage = (c: Ctx) => (input: Bag, output: { parts: Bag[] }) =>
  c.guard('turn-stamp', async () => {
    const { notes } = await runAll(
      ['turn-stamp.sh'],
      { session_id: input.sessionID, cwd: c.root },
      c.root
    );
    for (const n of notes) output.parts.push({ type: 'text', text: n });
  });

// PreToolUse. Throwing here rejects the tool before it executes and the message
// reaches the model as the tool error — this is a real deny.
const onPreTool = (c: Ctx) => (input: ToolInput, output: { args: Bag }) =>
  c.guard('pre-tool', async () => {
    const scripts =
      input.tool === 'bash'
        ? ['tool-stamp.sh', 'git-guard.sh']
        : EDIT_TOOLS.includes(input.tool)
          ? ['spec-gate.sh']
          : [];
    if (!scripts.length) return;

    const { deny } = await runAll(
      scripts,
      {
        session_id: input.sessionID,
        hook_event_name: 'PreToolUse',
        tool_name: CLAUDE_TOOL[input.tool] ?? input.tool,
        tool_input: toolInput(input.tool, output.args),
        cwd: c.root,
      },
      c.root
    );
    if (deny) throw denyError(deny);
  });

// PostToolUse. Never throw here: the file is already written, so a throw tells
// the model the tool failed while the change sits on disk.
const onPostTool = (c: Ctx) => (input: ToolInput, output: ToolOutput) =>
  c.guard('post-tool', async () => {
    const scripts = EDIT_TOOLS.includes(input.tool)
      ? ['size-guard.sh', 'tamper-notice.sh']
      : input.tool === 'bash'
        ? ['post-bash-write.sh']
        : input.tool === 'task'
          ? ['subagent-log.sh']
          : [];
    if (!scripts.length) return;

    const { deny, notes } = await runAll(
      scripts,
      {
        session_id: input.sessionID,
        hook_event_name: 'PostToolUse',
        tool_name: CLAUDE_TOOL[input.tool] ?? input.tool,
        tool_input: toolInput(input.tool, input.args),
        tool_response: { output: output.output },
        last_assistant_message: input.tool === 'task' ? output.output : '',
        cwd: c.root,
      },
      c.root
    );
    // A post-tool "deny" is only ever advice here; surface it as text.
    const all = deny ? [...notes, deny] : notes;
    if (all.length) output.output += '\n\n' + all.join('\n');
  });

// PreCompact — awaited, and it can also carry flow's compact instructions.
const onCompacting =
  (c: Ctx) => (input: Bag, output: { context: string[]; prompt?: string }) =>
    c.guard('pre-compact', async () => {
      const { notes } = await runAll(
        ['pre-compact-backup.sh', 'postcompact-context.sh'],
        { session_id: input.sessionID, trigger: 'auto', cwd: c.root },
        c.root
      );
      for (const n of notes) output.context.push(n);
    });

/**
 * STOP GATE — best effort, and honestly not a gate.
 *
 * opencode has NO hook that can stop a turn from ending. session.idle is
 * published after the agent loop has already broken, and the `event` hook is
 * fire-and-forget (`void hook["event"]?.(...)`), so it cannot delay or veto
 * anything. Upstream issue #16626 (session.stopping) is open and unimplemented.
 *
 * What this does instead: when the turn goes idle, run stop-gate.sh; if the
 * gates are red, inject a follow-up user turn. Differences from the Claude Code
 * Stop hook the user should know about:
 *   - the model's "I'm done" is already on screen; this corrects after the fact
 *     rather than preventing it,
 *   - the continuation is a VISIBLE user message,
 *   - session.idle also fires on user-abort, so a nudge can fight the escape key,
 *   - under headless `opencode run` the CLI exits on the same idle transition,
 *     so this loses the race entirely. For unattended work use `flow loop run`
 *     driving `opencode run --session <id>`: that is a real, deterministic gate.
 */
const onIdle = (c: Ctx) => (payload: Bag) =>
  c.guard('stop-gate', async () => {
    if (payload?.event?.type !== 'session.idle') return;
    const id = payload.event.properties?.sessionID;
    if (!id) return;

    const st = c.stop.get(id) ?? { inFlight: false, consecutive: 0 };
    if (st.inFlight) return;
    if (st.consecutive >= 3) return; // wedge valve, same as stop-gate.sh
    st.inFlight = true;
    c.stop.set(id, st);

    try {
      const v = await runHook(
        'stop-gate.sh',
        { session_id: id, stop_hook_active: st.consecutive > 0, cwd: c.root },
        c.root
      );
      if (v.kind !== 'deny') {
        st.consecutive = 0;
        return;
      }
      st.consecutive += 1;
      await c.client.session.promptAsync({
        path: { id },
        body: { parts: [{ type: 'text', text: v.reason }] },
        query: { directory: c.root },
      });
    } finally {
      st.inFlight = false;
      c.stop.set(id, st);
    }
  });

// ── The plugin ───────────────────────────────────────────────────────────────

export default {
  id: 'flow',
  async server({ client, directory, worktree }: Bag) {
    const root = worktree || directory;

    const log = (message: string, level = 'info') =>
      client.app?.log({ body: { service: 'flow', level, message } }).catch(() => {});

    // A thrown hook is swallowed by opencode's loader and the gate silently
    // vanishes. Every handler is wrapped so a bug surfaces as a log line instead
    // of a harness that quietly stopped enforcing anything.
    const guard: Ctx['guard'] = async (what, fn) => {
      try {
        return await fn();
      } catch (e: any) {
        if (e?.__flowDeny) throw e; // a real deny must propagate
        await log(`${what} failed: ${e?.message ?? e}`, 'error');
        return undefined;
      }
    };

    // One plugin instance serves EVERY session in this directory, so all state
    // is keyed by sessionID. A shared counter would let sibling sessions trip
    // each other's wedge valve.
    const c: Ctx = { root, client, seen: new Set(), stop: new Map(), guard };

    return {
      'experimental.chat.system.transform': onSystemTransform(c),
      'chat.message': onChatMessage(c),
      'tool.execute.before': onPreTool(c),
      'tool.execute.after': onPostTool(c),
      'experimental.session.compacting': onCompacting(c),
      event: onIdle(c),
      dispose: async () => {
        await guard('worklog', () => runAll(['worklog-hook.sh'], { cwd: root }, root));
      },
    };
  },
};
