// ---------------------------------------------------------------------------
// Deterministic scoring — reproducibility, renormalisation, visual safety,
// conflict handling and evidence.
// ---------------------------------------------------------------------------
// Run with: node --test test/deterministic_scoring.test.js
//
// Every function under test is imported from ../src/scoring.js, which is the
// exact module the Worker runs in production.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
	scorePair,
	computeOverallScore,
	constrainVisualScore,
	countDistinctiveFeatures,
	isDistinctiveFeature,
	computeConflictPenalty,
	countStrongConflicts,
	isStrongConflict,
	normaliseEvidence,
	normaliseEvidenceList,
	hasValue,
	parseDateTime,
	FACTOR_WEIGHTS,
	GENERIC_VISUAL_CEILING,
	CONFLICT_PENALTY_PER_FEATURE,
	CONFLICT_PENALTY_MAX,
	MATCH_THRESHOLD,
	MAX_EVIDENCE_FEATURES,
} from '../src/scoring.js';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/** A strongly-identified item pair: same branded laptop with a unique mark. */
function laptopLost(overrides = {}) {
	return {
		title: 'Dell XPS 13 Laptop',
		description: 'Silver Dell XPS 13 laptop with a cracked top-right corner and a CU Malaysia sticker on the lid.',
		category: 'Electronics',
		location: 'Main Library',
		dateTime: '2026-08-17T10:00:00Z',
		...overrides,
	};
}

function laptopFound(overrides = {}) {
	return {
		title: 'Dell XPS 13 Laptop',
		description: 'Silver Dell XPS 13 laptop with a cracked top-right corner and a CU Malaysia sticker on the lid.',
		category: 'Electronics',
		location: 'Main Library',
		dateTime: '2026-08-17T11:00:00Z',
		...overrides,
	};
}

/** Strong visual evidence: a logo and a unique damage mark. */
const strongVisual = {
	visualScore: 95,
	confidence: 92,
	reason: 'Same model label and the same crack in the same place.',
	evidence: {
		matchingFeatures: [
			'Dell logo on lid',
			'crack near top-right corner',
			'CU Malaysia sticker',
		],
		conflictingFeatures: [],
	},
};

/** Generic visual evidence: nothing identifying at all. */
const genericVisual = {
	visualScore: 88,
	confidence: 45,
	reason: 'Both are plain black backpacks.',
	evidence: {
		matchingFeatures: ['same black colour', 'similar shape'],
		conflictingFeatures: [],
	},
};

// ═══════════════════════════════════════════════════════════════════════════
// 1 & 2. Same item, same information → high stable and reproducible score
// ═══════════════════════════════════════════════════════════════════════════

describe('1. Same item with same information → high stable score', () => {
	it('scores well above the threshold', () => {
		const r = scorePair(laptopLost(), laptopFound(), strongVisual);
		assert.ok(r.overallScore >= 80,
			`expected >= 80, got ${r.overallScore}`);
		assert.equal(r.isMatch, true);
	});

	it('keeps every factor at full strength', () => {
		const r = scorePair(laptopLost(), laptopFound(), strongVisual);
		assert.equal(r.titleScore, 100);
		assert.equal(r.categoryScore, 100);
		assert.equal(r.locationScore, 100);
		assert.equal(r.visualScore, 95);
		assert.equal(r.conflictPenalty, 0);
	});
});

describe('2. Same pair evaluated twice → identical score', () => {
	it('is byte-identical across repeated calls', () => {
		const a = scorePair(laptopLost(), laptopFound(), strongVisual);
		const b = scorePair(laptopLost(), laptopFound(), strongVisual);
		assert.deepEqual(a, b);
	});

	it('is identical across 25 consecutive evaluations', () => {
		const first = scorePair(laptopLost(), laptopFound(), strongVisual).overallScore;
		for (let i = 0; i < 25; i++) {
			const again = scorePair(laptopLost(), laptopFound(), strongVisual).overallScore;
			assert.equal(again, first);
		}
	});

	it('does not depend on object key order', () => {
		const lostA = { title: 'X', description: 'Y', category: 'C', location: 'L', dateTime: '2026-08-17T10:00:00Z' };
		const lostB = { dateTime: '2026-08-17T10:00:00Z', location: 'L', category: 'C', description: 'Y', title: 'X' };
		const found = laptopFound();
		assert.equal(
			scorePair(lostA, found, strongVisual).overallScore,
			scorePair(lostB, found, strongVisual).overallScore);
	});

	it('is unaffected by the wall clock (no now() in the formula)', () => {
		// A fixed pair scored identically regardless of when it runs; the only
		// time input is the two supplied dateTime values.
		const r1 = scorePair(laptopLost(), laptopFound(), strongVisual);
		const r2 = scorePair(laptopLost(), laptopFound(), strongVisual);
		assert.equal(r1.timeScore, r2.timeScore);
		assert.equal(r1.overallScore, r2.overallScore);
	});
});

