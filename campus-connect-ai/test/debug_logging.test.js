// ---------------------------------------------------------------------------
// Diagnostic-logging safety + batch-match failure-mode tests
// ---------------------------------------------------------------------------
// Run: node --test test/debug_logging.test.js
//
// Verifies (a) which failure modes produce which HTTP status, and (b) that the
// temporary [AI WORKER DEBUG]/[AI WORKER ERROR] logging never leaks a key,
// an Authorization header, or base64 image data.

import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import worker from '../src/index.js';

// A SYNTHETIC, NON-FUNCTIONAL key shaped like a real OpenRouter key. It exists
// only so the redaction tests can prove a key-shaped string never reaches the
// logs. This is not a secret and must never be replaced with a real key.
const FAKE_KEY = 'sk-or-v1-0000000000000000000000000000000000000000';

function item(overrides = {}) {
  return {
    title: 'Dell XPS 13 Laptop',
    description: 'Silver Dell XPS 13 with a cracked corner.',
    category: 'Electronics',
    location: 'Main Library',
    dateTime: '2026-08-17T10:00:00Z',
    imageUrls: ['https://example.invalid/a.jpg'],
    ...overrides,
  };
}

function candidate(overrides = {}) {
  return { id: 'inv-1', ...item({ location: '' }), ...overrides };
}

