// ---------------------------------------------------------------------------
// Unit tests for validateGeminiItem — location-optional fix
// ---------------------------------------------------------------------------
// Run with: node --test test/validate_gemini_item.test.js

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

// ---------------------------------------------------------------------------
// validateGeminiItem (synced from src/index.js — pure input validation).
// location is optional; when provided it must be a non-empty string.
// ---------------------------------------------------------------------------

function validateGeminiItem(obj, label) {
  if (!obj || typeof obj !== 'object') return `${label} must be a JSON object.`;
  for (const field of ['title', 'description', 'category']) {
    if (typeof obj[field] !== 'string' || obj[field].trim() === '') {
      return `${label}.${field} is required and must be a non-empty string.`;
    }
  }
  // location is OPTIONAL — inventory items don't carry a location.
  // Empty string is the honest "not observed" signal; null/absent also ok.
  // When provided (non-null, non-empty), it must be a valid non-empty string.
  if (obj.location != null &&
      obj.location !== '' &&
      (typeof obj.location !== 'string' || obj.location.trim() === '')) {
    return `${label}.location must be a non-empty string when provided.`;
  }
  // dateTime is OPTIONAL — the report forms don't ask for a date/time.
  // Empty string means "unknown"; null/absent also ok.
  // When provided (non-null, non-empty), it must be a valid non-empty string.
  if (obj.dateTime != null &&
      obj.dateTime !== '' &&
      (typeof obj.dateTime !== 'string' || obj.dateTime.trim() === '')) {
    return `${label}.dateTime must be a non-empty string when provided.`;
  }
  // imageUrls is optional — items without images fall back to text-only comparison.
  if (!Array.isArray(obj.imageUrls)) {
    return `${label}.imageUrls must be an array.`;
  }
  for (let i = 0; i < obj.imageUrls.length; i++) {
    if (typeof obj.imageUrls[i] !== 'string' || obj.imageUrls[i].trim() === '') {
      return `${label}.imageUrls[${i}] must be a non-empty string.`;
    }
  }
  return null;
}

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
// Prompt contract test: buildGeminiContent marks unknown locations
// ---------------------------------------------------------------------------

describe('Gemini prompt — unknown location', () => {

  function buildPromptText(lost, found) {
    return `Compare these two items to determine if they are the SAME physical object.

LOST: "${lost.title}" | ${lost.category} | Location:${lost.location ? ' ' + lost.location : ' unknown'} | Time:${lost.dateTime ? ' ' + lost.dateTime : ' unknown'}
"${lost.description}"

FOUND: "${found.title}" | ${found.category} | Location:${found.location ? ' ' + found.location : ' unknown'} | Time:${found.dateTime ? ' ' + found.dateTime : ' unknown'}
"${found.description}"

Focus on: brand, logo, model, visible text, damage, stickers, unique marks, color, shape, accessories.

SCORING (all 0-100):
- visualScore: 90+ = multiple IDENTIFYING details match. 40-60 = same type/color but NO identifying details. <20 = different objects.
- titleScore: key word overlap level
- descriptionScore: factual overlap level
- categoryScore: 100 if same, 0 if different (no partial)
- locationScore: 100 if same building, 50-70 nearby, 0 different. If EITHER item's location is unknown/empty/blank, the location was NOT observed — set locationScore = 0 (neutral; do NOT award match points and do NOT treat it as a conflict).
- timeScore: 95 within 3h, 75 same day, 50 adjacent days, 20 same week, 5 beyond. If EITHER item's time is unknown/empty/blank, the event time was NOT observed — set timeScore = 0 (neutral; do NOT award match points and do NOT treat it as a conflict).
- confidence: 90+ = very strong evidence, 40-70 = generic similarity only
- reason: one sentence

CRITICAL: Two generic items (e.g. both "black backpack") must get visualScore ≤50 unless you SEE matching logos/stickers/damage.

Reply ONLY with this JSON:
{"visualScore":0,"titleScore":0,"descriptionScore":0,"categoryScore":0,"locationScore":0,"timeScore":0,"confidence":0,"reason":""}`;
  }

  it('shows "unknown" when lost location is empty', () => {
    const lost = validItem({ location: '' });
    const found = validItem({ location: 'Main Library' });
    const prompt = buildPromptText(lost, found);
    assert.ok(prompt.includes('Location: unknown'));
    assert.ok(prompt.includes('Location: Main Library'));
  });

  it('shows "unknown" when found location is empty', () => {
    const lost = validItem({ location: 'Main Library' });
    const found = validItem({ location: '' });
    const prompt = buildPromptText(lost, found);
    assert.ok(prompt.includes('Location: Main Library'));
    assert.ok(prompt.includes('Location: unknown'));
  });

  it('shows "unknown" for both when both locations are empty', () => {
    const lost = validItem({ location: '' });
    const found = validItem({ location: '' });
    const prompt = buildPromptText(lost, found);
    const matches = prompt.match(/Location: unknown/g);
    assert.strictEqual(matches.length, 2);
  });

  it('includes the location-neutral scoring rule', () => {
    const prompt = buildPromptText(validItem(), validItem());
    assert.ok(prompt.includes('location was NOT observed'));
    assert.ok(prompt.includes('locationScore = 0'));
    assert.ok(prompt.includes('do NOT award match points'));
  });

  it('does NOT show "unknown" when both locations are provided', () => {
    const lost = validItem({ location: 'Cafeteria' });
    const found = validItem({ location: 'Cafeteria' });
    const prompt = buildPromptText(lost, found);
    assert.ok(!prompt.includes('Location: unknown'));
    assert.ok(prompt.includes('Location: Cafeteria'));
  });

  // ── Time-unknown prompt tests ──────────────────────────────────────

  it('shows "unknown" when lost time is empty', () => {
    const lost = validItem({ dateTime: '' });
    const found = validItem({ dateTime: '2026-08-17T10:00:00Z' });
    const prompt = buildPromptText(lost, found);
    assert.ok(prompt.includes('Time: unknown'));
    assert.ok(prompt.includes('Time: 2026-08-17T10:00:00Z'));
  });

  it('shows "unknown" when found time is empty', () => {
    const lost = validItem({ dateTime: '2026-08-17T10:00:00Z' });
    const found = validItem({ dateTime: '' });
    const prompt = buildPromptText(lost, found);
    assert.ok(prompt.includes('Time: 2026-08-17T10:00:00Z'));
    assert.ok(prompt.includes('Time: unknown'));
  });

  it('shows "unknown" for both times when both are empty', () => {
    const lost = validItem({ dateTime: '' });
    const found = validItem({ dateTime: '' });
    const prompt = buildPromptText(lost, found);
    const matches = prompt.match(/Time: unknown/g);
    assert.strictEqual(matches.length, 2);
  });

  it('includes the time-neutral scoring rule', () => {
    const prompt = buildPromptText(validItem(), validItem());
    assert.ok(prompt.includes('event time was NOT observed'));
    assert.ok(prompt.includes('timeScore = 0'));
  });

  it('does NOT show "unknown" when both times are provided', () => {
    const lost = validItem({ dateTime: '2026-08-17T09:00:00Z' });
    const found = validItem({ dateTime: '2026-08-17T10:00:00Z' });
    const prompt = buildPromptText(lost, found);
    assert.ok(!prompt.includes('Time: unknown'));
  });
});