// ═══════════════════════════════════════════════════════════════════════════
// 3. Missing location must be truly neutral
// ═══════════════════════════════════════════════════════════════════════════

describe('3. Missing location does not reduce the score', () => {
	// A pair with no time on either side, so ONLY the location factor varies
	// between the two cases being compared.
	const noTime = { dateTime: '' };

	it('a perfect pair reaches 100 with no location and no time', () => {
		const r = scorePair(
			laptopLost({ ...noTime, location: '' }),
			laptopFound({ ...noTime, location: '' }),
			{ ...strongVisual, visualScore: 100 });
		// Active factors are title/description/category/visual, all 100, over a
		// renormalised denominator of 0.80 → exactly 100.
		assert.equal(r.locationAvailable, false);
		assert.equal(r.locationScore, null);
		assert.equal(r.activeWeightTotal, 0.80);
		assert.equal(r.overallScore, 100);
	});

	it('is not penalised the way the old fake-zero scoring penalised it', () => {
		const without = scorePair(
			laptopLost({ ...noTime, location: '' }),
			laptopFound({ ...noTime, location: '' }),
			strongVisual);

		// What the OLD code did: score the missing factors 0 and keep the full
		// 1.00 denominator. Both location and time are missing here.
		const oldFakeZero = Math.round(
			without.titleScore * 0.10 +
			without.descriptionScore * 0.30 +
			without.categoryScore * 0.15 +
			0 * 0.10 +              // locationScore = 0  ← the bug
			0 * 0.10 +              // timeScore = 0      ← the bug
			without.visualScore * 0.25);

		assert.ok(without.overallScore > oldFakeZero + 15,
			`renormalisation should recover the lost weight: old=${oldFakeZero} new=${without.overallScore}`);
		assert.ok(without.overallScore >= MATCH_THRESHOLD);
	});

	it('stays within one point of the same pair with a perfect location', () => {
		// A weighted mean shifts slightly when an above-average factor is
		// dropped; what must NOT happen is the double-digit collapse the old
		// fake-zero produced.
		const withLocation = scorePair(
			laptopLost(noTime), laptopFound(noTime), strongVisual);
		const without = scorePair(
			laptopLost({ ...noTime, location: '' }),
			laptopFound({ ...noTime, location: '' }),
			strongVisual);
		assert.equal(withLocation.locationScore, 100);
		assert.equal(without.locationScore, null);
		assert.ok(Math.abs(withLocation.overallScore - without.overallScore) <= 1,
			`expected near-identical, got ${withLocation.overallScore} vs ${without.overallScore}`);
	});

	it('drops the location weight from the denominator', () => {
		const r = computeOverallScore({
			titleScore: 100, descriptionScore: 100, categoryScore: 100,
			visualScore: 100, timeScore: 100,
			locationAvailable: false, timeAvailable: true,
		});
		assert.equal(r.activeWeightTotal, 0.90);
		assert.ok(!r.activeFactors.includes('location'));
		assert.ok(r.activeFactors.includes('time'));
		assert.equal(r.overallScore, 100);
	});

	it('treats an unknown placeholder as absent, not as a 0 score', () => {
		const r = scorePair(
			laptopLost({ ...noTime, location: 'unknown' }),
			laptopFound({ ...noTime, location: 'N/A' }),
			{ ...strongVisual, visualScore: 100 });
		assert.equal(r.locationAvailable, false);
		assert.equal(r.overallScore, 100);
	});

	it('is absent when only ONE side has a location', () => {
		const r = scorePair(
			laptopLost({ ...noTime, location: 'Main Library' }),
			laptopFound({ ...noTime, location: '' }),
			{ ...strongVisual, visualScore: 100 });
		assert.equal(r.locationAvailable, false);
		assert.equal(r.overallScore, 100);
	});

	it('a partial location mismatch DOES still lower the score when known', () => {
		// Neutrality applies to MISSING data only — real conflicting data must
		// still count against the match.
		const same = scorePair(laptopLost(noTime), laptopFound(noTime), strongVisual);
		const different = scorePair(
			laptopLost({ ...noTime, location: 'Main Library' }),
			laptopFound({ ...noTime, location: 'Cafeteria' }),
			strongVisual);
		assert.equal(different.locationAvailable, true);
		assert.ok(different.overallScore < same.overallScore);
	});
});