function batchRequest(body) {
  return new Request('https://w.example/ai/batch-match', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      // Deliberately present: must never appear in any log line.
      'Authorization': `Bearer ${FAKE_KEY}`,
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

// â”€â”€ Capture console output so the log contents can be asserted â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

let captured;
let originalLog;
let originalError;

beforeEach(() => {
  captured = [];
  originalLog = console.log;
  originalError = console.error;
  console.log = (...args) => { captured.push(args.join(' ')); };
  console.error = (...args) => { captured.push(args.join(' ')); };
});

afterEach(() => {
  console.log = originalLog;
  console.error = originalError;
});

const allLogs = () => captured.join('\n');

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// Failure modes â†’ HTTP status
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

describe('batch-match failure modes', () => {
  it('MISSING API KEY â†’ 500 (the production root cause)', async () => {
    const res = await worker.fetch(
      batchRequest({ anchorItem: item(), candidateItems: [candidate()] }),
      {}); // no OPENROUTER_API_KEY
    assert.equal(res.status, 500);
    const body = await res.json();
    assert.equal(body.success, false);
    assert.equal(body.error, 'OPENROUTER_API_KEY is not set.');
    assert.equal(body.stage, 'config-checked');
  });

  it('reports key presence as a boolean and a length, never the value', async () => {
    await worker.fetch(
      batchRequest({ anchorItem: item(), candidateItems: [candidate()] }),
      {});
    assert.match(allLogs(), /hasOpenRouterKey=false/);
    assert.match(allLogs(), /keyLength=0/);
  });

  it('a JSON null body â†’ 400, not an unhandled 500', async () => {
    const res = await worker.fetch(batchRequest('null'),
      { OPENROUTER_API_KEY: FAKE_KEY });
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.equal(body.error, 'Request body must be a JSON object.');
  });

  it('a JSON array body â†’ 400', async () => {
    const res = await worker.fetch(batchRequest('[]'),
      { OPENROUTER_API_KEY: FAKE_KEY });
    assert.equal(res.status, 400);
  });

  it('a JSON scalar body â†’ 400', async () => {
    const res = await worker.fetch(batchRequest('42'),
      { OPENROUTER_API_KEY: FAKE_KEY });
    assert.equal(res.status, 400);
  });

  it('malformed JSON â†’ 400', async () => {
    const res = await worker.fetch(batchRequest('{not json'),
      { OPENROUTER_API_KEY: FAKE_KEY });
    assert.equal(res.status, 400);
  });

  it('missing candidateItems â†’ 400', async () => {
    const res = await worker.fetch(batchRequest({ anchorItem: item() }),
      { OPENROUTER_API_KEY: FAKE_KEY });
    assert.equal(res.status, 400);
  });

  it('a candidate without an id â†’ 400', async () => {
    const res = await worker.fetch(batchRequest({
      anchorItem: item(),
      candidateItems: [{ ...item(), id: '' }],
    }), { OPENROUTER_API_KEY: FAKE_KEY });
    assert.equal(res.status, 400);
  });

  it('unreachable images â†’ 200 with a per-candidate error', async () => {
    // Key present, so the handler proceeds; image fetch fails and is caught
    // per candidate. The batch itself must still succeed.
    const res = await worker.fetch(batchRequest({
      anchorItem: item(),
      candidateItems: [candidate()],
      maxCandidates: 10,
    }), { OPENROUTER_API_KEY: FAKE_KEY });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(body.comparedCount, 1);
    assert.equal(body.results.length, 1);
    assert.ok(body.results[0].error, 'expected a per-candidate error');
    assert.equal(body.threshold, 50);
  });

  it('health stays 200 with an empty env (matches production)', async () => {
    const res = await worker.fetch(
      new Request('https://w.example/health'), {});
    assert.equal(res.status, 200);
  });
});

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// Logging safety â€” no secrets, no base64, no payloads
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

describe('diagnostic logging never leaks secrets', () => {
  async function runFullPath() {
    await worker.fetch(batchRequest({
      anchorItem: item(),
      candidateItems: [candidate()],
      maxCandidates: 10,
    }), { OPENROUTER_API_KEY: FAKE_KEY });
    return allLogs();
  }

  it('never logs the API key value', async () => {
    const logs = await runFullPath();
    assert.ok(!logs.includes(FAKE_KEY), 'API key leaked into logs');
    assert.ok(!logs.includes('sk-or-v1-'), 'key prefix leaked into logs');
  });

  it('never logs an Authorization header', async () => {
    const logs = await runFullPath();
    assert.ok(!/authorization/i.test(logs), 'Authorization leaked into logs');
    assert.ok(!/Bearer\s+sk-/i.test(logs), 'Bearer token leaked into logs');
  });

  it('never logs base64 image data or data: URIs', async () => {
    const logs = await runFullPath();
    assert.ok(!logs.includes('data:image/'), 'data: URI leaked into logs');
    assert.ok(!/;base64,/.test(logs), 'base64 payload leaked into logs');
  });

  it('never logs the item descriptions (no full payloads)', async () => {
    const logs = await runFullPath();
    assert.ok(!logs.includes('Silver Dell XPS 13 with a cracked corner'),
      'request payload leaked into logs');
  });

  it('emits the documented stage markers', async () => {
    const logs = await runFullPath();
    for (const stage of [
      'batch-start',
      'request-parsed',
      'candidates-validated',
      'batch-success',
    ]) {
      assert.match(logs, new RegExp(`\\[AI WORKER DEBUG\\] ${stage}`),
        `missing stage marker: ${stage}`);
    }
  });

  it('emits the documented error triplet on failure', async () => {
    await worker.fetch(
      batchRequest({ anchorItem: item(), candidateItems: [candidate()] }),
      {});
    const logs = allLogs();
    assert.match(logs, /\[AI WORKER ERROR\] stage=/);
    assert.match(logs, /\[AI WORKER ERROR\] name=/);
    assert.match(logs, /\[AI WORKER ERROR\] message=/);
  });

  it('redacts a key even if one reaches an error message', async () => {
    // Simulate a provider error whose text embeds a key.
    const logs = [];
    const origErr = console.error;
    console.error = (...a) => { logs.push(a.join(' ')); };
    try {
      // Drive the router catch-all with a throwing env accessor.
      const hostileEnv = {
        get OPENROUTER_API_KEY() {
          throw new Error(`upstream rejected key ${FAKE_KEY} via Bearer ${FAKE_KEY}`);
        },
      };
      const res = await worker.fetch(
        batchRequest({ anchorItem: item(), candidateItems: [candidate()] }),
        hostileEnv);
      assert.equal(res.status, 500);
    } finally {
      console.error = origErr;
    }
    const joined = logs.join('\n');
    assert.ok(!joined.includes(FAKE_KEY), 'key survived redaction');
    assert.match(joined, /<redacted-key>|Bearer <redacted>/);
  });
});
