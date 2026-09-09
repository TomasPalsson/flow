/**
 * Self-check for the opencode shim. Run it with:  bun plugins/flow/opencode/flow.test.ts
 *
 * The whole risk of the shim strategy is one thing: does the Claude-shaped JSON
 * this file synthesizes actually satisfy the real bash hooks? So the important
 * cases here run the REAL scripts in ../hooks, not mocks.
 */

import { strict as assert } from 'node:assert';
import { resolve } from 'node:path';
import plugin, { interpret, runHook, toolInput } from './flow.ts';

const ROOT = resolve(import.meta.dir, '..', '..', '..');
let failures = 0;

async function check(name: string, fn: () => void | Promise<void>) {
  try {
    await fn();
    console.log(`  ok   ${name}`);
  } catch (e: any) {
    failures += 1;
    console.log(`  FAIL ${name}\n       ${e?.message ?? e}`);
  }
}

console.log('interpret() decodes the lib/hookout.sh protocol');

await check('exit 2 + stderr is a deny (hook_feedback)', () => {
  const v = interpret(2, '', 'size guard says no', 'size-guard.sh');
  assert.equal(v.kind, 'deny');
  assert.equal((v as any).reason, 'size guard says no');
});

await check('permissionDecision deny is a deny (hook_deny)', () => {
  const json = JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: 'no force pushes',
    },
  });
  const v = interpret(0, json, '', 'git-guard.sh');
  assert.equal(v.kind, 'deny');
  assert.equal((v as any).reason, 'no force pushes');
});

await check('decision block is a deny (hook_block)', () => {
  const v = interpret(0, JSON.stringify({ decision: 'block', reason: 'tests are red' }), '', 's');
  assert.equal(v.kind, 'deny');
  assert.equal((v as any).reason, 'tests are red');
});

await check('additionalContext is context, not a deny (hook_soft)', () => {
  const json = JSON.stringify({
    hookSpecificOutput: { hookEventName: 'Stop', additionalContext: 'heads up' },
  });
  const v = interpret(0, json, '', 'stop-gate.sh');
  assert.equal(v.kind, 'context');
  assert.equal((v as any).text, 'heads up');
});

await check('systemMessage is context (hook_note)', () => {
  const v = interpret(0, JSON.stringify({ systemMessage: 'fyi' }), '', 's');
  assert.equal(v.kind, 'context');
  assert.equal((v as any).text, 'fyi');
});

await check('silent exit 0 is ok (hook_ok)', () => {
  assert.equal(interpret(0, '', '', 's').kind, 'ok');
});

await check('plain stdout is context (session-context.sh)', () => {
  const v = interpret(0, 'branch: main\ndirty: 0', '', 'session-context.sh');
  assert.equal(v.kind, 'context');
  assert.equal((v as any).text, 'branch: main\ndirty: 0');
});

await check('malformed JSON degrades to context, never to a deny', () => {
  const v = interpret(0, '{not really json', '', 's');
  assert.equal(v.kind, 'context');
});

console.log('\ntoolInput() maps opencode args onto Claude tool_input');

await check('bash -> command', () => {
  assert.deepEqual(toolInput('bash', { command: 'ls -la', description: 'list' }), {
    command: 'ls -la',
    description: 'list',
  });
});

await check('edit -> file_path / old_string / new_string', () => {
  assert.deepEqual(toolInput('edit', { filePath: '/a.ts', oldString: 'x', newString: 'y' }), {
    file_path: '/a.ts',
    old_string: 'x',
    new_string: 'y',
  });
});

await check('write -> file_path / content', () => {
  assert.deepEqual(toolInput('write', { filePath: '/b.ts', content: 'hi' }), {
    file_path: '/b.ts',
    content: 'hi',
  });
});

await check('missing args never yield undefined fields', () => {
  assert.deepEqual(toolInput('write', {}), { file_path: '', content: '' });
});

console.log('\nthe REAL bash hooks accept the synthesized payload');

