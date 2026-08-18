// ---------------------------------------------------------------------------
// Deterministic scoring module — the SINGLE source of truth
// ---------------------------------------------------------------------------
//
// Every function here is PURE: same inputs → same output. No network calls,
// no AI calls, no randomness, no clocks. This module is imported by both
// `src/index.js` (the Worker) and the `test/` suites, so the tests exercise
// exactly the code that runs in production — there is no hand-synced copy.
//
// Division of responsibility in the production Gemini path:
//   • Gemini (vision model)  → visualScore, confidence, structured evidence
//   • THIS MODULE            → title, description, category, location, time,
//                              weight renormalisation, visual-score safety
//                              constraint, conflict penalty, overall score
//
// That split is what makes the overall score reproducible: five of the six
// factors never vary, and the sixth (visual) is requested at temperature 0
// and then clamped by deterministic rules.

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

/** Clamp a value to an integer between 0 and 100. */
export function clampScore(v) {
	const n = Number(v);
	if (!Number.isFinite(n)) return 0;
	return Math.max(0, Math.min(100, Math.round(n)));
}

/**
 * Normalise a single word or short phrase for fuzzy comparison.
 * - lowercase & trim
 * - strip punctuation
 * - collapse whitespace
 * - strip common suffixes that cause false mismatches ("pointy" vs "pointed")
 */