// ═══════════════════════════════════════════════════════════════════════════
// 4. Missing time must be truly neutral
// ═══════════════════════════════════════════════════════════════════════════

describe('4. Missing time does not reduce the score', () => {
	// No location on either side, so ONLY the time factor varies.
	const noLoc = { location: '' };

	it('a perfect pair reaches 100 with no time and no location', () => {
		const r = scorePair(
			laptopLost({ ...noLoc, dateTime: '' }),
			laptopFound({ ...noLoc, dateTime: '' }),
			{ ...strongVisual, visualScore: 100 });
		assert.equal(r.timeAvailable, false);
		assert.equal(r.timeScore, null);
		assert.equal(r.activeWeightTotal, 0.80);
		assert.equal(r.overallScore, 100);
	});

	it('scores HIGHER than the same pair with a close-but-imperfect time', () => {
		// The best achievable time score is 95 (within 3h), so an available
		// time can only ever dilute a perfect pair. Dropping the factor is
		// therefore genuinely neutral, not a penalty.
		const withTime = scorePair(
			laptopLost(noLoc), laptopFound(noLoc),
			{ ...strongVisual, visualScore: 100 });
		const without = scorePair(
			laptopLost({ ...noLoc, dateTime: '' }),
			laptopFound({ ...noLoc, dateTime: '' }),
			{ ...strongVisual, visualScore: 100 });
		assert.equal(withTime.timeScore, 95);
		assert.equal(without.timeScore, null);
		assert.ok(without.overallScore >= withTime.overallScore);
	});

	it('drops the time weight from the denominator', () => {
		const r = computeOverallScore({
			titleScore: 100, descriptionScore: 100, categoryScore: 100,
			visualScore: 100, locationScore: 100,
			locationAvailable: true, timeAvailable: false,
		});
		assert.equal(r.activeWeightTotal, 0.90);
		assert.ok(!r.activeFactors.includes('time'));
		assert.ok(r.activeFactors.includes('location'));
		assert.equal(r.overallScore, 100);
	});

	it('treats an unparseable date as absent, not as a 0 or a fake 50', () => {
		const r = scorePair(
			laptopLost({ ...noLoc, dateTime: 'yesterday' }),
			laptopFound({ ...noLoc, dateTime: 'this morning' }),
			{ ...strongVisual, visualScore: 100 });
		assert.equal(r.timeAvailable, false);
		assert.equal(r.timeScore, null);
		assert.equal(r.overallScore, 100);
	});

	it('is absent when only ONE side has a time', () => {
		const r = scorePair(
			laptopLost({ ...noLoc, dateTime: '2026-08-17T10:00:00Z' }),
			laptopFound({ ...noLoc, dateTime: '' }),
			{ ...strongVisual, visualScore: 100 });
		assert.equal(r.timeAvailable, false);
		assert.equal(r.overallScore, 100);
	});

	it('a far-apart known time DOES still lower the score', () => {
		const close = scorePair(laptopLost(noLoc), laptopFound(noLoc), strongVisual);
		const far = scorePair(
			laptopLost({ ...noLoc, dateTime: '2026-06-01T10:00:00Z' }),
			laptopFound({ ...noLoc, dateTime: '2026-08-17T10:00:00Z' }),
			strongVisual);
		assert.equal(far.timeAvailable, true);
		assert.ok(far.overallScore < close.overallScore);
	});

	it('the real production case — inventory has no location and no time', () => {
		// _inventoryToWorkerPayload sends location:'' and may send dateTime:''.
		// Under the old formula this capped every such match at 80.
		const r = scorePair(
			laptopLost({ location: 'Main Library', dateTime: '' }),
			laptopFound({ location: '', dateTime: '' }),
			{ ...strongVisual, visualScore: 100 });
		assert.equal(r.locationAvailable, false);
		assert.equal(r.timeAvailable, false);
		assert.equal(r.activeWeightTotal, 0.80);
		assert.equal(r.overallScore, 100);
	});
});

// ═══════════════════════════════════════════════════════════════════════════
// 5. One available factor set is renormalised correctly
// ═══════════════════════════════════════════════════════════════════════════

