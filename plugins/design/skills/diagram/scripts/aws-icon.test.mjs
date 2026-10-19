import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { find, inline } from './aws-icon.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPT = join(here, 'aws-icon.mjs');
const INDEX = JSON.parse(readFileSync(join(here, '..', 'data', 'aws-icons.json'), 'utf8'));

function fixtureDir() {
  const dir = mkdtempSync(join(tmpdir(), 'aws-icons-'));
  mkdirSync(join(dir, 'architecture-service'), { recursive: true });
  writeFileSync(join(dir, 'architecture-service', 'AWSLambda.svg'),
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><title>Arch_AWS-Lambda_48</title><defs><linearGradient id="g"/></defs><path fill="url(#g)" d="M0 0h64v64H0z"/></svg>');
  return dir;
}
const run = (argv, env = {}) => spawnSync('node', [SCRIPT, ...argv], { encoding: 'utf8', env: { ...process.env, ...env } });

test('every alias points at an icon in the index', () => {
  for (const [alias, path] of Object.entries(INDEX.aliases)) assert.ok(INDEX.icons.includes(path), `${alias} -> ${path}`);
});

test('find: aliases win, then exact service names, services before resources', () => {
  assert.deepEqual(find('lambda'), ['architecture-service/AWSLambda']);
  assert.deepEqual(find('API Gateway'), ['architecture-service/AmazonAPIGateway']);
  assert.equal(find('dynamodb stream')[0], 'resource/AmazonDynamoDBStream');
  assert.equal(find('Elastic Container Registry')[0], 'architecture-service/AmazonElasticContainerRegistry');
  assert.deepEqual(find('no such thing zzz'), []);
});

test('inline: drops <title>, prefixes ids and their url() refs, keeps the viewBox', () => {
  const out = inline('<svg viewBox="0 0 40 40"><title>X</title><defs><clipPath id="c"/></defs><g clip-path="url(#c)"/></svg>', { x: 10, y: 20, size: 32, id: 'p' });
  assert.match(out, /^<svg x="10" y="20" width="32" height="32" viewBox="0 0 40 40" aria-hidden="true"/);
  assert.doesNotMatch(out, /<title>/);
  assert.match(out, /id="p-c"/);
  assert.match(out, /url\(#p-c\)/);
});

test('cli get reads AWS_ICONS_DIR offline and emits a placed nested svg', () => {
  const r = run(['get', 'lambda', '--x', '100', '--y', '40', '--size', '40'], { AWS_ICONS_DIR: fixtureDir() });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /<svg x="100" y="40" width="40" height="40" viewBox="0 0 64 64"/);
  assert.match(r.stdout, /id="awslambda-g"/);
});

test('cli: unknown icon and bad usage fail loudly', () => {
  assert.equal(run(['find', 'zzz nothing']).status, 1);
  assert.equal(run([]).status, 2);
});
