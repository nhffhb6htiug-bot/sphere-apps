// Exercise the real Sphere AI read-only query group using synthetic data only.
// No Supabase credentials, external APIs, payments or customer records.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const src = fs.readFileSync('supabase/functions/sphere-ai/index.ts', 'utf8');
const start = src.indexOf('    const [meResult, editorsResult, feeResult] = await Promise.all([');
const end = src.indexOf('    const ids =', start);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

test('Sphere AI starts independent profile, editor and fee reads together', async () => {
  assert.ok(start >= 0 && end > start, 'expected parallel read group in Edge Function');
  const fragment = src.slice(start, end);
  const load = new AsyncFunction('admin', 'user', fragment + '\nreturn { me, eds, feeRow };');
  const pending = [];
  const admin = {
    from(table) {
      return {
        select() { return this; },
        eq() { return this; },
        limit() { return new Promise(resolve => pending.push({table, resolve})); },
        maybeSingle() { return new Promise(resolve => pending.push({table, resolve})); }
      };
    }
  };
  const result = load(admin, {id: 'synthetic-user'});
  assert.deepEqual(pending.map(q => q.table), ['profiles', 'profiles', 'sp_settings'],
    'all three requests must start before any one completes');
  pending[0].resolve({data: {full_name: 'Test user', role: 'CLIENT'}});
  pending[1].resolve({data: [{id: 'test-editor'}]});
  pending[2].resolve({data: {value: 5}});
  const data = await result;
  assert.equal(data.me.full_name, 'Test user');
  assert.equal(data.eds[0].id, 'test-editor');
  assert.equal(data.feeRow.value, 5);
});