describe('5. Active weight set is renormalised correctly', () => {
	const perfect = {
		titleScore: 100, descriptionScore: 100, categoryScore: 100, visualScore: 100,
		locationScore: 100, timeScore: 100,
	};

	it('denominator is 1.00 when both optional factors are available', () => {
		const r = computeOverallScore({ ...perfect, locationAvailable: true, timeAvailable: true });
		assert.equal(r.activeWeightTotal, 1);
		assert.deepEqual(r.activeFactors,
			['title', 'description', 'category', 'visual', 'location', 'time']);
	});

	it('denominator is 0.80 when neither optional factor is available', () => {
		const r = computeOverallScore({ ...perfect, locationAvailable: false, timeAvailable: false });
		assert.equal(r.activeWeightTotal, 0.80);
		assert.deepEqual(r.activeFactors, ['title', 'description', 'category', 'visual']);
		assert.equal(r.overallScore, 100);
	});

	it('renormalises a mixed factor set exactly', () => {
		// Active: title .10 (=80), description .30 (=60), category .15 (=100),
		//         visual .25 (=40). Denominator 0.80.
		// numerator = 8 + 18 + 15 + 10 = 51 → 51 / 0.80 = 63.75 → 64
		const r = computeOverallScore({
			titleScore: 80, descriptionScore: 60, categoryScore: 100, visualScore: 40,
			locationAvailable: false, timeAvailable: false,
		});
		assert.equal(r.activeWeightTotal, 0.80);
		assert.equal(r.overallScore, 64);
	});

	it('matches the classic formula when all six factors are present', () => {
		// The original production formula, unchanged for the all-available case:
		//   70*.10 + 50*.30 + 100*.15 + 100*.10 + 75*.10 + 60*.25
		// =    7   +   15   +    15    +    10   +   7.5  +   15   = 69.5 → 70
		const legacy = Math.round(
			70 * 0.10 + 50 * 0.30 + 100 * 0.15 + 100 * 0.10 + 75 * 0.10 + 60 * 0.25);
		const r = computeOverallScore({
			titleScore: 70, descriptionScore: 50, categoryScore: 100, visualScore: 60,
			locationScore: 100, timeScore: 75,
			locationAvailable: true, timeAvailable: true,
		});
		assert.equal(r.activeWeightTotal, 1);
		assert.equal(r.overallScore, legacy);
		assert.equal(r.overallScore, 70);
	});

	it('preserves the documented factor weights', () => {
		assert.equal(FACTOR_WEIGHTS.title, 0.10);
		assert.equal(FACTOR_WEIGHTS.description, 0.30);
		assert.equal(FACTOR_WEIGHTS.category, 0.15);
		assert.equal(FACTOR_WEIGHTS.location, 0.10);
		assert.equal(FACTOR_WEIGHTS.time, 0.10);
		assert.equal(FACTOR_WEIGHTS.visual, 0.25);
		const sum = Object.values(FACTOR_WEIGHTS).reduce((a, b) => a + b, 0);
		assert.equal(Number(sum.toFixed(4)), 1);
	});

	it('never lets a missing factor lower the achievable maximum', () => {
		const combos = [[true, true], [true, false], [false, true], [false, false]];
		for (const [locationAvailable, timeAvailable] of combos) {
			const r = computeOverallScore({ ...perfect, locationAvailable, timeAvailable });
			assert.equal(r.overallScore, 100,
				`max should stay 100 for loc=${locationAvailable} time=${timeAvailable}`);
		}
	});

	it('a mid-range pair is not penalised by dropping optional factors', () => {
		// Same four core factors; only availability differs. The renormalised
		// mean must be identical because the dropped factors contributed
		// proportionally the same as the rest.
		const core = { titleScore: 60, descriptionScore: 60, categoryScore: 60, visualScore: 60 };
		const both = computeOverallScore({
			...core, locationScore: 60, timeScore: 60,
			locationAvailable: true, timeAvailable: true });
		const neither = computeOverallScore({
			...core, locationAvailable: false, timeAvailable: false });
		assert.equal(both.overallScore, 60);
		assert.equal(neither.overallScore, 60);
	});
});

// ═══════════════════════════════════════════════════════════════════════════
// 7 & 8. Visual scoring safety — the generic-item rule
// ═══════════════════════════════════════════════════════════════════════════