export const NORMALISE_RE = /[.,;:!?'"()]+/g;
export const TRAILING_SUFFIX = /(ed|ing|ly|s|es)$/i;

export function normaliseWord(s) {
	let t = String(s || '').trim().toLowerCase();
	t = t.replace(NORMALISE_RE, '');
	t = t.replace(/\s+/g, ' ');
	// Strip common suffixes ONLY when the remaining stem is at least 2 chars.
	t = t.replace(TRAILING_SUFFIX, (match) => {
		const stem = t.slice(0, -match.length);
		return stem.length >= 2 ? '' : match;
	});
	t = t.trim();
	return t;
}

/**
 * Normalise an array of strings: trim, lowercase, strip punctuation,
 * remove empty / duplicate entries, and apply suffix stripping.
 */
export function normaliseArray(arr) {
	if (!Array.isArray(arr)) return [];
	const seen = new Set();
	const out = [];
	for (const item of arr) {
		const n = normaliseWord(item);
		if (n && !seen.has(n)) {
			seen.add(n);
			out.push(n);
		}
	}
	return out;
}

/** Tokenise a string: lowercase, strip punctuation, split on whitespace. */
export function tokenise(s) {
	return String(s || '')
		.toLowerCase()
		.replace(/[.,;:!?'"()\[\]{}]+/g, ' ')
		.replace(/\s+/g, ' ')
		.trim()
		.split(' ')
		.filter(Boolean);
}

/**
 * Common stop-words that add noise to title/description matching.
 * "found", "lost", and "item" are stop-words here because they appear in
 * nearly every report and don't help distinguish one item from another.
 */
export const STOP_WORDS = new Set([
	'a', 'an', 'the', 'is', 'was', 'are', 'were', 'be', 'been',
	'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with',
	'it', 'its', 'this', 'that', 'my', 'me', 'i', 'you', 'your',
	'found', 'lost', 'item', 'has', 'have', 'had', 'not', 'no',
	'very', 'just', 'about', 'near', 'around', 'from',
]);

/** Remove stop-words from a token array. */
export function removeStopWords(tokens) {
	return tokens.filter(t => !STOP_WORDS.has(t) && t.length > 1);
}

/**
 * Jaccard similarity: size(intersection) / size(union).
 * Returns 0-1. Both-empty → 0 (no evidence).
 */
export function jaccard(setA, setB) {
	if (setA.size === 0 && setB.size === 0) return 0;
	const intersection = new Set([...setA].filter(x => setB.has(x)));
	const union = new Set([...setA, ...setB]);
	return intersection.size / union.size;
}

/**
 * Whether a metadata string carries real information.
 * Empty, whitespace-only, and explicit "unknown" placeholders are absent.
 * This is what drives weight renormalisation — never a 0 score.
 */
const ABSENT_PLACEHOLDERS = new Set([
	'unknown', 'unspecified', 'none', 'n/a', 'na', 'null', 'nil',
	'not specified', 'not observed', 'not available', 'unavailable', '-', '--',
]);

export function hasValue(s) {
	if (s == null) return false;
	const t = String(s).trim().toLowerCase();
	if (t === '') return false;
	return !ABSENT_PLACEHOLDERS.has(t);
}

/**
 * Parse a date/time string in the formats the app emits (ISO 8601) plus
 * "YYYY-MM-DD HH:MM". Returns a Date, or null when unparseable.
 */
export function parseDateTime(s) {
	if (!hasValue(s)) return null;
	const d = new Date(s);
	if (!isNaN(d.getTime())) return d;
	const m = String(s).match(/^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})/);
	if (m) {
		const d2 = new Date(m[1] + 'T' + m[2] + ':00');
		if (!isNaN(d2.getTime())) return d2;
	}
	return null;
}

// ---------------------------------------------------------------------------
// Structured-attribute image similarity (legacy /ai/match-test path)
// ---------------------------------------------------------------------------

/**
 * Normalise a structured-attribute object for comparison.
 * Deduplicates arrays, removes empty strings, strips trailing suffixes,
 * and ensures all expected fields exist with safe defaults.
 */
export function normalizeAttrs(attrs) {
	if (!attrs || typeof attrs !== 'object') return {};
	return {
		objectType:          normaliseWord(attrs.objectType),
		brand:               normaliseWord(attrs.brand),
		model:               normaliseWord(attrs.model),
		primaryColor:        normaliseWord(attrs.primaryColor),
		secondaryColors:     normaliseArray(attrs.secondaryColors),
		shape:               normaliseWord(attrs.shape),
		material:            normaliseWord(attrs.material),
		visibleText:         normaliseWord(attrs.visibleText),
		logos:               normaliseArray(attrs.logos),
		distinctiveFeatures: normaliseArray(attrs.distinctiveFeatures),
		condition:           normaliseWord(attrs.condition),
		damageOrMarks:       normaliseArray(attrs.damageOrMarks),
		accessories:         normaliseArray(attrs.accessories),
		sizeOrFormFactor:    normaliseWord(attrs.sizeOrFormFactor),
		confidence:          clampScore(attrs.confidence),
	};
}

/**
 * Deterministic image-similarity score (0-100) comparing two structured
 * attribute objects from the vision model.
 *
 * Field weights are tuned so that GENERIC matches (both are black bags)
 * alone cannot produce a high score. IDENTIFYING fields (brand, model,
 * logos, visible text, distinctive features, damage/marks) carry most
 * of the weight.
 *
 * Points breakdown (total ≤ 100):
 *   objectType           5   (generic — easy to match)
 *   brand               18   (identifying — strong)
 *   model               12   (identifying)
 *   primaryColor         8   (moderately useful)
 *   secondaryColors      3   (minor)
 *   shape                2   (too generic)
 *   material             2   (too generic)
 *   visibleText         15   (identifying — very strong)
 *   logos               15   (identifying — very strong)
 *   distinctiveFeatures 12   (identifying)
 *   damageOrMarks        8   (identifying)
 *   accessories          5   (sometimes useful)
 *   confidence boost    up to +20% bonus for high-confidence ID details
 */
export function computeImageSimilarity(lost, found) {
	// Normalise both attribute sets first.
	const L = normalizeAttrs(lost);
	const F = normalizeAttrs(found);

	let points = 0;

	// Fuzzy single-string comparison. Empty strings never match — an unknown
	// value is not evidence of similarity.
	const eq = (a, b) => {
		const na = normaliseWord(a);
		const nb = normaliseWord(b);
		if (!na || !nb) return false;
		return na === nb;
	};

	// Overlap ratio for normalised arrays.
	const overlap = (arrA, arrB) => {
		const a = normaliseArray(arrA);
		const b = normaliseArray(arrB);
		// NEITHER has items → no evidence either way → give partial credit
		// so the absence of details doesn't inflate the score.
		if (a.length === 0 && b.length === 0) return 0.5;
		if (a.length === 0 || b.length === 0) return 0;
		const setA = new Set(a);
		const setB = new Set(b);
		let common = 0;
		for (const item of setA) { if (setB.has(item)) common++; }
		return common / Math.max(setA.size, setB.size);
	};

	// --- Field-by-field scoring with rebalanced weights ---
	if (eq(L.objectType, F.objectType))         points += 5;
	if (L.brand && F.brand && eq(L.brand, F.brand))         points += 18;
	if (L.model && F.model && eq(L.model, F.model))         points += 12;
	if (eq(L.primaryColor, F.primaryColor))     points += 8;
	points += Math.round(overlap(L.secondaryColors,   F.secondaryColors)   * 3);
	if (eq(L.shape, F.shape))                   points += 2;
	if (eq(L.material, F.material))             points += 2;
	if (L.visibleText && F.visibleText && eq(L.visibleText, F.visibleText)) points += 15;
	points += Math.round(overlap(L.logos,               F.logos)               * 15);
	points += Math.round(overlap(L.distinctiveFeatures,  F.distinctiveFeatures)  * 12);
	points += Math.round(overlap(L.damageOrMarks,        F.damageOrMarks)        * 8);
	points += Math.round(overlap(L.accessories,          F.accessories)          * 5);

	// Cap raw points at 100.
	points = Math.min(100, points);

	// --- Confidence adjustment ---
	// High confidence with identifying details → bonus.
	// Low confidence → penalty.
	const cLost  = clampScore(L.confidence);
	const cFound = clampScore(F.confidence);
	const avgConf = (cLost + cFound) / 2;

	if (avgConf >= 70) {
		// Both vision calls found strong identifying details — boost.
		const boost = 1 + ((avgConf - 70) / 100) * 0.2; // up to +20%
		points = Math.round(Math.min(100, points * boost));
	} else if (avgConf < 40) {
		// Very low confidence — penalty.
		const penalty = 0.5 + (avgConf / 40) * 0.5; // 0.5–1.0 multiplier
		points = Math.round(points * penalty);
	}
	// 40–69: neutral — no adjustment.

	return points;
}

// ---------------------------------------------------------------------------
// Per-factor deterministic scorers
// ---------------------------------------------------------------------------
// Behaviour is unchanged from the previous in-file implementations — these
// were moved here verbatim so the production path and the tests share them.

/**
 * 0-100 deterministic title similarity.
 *
 * "Dell XPS Laptop" vs "Dell Laptop Found" → high score.
 * "Water bottle" vs "Backpack" → near zero.
 */
export function computeTitleSimilarity(titleA, titleB) {
	const a = removeStopWords(tokenise(titleA));
	const b = removeStopWords(tokenise(titleB));
	if (a.length === 0 && b.length === 0) return 0;

	const setA = new Set(a);
	const setB = new Set(b);

	// Base Jaccard score.
	const base = jaccard(setA, setB);
	let score = base * 100;

	// Bonus: check for multi-word phrase overlap (stronger signal).
	const phraseA = a.join(' ');
	const phraseB = b.join(' ');
	if (phraseA.includes(phraseB) || phraseB.includes(phraseA)) {
		score = Math.min(100, score + 20);
	}

	// Penalty: if shared tokens are only very common/generic words, cap lower.
	const commonTokens = [...setA].filter(x => setB.has(x));
	const genericSet = new Set(['black', 'white', 'blue', 'red', 'green',
		'small', 'large', 'big', 'new', 'old', 'phone', 'bag', 'laptop', 'case']);
	const specificTokens = commonTokens.filter(t => !genericSet.has(t));
	if (specificTokens.length === 0 && commonTokens.length > 0) {
		// Only generic words matched — cap at 40.
		score = Math.min(40, score);
	}

	return clampScore(score);
}

/**
 * 0-100 deterministic description similarity.
 *
 * Compares meaningful tokens. High-frequency descriptive words (colors,
 * objects) carry standard weight; rare/specific words carry more.
 */
export function computeDescriptionSimilarity(descA, descB) {
	const a = removeStopWords(tokenise(descA));
	const b = removeStopWords(tokenise(descB));
	if (a.length === 0 && b.length === 0) return 0;

	const setA = new Set(a);
	const setB = new Set(b);

	const base = jaccard(setA, setB);

	// Weighted overlap: count occurrences for stronger signal.
	const freqA = {};
	const freqB = {};
	for (const t of a) freqA[t] = (freqA[t] || 0) + 1;
	for (const t of b) freqB[t] = (freqB[t] || 0) + 1;
	let weightedOverlap = 0;
	let weightedTotal = 0;
	const allTokens = new Set([...Object.keys(freqA), ...Object.keys(freqB)]);
	for (const t of allTokens) {
		const ca = freqA[t] || 0;
		const cb = freqB[t] || 0;
		weightedOverlap += Math.min(ca, cb);
		weightedTotal += Math.max(ca, cb);
	}
	const weighted = weightedTotal > 0 ? weightedOverlap / weightedTotal : 0;

	// Blend Jaccard (structural) and weighted (content) → 0-100.
	const raw = (base * 0.4 + weighted * 0.6) * 100;

	return clampScore(raw);
}

/**
 * 100 if categories match exactly after normalisation, 0 otherwise.
 * Simple and deterministic.
 */
export function computeCategoryScore(catA, catB) {
	const a = normaliseWord(catA);
	const b = normaliseWord(catB);
	if (!a || !b) return 0;
	return a === b ? 100 : 0;
}

/**
 * 0-100 deterministic location similarity.
 *
 * "Library" vs "Main Library" → high (substring containment).
 * "Library" vs "Cafeteria" → 0.
 * "Block A Library" vs "Block B Library" → moderate (word overlap).
 *
 * Callers must check [hasValue] on both inputs first: when either side is
 * absent the location factor is DROPPED from the weighting (see
 * [computeOverallScore]) rather than scored 0.
 */
export function computeLocationScore(locA, locB) {
	const a = normaliseWord(locA);
	const b = normaliseWord(locB);
	if (!a || !b) return 0;

	// Substring containment → strong signal.
	if (a.includes(b) || b.includes(a)) return 100;

	// Token-level overlap.
	const tokensA = tokenise(a);
	const tokensB = tokenise(b);
	const setA = new Set(tokensA);
	const setB = new Set(tokensB);
	const j = jaccard(setA, setB);

	return clampScore(Math.round(j * 100));
}

/**
 * 0-100 deterministic time-proximity score.
 *
 * Callers must check that both sides parse first: when either side is absent
 * or unparseable the time factor is DROPPED from the weighting (see
 * [computeOverallScore]) rather than scored 0 or a fake 50.
 */
export function computeTimeScore(timeA, timeB) {
	const dA = parseDateTime(timeA);
	const dB = parseDateTime(timeB);
	if (!dA || !dB) return 0;

	const diffMs = Math.abs(dA.getTime() - dB.getTime());
	const diffHours = diffMs / (1000 * 60 * 60);

	if (diffHours <= 3)       return 95;
	if (diffHours <= 6)       return 85;
	if (diffHours <= 24)      return 75;
	if (diffHours <= 48)      return 60;
	if (diffHours <= 72)      return 40;
	if (diffHours <= 168)     return 20;  // 7 days
	return 5;  // more than a week
}

// ---------------------------------------------------------------------------
// Factor weights
// ---------------------------------------------------------------------------

/**
 * The general factor weights, preserved exactly as the production path has
 * always used them. They sum to 1.00 when every factor is available.
 *
 * When location and/or time are unavailable, the corresponding weight is
 * removed from the denominator and the remaining weights are renormalised —
 * see [computeOverallScore]. A missing factor therefore neither adds nor
 * removes anything from the achievable maximum.
 */
export const FACTOR_WEIGHTS = Object.freeze({
	title:       0.10,
	description: 0.30,
	category:    0.15,
	location:    0.10,
	time:        0.10,
	visual:      0.25,
});

// ---------------------------------------------------------------------------
// Visual-score safety constraint (generic-item rule)
// ---------------------------------------------------------------------------

/**
 * Ceiling applied to the visual score when the vision model reported no
 * distinctive identifying evidence. Two generic black bags cannot exceed this
 * on looks alone.
 */
export const GENERIC_VISUAL_CEILING = 50;

/**
 * Evidence phrases that indicate a DISTINCTIVE, identifying observation
 * rather than a generic property (colour/shape/type). Any matching feature
 * containing one of these tokens lifts the generic ceiling.
 */
const DISTINCTIVE_TOKENS = [
	'logo', 'brand', 'model', 'text', 'label', 'writing', 'engrav', 'emboss',
	'serial', 'imei', 'sticker', 'decal', 'badge', 'emblem', 'monogram',
	'scratch', 'crack', 'dent', 'chip', 'scuff', 'stain', 'tear', 'damage',
	'mark', 'initial', 'name', 'signature', 'keychain', 'charm', 'strap',
	'tag', 'inscription', 'pattern', 'print', 'unique', 'custom', 'distinct',
];

/**
 * Generic descriptors that never count as identifying evidence on their own.
 * A matching feature made up ONLY of these is generic.
 */
const GENERIC_ONLY_TOKENS = [
	'colour', 'color', 'black', 'white', 'grey', 'gray', 'blue', 'red',
	'green', 'yellow', 'brown', 'pink', 'purple', 'orange', 'silver', 'gold',
	'shape', 'size', 'type', 'material', 'plastic', 'metal', 'leather',
	'fabric', 'cloth', 'same', 'similar', 'both', 'generic', 'category',
	'object', 'item', 'thing', 'style', 'design', 'appearance', 'look',
];

/**
 * Whether a single evidence phrase describes a distinctive identifying detail.
 *
 * "same visible Nike logo"          → true  (logo)
 * "scratch near top-right corner"   → true  (scratch)
 * "both black"                      → false (generic colour only)
 */
export function isDistinctiveFeature(feature) {
	const t = String(feature || '').trim().toLowerCase();
	if (t === '') return false;
	for (const token of DISTINCTIVE_TOKENS) {
		if (t.includes(token)) return true;
	}
	// No distinctive token found. If the phrase is nothing but generic
	// descriptors, it is definitively generic.
	const words = t.replace(/[^a-z0-9\s]/g, ' ').split(/\s+/).filter(Boolean);
	if (words.length === 0) return false;
	const allGeneric = words.every(
		w => GENERIC_ONLY_TOKENS.includes(w) || STOP_WORDS.has(w));
	return !allGeneric;
}

/** How many of the supplied matching features are distinctive. */
export function countDistinctiveFeatures(matchingFeatures) {
	if (!Array.isArray(matchingFeatures)) return 0;
	return matchingFeatures.filter(isDistinctiveFeature).length;
}

/**
 * Apply the generic-item rule to a raw visual score from the vision model.
 *
 * The model is instructed to keep generic pairs low, but instructions are not
 * guarantees — this enforces the rule in code so the outcome is deterministic.
 *
 * • At least one DISTINCTIVE matching feature → the model's score stands.
 *   Strong evidence (brand/logo/model/visible text/damage/sticker/unique mark)
 *   is therefore still allowed to produce a high visual score.
 * • No distinctive matching features → capped at [GENERIC_VISUAL_CEILING].
 *
 * @returns {{ visualScore: number, capped: boolean, distinctiveCount: number }}
 */
export function constrainVisualScore(rawVisualScore, matchingFeatures) {
	const raw = clampScore(rawVisualScore);
	const distinctiveCount = countDistinctiveFeatures(matchingFeatures);
	if (distinctiveCount > 0) {
		return { visualScore: raw, capped: false, distinctiveCount };
	}
	const capped = Math.min(raw, GENERIC_VISUAL_CEILING);
	return { visualScore: capped, capped: capped < raw, distinctiveCount };
}

// ---------------------------------------------------------------------------
// Conflict handling
// ---------------------------------------------------------------------------

/**
 * Penalty (in final score points) charged per strong conflicting feature,
 * and the maximum total penalty.
 */
export const CONFLICT_PENALTY_PER_FEATURE = 12;
export const CONFLICT_PENALTY_MAX = 40;

/**
 * Conflicts that are decisive: a different brand/model/object type, or two
 * clearly-known different colours, mean these are not the same object.
 */
const STRONG_CONFLICT_TOKENS = [
	'brand', 'model', 'logo', 'text', 'label', 'serial', 'imei',
	'object type', 'objecttype', 'different object', 'different type',
	'sticker', 'engrav', 'inscription', 'monogram',
];

/**
 * Known colour words used to detect "red vs blue" style conflicts, where the
 * colour of both items is clearly known and clearly different.
 */
const COLOUR_WORDS = [
	'black', 'white', 'grey', 'gray', 'blue', 'red', 'green',
	'yellow', 'brown', 'pink', 'purple', 'orange', 'silver', 'gold',
];

/**
 * Phrases that explicitly assert a difference. Deliberately matches inflected
 * forms ("differ", "differs", "different", "differing") by anchoring only the
 * start of the word.
 */
const DIFFERENCE_RE =
	/\b(vs|versus|differ\w*|mismatch\w*|not\s+the\s+same|instead\s+of)\b/;

/**
 * Whether a conflicting-feature phrase is strong enough to reduce the score.
 * Vague conflicts ("slightly different angle") are ignored.
 */
export function isStrongConflict(feature) {
	const t = String(feature || '').trim().toLowerCase();
	if (t === '') return false;
	// A distinctive identifier in conflict is always strong.
	for (const token of STRONG_CONFLICT_TOKENS) {
		if (t.includes(token)) return true;
	}
	// "red vs blue" phrasing — two different known colours named together.
	const named = [...new Set(COLOUR_WORDS.filter(c => t.includes(c)))];
	if (named.length >= 2) return true;
	// One colour named alongside an explicit statement of difference.
	if (named.length >= 1 && DIFFERENCE_RE.test(t)) return true;
	// An explicitly different colour attribute ("case colour differs").
	if (/colou?r/.test(t) && DIFFERENCE_RE.test(t)) return true;
	return false;
}

/** How many of the supplied conflicting features are strong. */
export function countStrongConflicts(conflictingFeatures) {
	if (!Array.isArray(conflictingFeatures)) return 0;
	return conflictingFeatures.filter(isStrongConflict).length;
}

/**
 * Total penalty to subtract from the weighted score, given the conflicting
 * features the vision model reported. Capped so a single noisy response can
 * never drive a genuine match to zero.
 */
export function computeConflictPenalty(conflictingFeatures) {
	const strong = countStrongConflicts(conflictingFeatures);
	return Math.min(CONFLICT_PENALTY_MAX, strong * CONFLICT_PENALTY_PER_FEATURE);
}

// ---------------------------------------------------------------------------
// Evidence normalisation
// ---------------------------------------------------------------------------

/** Upper bound on stored evidence entries per list, to keep documents small. */
export const MAX_EVIDENCE_FEATURES = 8;

/**
 * Normalise one evidence list from the model: strings only, trimmed, no
 * blanks, no duplicates (case-insensitive), capped in length. Always returns
 * an array — never null — so downstream storage is predictable.
 */
export function normaliseEvidenceList(value) {
	if (!Array.isArray(value)) return [];
	const seen = new Set();
	const out = [];
	for (const entry of value) {
		if (typeof entry !== 'string') continue;
		const trimmed = entry.trim().replace(/\s+/g, ' ');
		if (trimmed === '') continue;
		const key = trimmed.toLowerCase();
		if (seen.has(key)) continue;
		seen.add(key);
		out.push(trimmed);
		if (out.length >= MAX_EVIDENCE_FEATURES) break;
	}
	return out;
}

/**
 * Normalise the evidence object returned by the vision model into the shape
 * the Dart `MatchEvidence` model expects.
 */
export function normaliseEvidence(raw) {
	const source = raw && typeof raw === 'object' ? raw : {};
	return {
		matchingFeatures: normaliseEvidenceList(source.matchingFeatures),
		conflictingFeatures: normaliseEvidenceList(source.conflictingFeatures),
	};
}

// ---------------------------------------------------------------------------
// Overall score — weighted, renormalised, conflict-adjusted
// ---------------------------------------------------------------------------

/**
 * Combine the six factors into the final 0-100 overall score.
 *
 * Renormalisation
 * ---------------
 * Title, description, category and visual are ALWAYS active. Location and
 * time are active only when [locationAvailable] / [timeAvailable] is true.
 *
 * The score is the weighted mean over the ACTIVE factors only:
 *
 *     overall = Σ(score_i × weight_i) / Σ(weight_i)      for active i
 *
 * so a missing factor is removed from both numerator and denominator. The
 * maximum achievable score therefore stays 100 whether or not location and
 * time are known — no fake "neutral 0" and no hidden ceiling.
 *
 *   both available → denominator 1.00
 *   no location    → denominator 0.90
 *   no time        → denominator 0.90
 *   neither        → denominator 0.80
 *
 * Conflict penalty
 * ----------------
 * Strong conflicting evidence is subtracted after renormalisation, so it
 * reduces the final score regardless of which factors were available.
 *
 * @returns {{ overallScore: number, weightedScore: number,
 *             activeWeightTotal: number, conflictPenalty: number,
 *             activeFactors: string[] }}
 */
export function computeOverallScore({
	titleScore,
	descriptionScore,
	categoryScore,
	visualScore,
	locationScore = 0,
	timeScore = 0,
	locationAvailable,
	timeAvailable,
	conflictingFeatures = [],
}) {
	// Always-active factors.
	const active = [
		['title',       clampScore(titleScore),       FACTOR_WEIGHTS.title],
		['description', clampScore(descriptionScore), FACTOR_WEIGHTS.description],
		['category',    clampScore(categoryScore),    FACTOR_WEIGHTS.category],
		['visual',      clampScore(visualScore),      FACTOR_WEIGHTS.visual],
	];

	// Conditionally-active factors — omitted entirely when unavailable.
	if (locationAvailable) {
		active.push(['location', clampScore(locationScore), FACTOR_WEIGHTS.location]);
	}
	if (timeAvailable) {
		active.push(['time', clampScore(timeScore), FACTOR_WEIGHTS.time]);
	}

	let numerator = 0;
	let activeWeightTotal = 0;
	for (const [, score, weight] of active) {
		numerator += score * weight;
		activeWeightTotal += weight;
	}

	// activeWeightTotal is never 0 — four factors are always active.
	const weightedScore = numerator / activeWeightTotal;

	const conflictPenalty = computeConflictPenalty(conflictingFeatures);
	const overallScore = clampScore(weightedScore - conflictPenalty);

	return {
		overallScore,
		weightedScore: clampScore(weightedScore),
		activeWeightTotal: Number(activeWeightTotal.toFixed(4)),
		conflictPenalty,
		activeFactors: active.map(([name]) => name),
	};
}

/** The acceptance threshold. Unchanged — a match is proposed at 50 or above. */
export const MATCH_THRESHOLD = 50;

/**
 * Full deterministic scoring for one lost↔found pair, given ONLY the vision
 * model's visual assessment. Every other factor is computed here.
 *
 * This is the single entry point the production path uses, so the tests
 * exercise exactly the arithmetic that runs in production.
 *
 * `locationScore` / `timeScore` are returned as `null` when the underlying
 * data was unavailable, so callers can omit them instead of storing a
 * misleading 0.
 *
 * @param {object} lost   { title, description, category, location, dateTime }
 * @param {object} found  { title, description, category, location, dateTime }
 * @param {object} visual { visualScore, confidence, reason, evidence }
 */
export function scorePair(lost, found, visual) {
	const l = lost || {};
	const f = found || {};
	const v = visual || {};
	const evidence = normaliseEvidence(v.evidence);

	// Availability is a property of the DATA, decided before any scoring.
	const locationAvailable = hasValue(l.location) && hasValue(f.location);
	const timeAvailable =
		parseDateTime(l.dateTime) !== null && parseDateTime(f.dateTime) !== null;

	const titleScore       = computeTitleSimilarity(l.title, f.title);
	const descriptionScore = computeDescriptionSimilarity(l.description, f.description);
	const categoryScore    = computeCategoryScore(l.category, f.category);
	const locationScore    = locationAvailable
		? computeLocationScore(l.location, f.location)
		: null;
	const timeScore = timeAvailable
		? computeTimeScore(l.dateTime, f.dateTime)
		: null;

	// Generic-item rule, enforced in code rather than trusted to the prompt.
	const constrained = constrainVisualScore(v.visualScore, evidence.matchingFeatures);

	const combined = computeOverallScore({
		titleScore,
		descriptionScore,
		categoryScore,
		visualScore: constrained.visualScore,
		locationScore: locationScore ?? 0,
		timeScore: timeScore ?? 0,
		locationAvailable,
		timeAvailable,
		conflictingFeatures: evidence.conflictingFeatures,
	});

	return {
		overallScore: combined.overallScore,
		titleScore,
		descriptionScore,
		categoryScore,
		locationScore,
		timeScore,
		visualScore: constrained.visualScore,
		rawVisualScore: clampScore(v.visualScore),
		visualCapped: constrained.capped,
		distinctiveFeatureCount: constrained.distinctiveCount,
		confidence: clampScore(v.confidence),
		reason: typeof v.reason === 'string' ? v.reason : '',
		evidence,
		locationAvailable,
		timeAvailable,
		activeFactors: combined.activeFactors,
		activeWeightTotal: combined.activeWeightTotal,
		weightedScore: combined.weightedScore,
		conflictPenalty: combined.conflictPenalty,
		isMatch: combined.overallScore >= MATCH_THRESHOLD,
	};
}