const preToolPayload = (command: string) => ({
  session_id: 'shim-selfcheck',
  hook_event_name: 'PreToolUse',
  tool_name: 'Bash',
  tool_input: toolInput('bash', { command }),
  cwd: ROOT,
});

await check('git-guard.sh DENIES a destructive command', async () => {
  const destructive = ['git', 'push', '--force', 'origin', 'main'].join(' ');
  const v = await runHook('git-guard.sh', preToolPayload(destructive), ROOT);
  assert.equal(v.kind, 'deny', `expected a deny, got ${JSON.stringify(v)}`);
  assert.ok((v as any).reason.length > 0, 'a deny must carry a reason the model can read');
});

await check('git-guard.sh ALLOWS an ordinary command', async () => {
  const v = await runHook('git-guard.sh', preToolPayload('ls -la'), ROOT);
  assert.notEqual(v.kind, 'deny', `expected no deny, got ${JSON.stringify(v)}`);
});

await check('git-guard.sh allows a safe command that merely mentions force', async () => {
  const v = await runHook('git-guard.sh', preToolPayload('echo "do not --force it"'), ROOT);
  assert.notEqual(v.kind, 'deny', `expected no deny, got ${JSON.stringify(v)}`);
});

await check('an unknown script fails open, never closed', async () => {
  const v = await runHook('does-not-exist.sh', preToolPayload('ls'), ROOT);
  assert.notEqual(v.kind, 'deny', 'a missing hook must not deny every command');
});

console.log('\nthe plugin itself wires up the way opencode expects');

const logged: string[] = [];
const fakeClient = {
  app: { log: async ({ body }: any) => void logged.push(body.message) },
  session: { promptAsync: async () => {} },
};
const hooks: any = await plugin.server({ client: fakeClient, directory: ROOT, worktree: ROOT });

await check('server() returns only real opencode hook names', () => {
  const known = [
    'experimental.chat.system.transform',
    'chat.message',
    'tool.execute.before',
    'tool.execute.after',
    'experimental.session.compacting',
    'event',
    'dispose',
  ];
  for (const k of Object.keys(hooks)) assert.ok(known.includes(k), `unknown hook name: ${k}`);
});

await check('tool.execute.before THROWS on a destructive bash command', async () => {
  const destructive = ['git', 'push', '--force', 'origin', 'main'].join(' ');
  await assert.rejects(
    () =>
      hooks['tool.execute.before'](
        { tool: 'bash', sessionID: 'shim-selfcheck', callID: 'c1' },
        { args: { command: destructive } }
      ),
    (e: any) => e.__flowDeny === true && typeof e.message === 'string' && e.message.length > 0
  );
});

await check('tool.execute.before stays silent on an ordinary command', async () => {
  await hooks['tool.execute.before'](
    { tool: 'bash', sessionID: 'shim-selfcheck', callID: 'c2' },
    { args: { command: 'ls -la' } }
  );
});

await check('tool.execute.before ignores tools it does not guard', async () => {
  await hooks['tool.execute.before'](
    { tool: 'read', sessionID: 'shim-selfcheck', callID: 'c3' },
    { args: { filePath: '/etc/hosts' } }
  );
});

await check('tool.execute.after appends to output.output and never throws', async () => {
  const output = { title: 't', output: 'original', metadata: {} };
  await hooks['tool.execute.after'](
    { tool: 'write', sessionID: 'shim-selfcheck', callID: 'c4', args: { filePath: '/tmp/x.ts', content: 'x' } },
    output
  );
  assert.ok(output.output.startsWith('original'), 'the tool result must be preserved, not replaced');
});

await check('system.transform injects once per session, not every request', async () => {
  const out = { system: [] as string[] };
  await hooks['experimental.chat.system.transform']({ sessionID: 'once-test' }, out);
  const afterFirst = out.system.length;
  await hooks['experimental.chat.system.transform']({ sessionID: 'once-test' }, out);
  assert.equal(out.system.length, afterFirst, 'second request must not re-inject session context');
});

await check('event ignores everything that is not session.idle', async () => {
  await hooks.event({ event: { type: 'file.edited', properties: { file: '/a.ts' } } });
});

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