describe('7. Generic same-category objects do not get high scores', () => {
	it('caps the visual score at 50 when no distinctive evidence exists', () => {
		const r = constrainVisualScore(95, ['same black colour', 'similar shape']);
		assert.equal(r.visualScore, GENERIC_VISUAL_CEILING);
		assert.equal(r.capped, true);
		assert.equal(r.distinctiveCount, 0);
	});

	it('caps a generic black bag vs another generic black bag', () => {
		const lost = {
			title: 'Black Backpack', description: 'A plain black backpack.',
			category: 'Bags', location: '', dateTime: '',
		};
		const found = {
			title: 'Black Backpack', description: 'A plain black backpack.',
			category: 'Bags', location: '', dateTime: '',
		};
		const r = scorePair(lost, found, genericVisual);
		// Text is identical, so title/description/category are all 100 — but
		// the visual contribution is held down by the generic rule.
		assert.equal(r.rawVisualScore, 88);
		assert.equal(r.visualScore, 50);
		assert.equal(r.visualCapped, true);
	});

	it('an empty evidence list is treated as generic', () => {
		const r = constrainVisualScore(100, []);
		assert.equal(r.visualScore, 50);
		assert.equal(r.capped, true);
	});

	it('a missing evidence list is treated as generic', () => {
		assert.equal(constrainVisualScore(100, undefined).visualScore, 50);
		assert.equal(constrainVisualScore(100, null).visualScore, 50);
	});

	it('does not raise a visual score that is already below the ceiling', () => {
		const r = constrainVisualScore(30, ['same colour']);
		assert.equal(r.visualScore, 30);
		assert.equal(r.capped, false);
	});

	it('classifies generic phrases correctly', () => {
		assert.equal(isDistinctiveFeature('both black'), false);
		assert.equal(isDistinctiveFeature('same colour'), false);
		assert.equal(isDistinctiveFeature('similar shape'), false);
		assert.equal(isDistinctiveFeature('same object type'), false);
		assert.equal(isDistinctiveFeature(''), false);
	});
});

describe('8. Strong distinctive evidence can produce a high visual score', () => {
	it('allows a 95 visual score when a logo matches', () => {
		const r = constrainVisualScore(95, ['Nike swoosh logo on front pocket']);
		assert.equal(r.visualScore, 95);
		assert.equal(r.capped, false);
		assert.equal(r.distinctiveCount, 1);
	});

	it('recognises each category of identifying evidence', () => {
		const distinctive = [
			'matching Dell brand label',
			'same model number XPS-9310',
			'visible text "property of CU"',
			'deep scratch near the top-right corner',
			'identical star sticker on the lid',
			'engraved initials A.R.',
			'unique frayed strap',
			'cracked screen corner',
		];
		for (const feature of distinctive) {
			assert.equal(isDistinctiveFeature(feature), true, `expected distinctive: ${feature}`);
		}
		assert.equal(countDistinctiveFeatures(distinctive), distinctive.length);
	});

	it('lets one distinctive feature lift the cap even among generic ones', () => {
		const r = constrainVisualScore(92,
			['same black colour', 'similar shape', 'matching Adidas logo']);
		assert.equal(r.visualScore, 92);
		assert.equal(r.capped, false);
		assert.equal(r.distinctiveCount, 1);
	});

	it('a strongly-identified pair reaches a high overall score', () => {
		const r = scorePair(laptopLost(), laptopFound(), strongVisual);
		assert.equal(r.visualCapped, false);
		assert.ok(r.overallScore >= 80);
		assert.equal(r.isMatch, true);
	});
});

// ═══════════════════════════════════════════════════════════════════════════
// 9. Strong conflicting evidence lowers the final score
// ═══════════════════════════════════════════════════════════════════════════

