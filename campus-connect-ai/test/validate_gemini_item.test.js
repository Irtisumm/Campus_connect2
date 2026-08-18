// ---------------------------------------------------------------------------
// Unit tests for validateGeminiItem and the Gemini prompt contract
// ---------------------------------------------------------------------------
// Run with: node --test test/validate_gemini_item.test.js
//
// These import the REAL implementations from ../src/index.js, so the prompt
// assertions below verify the prompt that is actually sent in production.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

// These now live in `src/batch.js`, NOT in the Worker entry module: Cloudflare
// treats every named export of the entry module as a Worker entrypoint, and a
// non-function export (`BATCH_MAX_CANDIDATES`) prevented workerd from starting.
import {
  validateGeminiItem,
  buildGeminiContent,
  candidateFilter,
  BATCH_MAX_CANDIDATES,
} from '../src/batch.js';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

function validItem(overrides = {}) {
  return {
    title: 'Black Backpack',
    description: 'Found near the library with a math textbook inside.',
    category: 'Bags',
    location: 'Main Library',
    dateTime: '2026-08-17T10:00:00Z',
    imageUrls: ['https://example.com/img1.jpg'],
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Test cases
// ---------------------------------------------------------------------------

describe('validateGeminiItem — location optional (Fix 1)', () => {

  // ── Case 1: Normal item with location passes ────────────────────────
  it('accepts normal item with location', () => {
    assert.strictEqual(validateGeminiItem(validItem(), 'item'), null);
  });

  // ── Case 2: Empty location string passes (inventory items) ──────────
  it('accepts item with empty location (inventory payload)', () => {
    const inv = validItem({ location: '' });
    assert.strictEqual(validateGeminiItem(inv, 'candidateItems[0]'), null);
  });

  // ── Case 3: Missing location key passes ─────────────────────────────
  it('accepts item with no location key at all', () => {
    const { location, ...rest } = validItem();
    assert.strictEqual(validateGeminiItem(rest, 'candidateItems[0]'), null);
  });

  // ── Case 4: null location passes ────────────────────────────────────
  it('accepts item with location: null', () => {
    const inv = validItem({ location: null });
    assert.strictEqual(validateGeminiItem(inv, 'candidateItems[0]'), null);
  });

  // ── Case 5: Non-required fields still enforced ──────────────────────
  it('rejects item with missing title', () => {
    const bad = validItem();
    delete bad.title;
    const err = validateGeminiItem(bad, 'anchorItem');
    assert.ok(err.includes('title'));
    assert.ok(err.includes('required'));
  });

  it('rejects item with empty description', () => {
    const bad = validItem({ description: '' });
    const err = validateGeminiItem(bad, 'anchorItem');
    assert.ok(err.includes('description'));
    assert.ok(err.includes('required'));
  });

  it('rejects item with empty category', () => {
    const bad = validItem({ category: '   ' });
    const err = validateGeminiItem(bad, 'item');
    assert.ok(err.includes('category'));
    assert.ok(err.includes('required'));
  });

  it('accepts item with empty dateTime', () => {
    const inv = validItem({ dateTime: '' });
    assert.strictEqual(validateGeminiItem(inv, 'candidateItems[0]'), null);
  });

  it('accepts item with no dateTime key at all', () => {
    const { dateTime, ...rest } = validItem();
    assert.strictEqual(validateGeminiItem(rest, 'item'), null);
  });

  it('rejects item with whitespace-only dateTime (invalid when provided)', () => {
    const bad = validItem({ dateTime: '   ' });
    const err = validateGeminiItem(bad, 'item');
    assert.ok(err.includes('dateTime'));
    assert.ok(err.includes('non-empty'));
  });

  it('rejects non-object', () => {
    const err = validateGeminiItem(null, 'test');
    assert.ok(err.includes('JSON object'));
  });

  it('rejects non-array imageUrls', () => {
    const bad = validItem({ imageUrls: 'not-an-array' });
    const err = validateGeminiItem(bad, 'item');
    assert.ok(err.includes('imageUrls'));
    assert.ok(err.includes('array'));
  });

  it('rejects empty string inside imageUrls', () => {
    const bad = validItem({ imageUrls: [''] });
    const err = validateGeminiItem(bad, 'item');
    assert.ok(err.includes('imageUrls[0]'));
    assert.ok(err.includes('non-empty'));
  });
});

// ---------------------------------------------------------------------------
// Prompt contract — Gemini is asked for VISUAL analysis + evidence ONLY
// ---------------------------------------------------------------------------

/** Extract the trailing prompt text from a real buildGeminiContent() call. */
function promptFor(lost, found) {
  const content = buildGeminiContent([], [], lost, found);
  const last = content[content.length - 1];
  assert.equal(last.type, 'text');
  return last.text;
}

describe('Gemini prompt — visual-only contract', () => {
  it('requests visualScore', () => {
    const p = promptFor(validItem(), validItem());
    assert.ok(p.includes('visualScore'));
  });

  it('requests structured evidence arrays', () => {
    const p = promptFor(validItem(), validItem());
    assert.ok(p.includes('matchingFeatures'));
    assert.ok(p.includes('conflictingFeatures'));
  });

  it('does NOT ask the model to score title/description/category', () => {
    const p = promptFor(validItem(), validItem());
    assert.ok(!p.includes('titleScore'));
    assert.ok(!p.includes('descriptionScore'));
    assert.ok(!p.includes('categoryScore'));
  });

  it('does NOT ask the model to score location or time', () => {
    const p = promptFor(validItem(), validItem());
    assert.ok(!p.includes('locationScore'));
    assert.ok(!p.includes('timeScore'));
  });

  it('does not leak location or time values into the prompt at all', () => {
    const lost = validItem({ location: 'Main Library', dateTime: '2026-08-17T10:00:00Z' });
    const found = validItem({ location: 'Cafeteria', dateTime: '2026-08-11T08:00:00Z' });
    const p = promptFor(lost, found);
    assert.ok(!p.includes('Main Library'));
    assert.ok(!p.includes('Cafeteria'));
    assert.ok(!p.includes('2026-08-17T10:00:00Z'));
  });

  it('states the generic-item rule', () => {
    const p = promptFor(validItem(), validItem());
    assert.ok(/generic/i.test(p));
    assert.ok(p.includes('visualScore <= 50'));
  });

  it('declares the exact JSON response shape', () => {
    const p = promptFor(validItem(), validItem());
    assert.ok(p.includes(
      '{"visualScore":0,"matchingFeatures":[],"conflictingFeatures":[],"confidence":0,"reason":""}'));
  });

  it('still includes the item titles, categories and descriptions as context', () => {
    const lost = validItem({ title: 'Blue Hydro Flask', category: 'Bottles' });
    const found = validItem({ title: 'Blue Flask', category: 'Bottles' });
    const p = promptFor(lost, found);
    assert.ok(p.includes('Blue Hydro Flask'));
    assert.ok(p.includes('Blue Flask'));
    assert.ok(p.includes('Bottles'));
  });

  it('interleaves image entries before the prompt text', () => {
    const lostImages = [{ dataUri: 'data:image/jpeg;base64,AAA' }];
    const foundImages = [{ dataUri: 'data:image/jpeg;base64,BBB' }];
    const content = buildGeminiContent(lostImages, foundImages, validItem(), validItem());
    assert.equal(content[0].text, 'LOST ITEM image 1:');
    assert.equal(content[1].image_url.url, 'data:image/jpeg;base64,AAA');
    assert.equal(content[2].text, 'FOUND ITEM image 1:');
    assert.equal(content[3].image_url.url, 'data:image/jpeg;base64,BBB');
    assert.equal(content[content.length - 1].type, 'text');
  });
});

// ---------------------------------------------------------------------------
// Candidate count — no silent reduction (Fix 3)
// ---------------------------------------------------------------------------

describe('Candidate batch capacity', () => {
  it('BATCH_MAX_CANDIDATES is 10', () => {
    assert.equal(BATCH_MAX_CANDIDATES, 10);
  });

  it('the Flutter client _aiMaxCandidates (10) fits within the cap', () => {
    const clientMaxCandidates = 10; // lib/services/app_state.dart
    assert.ok(clientMaxCandidates <= BATCH_MAX_CANDIDATES);
    assert.equal(clientMaxCandidates, BATCH_MAX_CANDIDATES);
  });

  it('resolves maxCandidates to the full capacity when unspecified', () => {
    // Mirrors handleBatchMatch: default is BATCH_MAX_CANDIDATES, not 5.
    const resolve = (requested) => Math.max(1, Math.min(
      typeof requested === 'number' ? requested : BATCH_MAX_CANDIDATES,
      BATCH_MAX_CANDIDATES));
    assert.equal(resolve(undefined), 10);
    assert.equal(resolve(10), 10);
    assert.equal(resolve(99), 10);
    assert.equal(resolve(3), 3);
    assert.equal(resolve(0), 1);
  });

  it('does not drop any of 10 same-category candidates', () => {
    const anchor = validItem({ category: 'Bags' });
    const candidates = Array.from({ length: 10 }, (_, i) =>
      validItem({ category: 'Bags', title: `Bag ${i}` }));
    const filtered = candidates.filter(c => candidateFilter(anchor, c));
    const maxCandidates = BATCH_MAX_CANDIDATES;
    const selected = filtered.slice(0, maxCandidates);
    assert.equal(filtered.length, 10);
    assert.equal(selected.length, 10);
    assert.equal(filtered.length - selected.length, 0); // droppedCount
  });

  it('candidateFilter still excludes different categories', () => {
    const anchor = validItem({ category: 'Bags' });
    assert.equal(candidateFilter(anchor, validItem({ category: 'Bags' })), true);
    assert.equal(candidateFilter(anchor, validItem({ category: 'Phones' })), false);
  });
});