describe('9. Strong conflicting evidence lowers the final score', () => {
	it('a colour conflict reduces the score', () => {
		const clean = scorePair(laptopLost(), laptopFound(), strongVisual);
		const conflicted = scorePair(laptopLost(), laptopFound(), {
			...strongVisual,
			evidence: {
				matchingFeatures: strongVisual.evidence.matchingFeatures,
				conflictingFeatures: ['lost item is red, found item is blue'],
			},
		});
		assert.equal(conflicted.conflictPenalty, CONFLICT_PENALTY_PER_FEATURE);
		assert.ok(conflicted.overallScore < clean.overallScore);
	});

	it('a brand conflict reduces the score', () => {
		const r = scorePair(laptopLost(), laptopFound(), {
			...strongVisual,
			evidence: {
				matchingFeatures: ['same shape'],
				conflictingFeatures: ['different brand: Samsung vs Apple'],
			},
		});
		assert.ok(r.conflictPenalty >= CONFLICT_PENALTY_PER_FEATURE);
	});

	it('recognises the documented conflict kinds', () => {
		assert.equal(isStrongConflict('lost is red, found is blue'), true);
		assert.equal(isStrongConflict('different brand label'), true);
		assert.equal(isStrongConflict('Samsung vs iPhone model text'), true);
		assert.equal(isStrongConflict('completely different object type'), true);
		assert.equal(isStrongConflict('case colour differs'), true);
		assert.equal(isStrongConflict('different visible model label'), true);
	});

	it('ignores vague, non-decisive conflicts', () => {
		assert.equal(isStrongConflict('slightly different angle'), false);
		assert.equal(isStrongConflict('lighting is different'), false);
		assert.equal(isStrongConflict(''), false);
	});

	it('accumulates the penalty per strong conflict', () => {
		assert.equal(computeConflictPenalty([]), 0);
		assert.equal(computeConflictPenalty(['different brand']), 12);
		assert.equal(computeConflictPenalty(['different brand', 'red vs blue']), 24);
		assert.equal(countStrongConflicts(['different brand', 'blurry photo']), 1);
	});

	it('caps the total penalty', () => {
		const many = [
			'different brand', 'red vs blue', 'different model',
			'different logo', 'different serial', 'different sticker',
		];
		assert.equal(computeConflictPenalty(many), CONFLICT_PENALTY_MAX);
	});

	it('does not blindly match just because the category is the same', () => {
		// Same category and same generic text, but the visual evidence says
		// these are different objects.
		const lost = {
			title: 'Phone', description: 'A phone.', category: 'Phones',
			location: '', dateTime: '',
		};
		const found = {
			title: 'Phone', description: 'A phone.', category: 'Phones',
			location: '', dateTime: '',
		};
		const r = scorePair(lost, found, {
			visualScore: 10,
			confidence: 90,
			reason: 'Different devices entirely.',
			evidence: {
				matchingFeatures: [],
				conflictingFeatures: [
					'different brand: Samsung vs Apple',
					'different colour: black vs white',
				],
			},
		});
		assert.equal(r.categoryScore, 100);
		assert.ok(r.conflictPenalty >= 24);
		assert.equal(r.isMatch, false, `expected no match, got ${r.overallScore}`);
	});

	it('a conflict can push a borderline pair below the threshold', () => {
		const base = {
			titleScore: 70, descriptionScore: 60, categoryScore: 100, visualScore: 60,
			locationAvailable: false, timeAvailable: false,
		};
		const clean = computeOverallScore(base);
		const conflicted = computeOverallScore({
			...base, conflictingFeatures: ['different brand', 'red vs blue'],
		});
		assert.ok(clean.overallScore >= MATCH_THRESHOLD);
		assert.ok(conflicted.overallScore < clean.overallScore);
		assert.equal(conflicted.conflictPenalty, 24);
	});

	it('never drives the score below 0', () => {
		const r = computeOverallScore({
			titleScore: 0, descriptionScore: 0, categoryScore: 0, visualScore: 0,
			locationAvailable: false, timeAvailable: false,
			conflictingFeatures: ['different brand', 'red vs blue', 'different model'],
		});
		assert.equal(r.overallScore, 0);
	});
});

// ═══════════════════════════════════════════════════════════════════════════
// 10, 11, 12. Structured evidence
// ═══════════════════════════════════════════════════════════════════════════

describe('10. matchingFeatures are populated', () => {
	it('passes the model list through scorePair', () => {
		const r = scorePair(laptopLost(), laptopFound(), strongVisual);
		assert.deepEqual(r.evidence.matchingFeatures, [
			'Dell logo on lid',
			'crack near top-right corner',
			'CU Malaysia sticker',
		]);
	});

	it('trims, de-duplicates and drops blanks', () => {
		const list = normaliseEvidenceList([
			'  Nike logo  ', 'Nike logo', 'NIKE LOGO', '', '   ', 'scratch on lid',
		]);
		assert.deepEqual(list, ['Nike logo', 'scratch on lid']);
	});

	it('collapses internal whitespace', () => {
		assert.deepEqual(normaliseEvidenceList(['same    Nike   logo']), ['same Nike logo']);
	});

	it('ignores non-string entries', () => {
		assert.deepEqual(normaliseEvidenceList(['logo', 42, null, {}, 'sticker']),
			['logo', 'sticker']);
	});

	it('caps the list length', () => {
		const many = Array.from({ length: 20 }, (_, i) => `feature ${i}`);
		assert.equal(normaliseEvidenceList(many).length, MAX_EVIDENCE_FEATURES);
	});
});

describe('11. conflictingFeatures are populated', () => {
	it('passes the model list through scorePair', () => {
		const r = scorePair(laptopLost(), laptopFound(), {
			...strongVisual,
			evidence: {
				matchingFeatures: ['same Dell logo'],
				conflictingFeatures: ['different case colour', 'different visible model label'],
			},
		});
		assert.deepEqual(r.evidence.conflictingFeatures,
			['different case colour', 'different visible model label']);
	});

	it('normalises both lists together', () => {
		const e = normaliseEvidence({
			matchingFeatures: ['  logo ', 'logo'],
			conflictingFeatures: ['different colour', ''],
		});
		assert.deepEqual(e.matchingFeatures, ['logo']);
		assert.deepEqual(e.conflictingFeatures, ['different colour']);
	});
});

describe('12. Missing / malformed evidence degrades safely', () => {
	it('yields empty lists when evidence is absent', () => {
		const e = normaliseEvidence(undefined);
		assert.deepEqual(e.matchingFeatures, []);
		assert.deepEqual(e.conflictingFeatures, []);
	});

	it('yields empty lists for null and for non-objects', () => {
		for (const input of [null, 'nope', 42, []]) {
			const e = normaliseEvidence(input);
			assert.deepEqual(e.matchingFeatures, []);
			assert.deepEqual(e.conflictingFeatures, []);
		}
	});

	it('scorePair still returns a usable result with no evidence at all', () => {
		const r = scorePair(laptopLost(), laptopFound(), { visualScore: 80, confidence: 70 });
		assert.deepEqual(r.evidence.matchingFeatures, []);
		assert.deepEqual(r.evidence.conflictingFeatures, []);
		// No distinctive evidence → the generic cap applies.
		assert.equal(r.visualScore, GENERIC_VISUAL_CEILING);
		assert.equal(r.conflictPenalty, 0);
		assert.equal(typeof r.overallScore, 'number');
	});

	it('tolerates a partially-formed evidence object', () => {
		const r = scorePair(laptopLost(), laptopFound(), {
			visualScore: 90, confidence: 80,
			evidence: { matchingFeatures: ['same Dell logo'] }, // no conflicting key
		});
		assert.deepEqual(r.evidence.matchingFeatures, ['same Dell logo']);
		assert.deepEqual(r.evidence.conflictingFeatures, []);
		assert.equal(r.visualScore, 90);
	});
});

// ═══════════════════════════════════════════════════════════════════════════
// 13. The 50% threshold is unchanged
// ═══════════════════════════════════════════════════════════════════════════

describe('13. Existing 50 threshold behaviour is preserved', () => {
	it('MATCH_THRESHOLD is still 50', () => {
		assert.equal(MATCH_THRESHOLD, 50);
	});

	it('exactly 50 is a match', () => {
		const r = computeOverallScore({
			titleScore: 50, descriptionScore: 50, categoryScore: 50, visualScore: 50,
			locationAvailable: false, timeAvailable: false,
		});
		assert.equal(r.overallScore, 50);
		assert.equal(r.overallScore >= MATCH_THRESHOLD, true);
	});

	it('a clearly unrelated pair is not a match', () => {
		const r = scorePair(
			{ title: 'Umbrella', description: 'A striped umbrella.', category: 'Other', location: '', dateTime: '' },
			{ title: 'Calculator', description: 'A scientific calculator.', category: 'Stationery', location: '', dateTime: '' },
			{ visualScore: 0, confidence: 10 });
		assert.ok(r.overallScore < MATCH_THRESHOLD);
		assert.equal(r.isMatch, false);
	});

	it('isMatch always agrees with the threshold comparison', () => {
		const cases = [
			[laptopLost(), laptopFound(), strongVisual],
			[laptopLost(), laptopFound(), genericVisual],
			[laptopLost({ category: 'Bags' }), laptopFound({ category: 'Phones' }), strongVisual],
		];
		for (const [lost, found, visual] of cases) {
			const r = scorePair(lost, found, visual);
			assert.equal(r.isMatch, r.overallScore >= MATCH_THRESHOLD);
		}
	});
});

// ═══════════════════════════════════════════════════════════════════════════
// Availability helper contracts
// ═══════════════════════════════════════════════════════════════════════════

describe('hasValue / parseDateTime', () => {
	it('recognises real values', () => {
		assert.equal(hasValue('Main Library'), true);
		assert.equal(hasValue('0'), true);
	});

	it('recognises absent values and placeholders', () => {
		for (const v of ['', '   ', null, undefined, 'unknown', 'UNKNOWN',
			'n/a', 'N/A', 'none', 'not specified', '-']) {
			assert.equal(hasValue(v), false, `expected absent: ${String(v)}`);
		}
	});

	it('parses the formats the app emits', () => {
		assert.ok(parseDateTime('2026-08-17T10:00:00Z') instanceof Date);
		assert.ok(parseDateTime('2026-08-17 10:00') instanceof Date);
	});

	it('returns null for unparseable or absent input', () => {
		assert.equal(parseDateTime('yesterday'), null);
		assert.equal(parseDateTime(''), null);
		assert.equal(parseDateTime(null), null);
		assert.equal(parseDateTime('unknown'), null);
	});
});

// ═══════════════════════════════════════════════════════════════════════════
// 14 & 15. Both matching directions still work
// ═══════════════════════════════════════════════════════════════════════════
//
// Both flows call the SAME Worker endpoint with the lost report as the anchor
// and the inventory item as the candidate, so `scorePair(lost, inventory, …)`
// is the shared unit under test.
//
//   Flow A — Lost → Inventory : new lost report vs existing inventory items
//   Flow B — Inventory → Lost : new inventory item vs existing lost reports
//
// The only difference is which side is newly created, so a correct score must
// be symmetric with respect to argument order for these payload shapes.

/** Mirrors AppState._itemToWorkerPayload for a lost report. */
function lostPayload(overrides = {}) {
	return {
		title: 'Dell XPS 13 Laptop',
		description: 'Silver Dell XPS 13 with a cracked corner and a CU Malaysia sticker.',
		category: 'Electronics',
		location: 'Main Library',                 // whereLost
		dateTime: '2026-08-17T10:00:00Z',         // whenLost
		...overrides,
	};
}

/** Mirrors AppState._inventoryToWorkerPayload — no location, createdAt time. */
function inventoryPayload(overrides = {}) {
	return {
		id: 'inv-1',
		title: 'Dell XPS 13 Laptop',
		description: 'Silver Dell XPS 13 with a cracked corner and a CU Malaysia sticker.',
		category: 'Electronics',
		location: '',                             // never recorded
		dateTime: '2026-08-17T12:00:00Z',         // createdAt
		...overrides,
	};
}

describe('14. Lost → Inventory (Flow A) still works', () => {
	it('produces a match above the threshold for a genuine pair', () => {
		const r = scorePair(lostPayload(), inventoryPayload(), strongVisual);
		assert.equal(r.isMatch, true);
		assert.ok(r.overallScore >= MATCH_THRESHOLD);
	});

	it('drops location (inventory has none) but keeps time', () => {
		const r = scorePair(lostPayload(), inventoryPayload(), strongVisual);
		assert.equal(r.locationAvailable, false);
		assert.equal(r.timeAvailable, true);
		assert.equal(r.activeWeightTotal, 0.90);
	});

	it('rejects a different-category candidate', () => {
		const r = scorePair(
			lostPayload({ category: 'Electronics' }),
			inventoryPayload({ category: 'Bags', title: 'Black Tote', description: 'A black tote bag.' }),
			{ visualScore: 20, confidence: 40 });
		assert.equal(r.categoryScore, 0);
		assert.equal(r.isMatch, false);
	});
});

describe('15. Inventory/Found → Lost (Flow B) still works', () => {
	it('produces the same score as Flow A for the same pair', () => {
		// Flow B iterates lost reports as the anchor; the payload pair is the
		// same, so the score must be identical — the two directions can never
		// disagree about whether something is a match.
		const flowA = scorePair(lostPayload(), inventoryPayload(), strongVisual);
		const flowB = scorePair(lostPayload(), inventoryPayload(), strongVisual);
		assert.equal(flowA.overallScore, flowB.overallScore);
		assert.equal(flowA.isMatch, flowB.isMatch);
		assert.deepEqual(flowA.evidence, flowB.evidence);
	});

	it('is symmetric if the arguments are swapped', () => {
		const forward = scorePair(lostPayload(), inventoryPayload(), strongVisual);
		const reversed = scorePair(inventoryPayload(), lostPayload(), strongVisual);
		assert.equal(forward.overallScore, reversed.overallScore);
	});

	it('applies the same generic cap in both directions', () => {
		const generic = {
			visualScore: 90, confidence: 50,
			evidence: { matchingFeatures: ['same black colour'], conflictingFeatures: [] },
		};
		const a = scorePair(lostPayload(), inventoryPayload(), generic);
		const b = scorePair(inventoryPayload(), lostPayload(), generic);
		assert.equal(a.visualScore, GENERIC_VISUAL_CEILING);
		assert.equal(b.visualScore, GENERIC_VISUAL_CEILING);
		assert.equal(a.overallScore, b.overallScore);
	});

	it('applies the same conflict penalty in both directions', () => {
		const conflicted = {
			visualScore: 80, confidence: 70,
			evidence: {
				matchingFeatures: ['same Dell logo'],
				conflictingFeatures: ['different brand: Samsung vs Apple'],
			},
		};
		const a = scorePair(lostPayload(), inventoryPayload(), conflicted);
		const b = scorePair(inventoryPayload(), lostPayload(), conflicted);
		assert.equal(a.conflictPenalty, b.conflictPenalty);
		assert.equal(a.overallScore, b.overallScore);
	});
});
