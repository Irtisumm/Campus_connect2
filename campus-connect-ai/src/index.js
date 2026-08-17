const responses = {
	'/': {
		success: true,
		service: 'Campus Connect AI Matching',
		status: 'ready',
	},
	'/health': {
		success: true,
		status: 'healthy',
	},
};

// ---------------------------------------------------------------------------
// Secondary Cloudflare account — Workers AI REST API credentials
// ---------------------------------------------------------------------------

// Cloudflare credentials are read from environment variables — never hardcoded.
// Set CF_ACCOUNT_ID and CF_API_TOKEN in .dev.vars for local dev, or via
// `wrangler secret put` for production.
const CF_API_BASE = 'https://api.cloudflare.com/client/v4/accounts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function jsonError(message, status = 400) {
	return Response.json({ success: false, error: message }, { status });
}

/** Extract a JSON object from an AI text response that may be wrapped in
 *  markdown fences or have extra text before/after.  Also handles the case
 *  where the AI binding already returns a parsed object. */
function extractJson(text) {
	// If the AI already returned a parsed object, use it.
	if (text && typeof text === 'object' && !Array.isArray(text)) {
		// Recognise both scoring output (titleScore) and vision attributes (objectType).
		if ('titleScore' in text || 'objectType' in text) return text;
		return null;
	}
	if (typeof text !== 'string') text = String(text || '');
	// Strip ```json ... ``` fences.
	const fence = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/i);
	const raw = fence ? fence[1].trim() : text.trim();
	// Find the outermost { … }.
	const start = raw.indexOf('{');
	const end = raw.lastIndexOf('}');
	if (start === -1 || end === -1 || end <= start) return null;
	try {
		return JSON.parse(raw.slice(start, end + 1));
	} catch {
		return null;
	}
}

/** Validate that all required string fields exist and are non-empty. */
function validateItem(obj, label) {
	const required = ['title', 'description', 'category', 'location', 'dateTime', 'imageUrl'];
	for (const key of required) {
		if (typeof obj[key] !== 'string' || obj[key].trim() === '') {
			return `${label}.${key} is required and must be a non-empty string`;
		}
	}
	return null;
}

/** Clamp a value between 0 and 100. */
function clampScore(v) {
	const n = Number(v);
	if (!Number.isFinite(n)) return 0;
	return Math.max(0, Math.min(100, Math.round(n)));
}

// ---------------------------------------------------------------------------
// Text normalisation helpers — reduce vision-model wording variation
// ---------------------------------------------------------------------------

/**
 * Normalise a single word or short phrase for fuzzy comparison.
 * - lowercase & trim
 * - strip punctuation
 * - collapse whitespace
 * - strip common suffixes that cause false mismatches ("pointy" vs "pointed")
 */
const NORMALISE_RE = /[.,;:!?'"()]+/g;
const TRAILING_SUFFIX = /(ed|ing|ly|s|es)$/i;

function normaliseWord(s) {
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
function normaliseArray(arr) {
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

// ---------------------------------------------------------------------------
// Deterministic image-similarity scoring
// ---------------------------------------------------------------------------

/**
 * Deterministic image-similarity score (0-100) comparing two structured
 * attribute objects from the vision model.
 *
 * Field weights are tuned so that GENERIC matches (both are black bags)
 * alone cannot produce a high score.  IDENTIFYING fields (brand, model,
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
function computeImageSimilarity(lost, found) {
	// Normalise both attribute sets first.
	const L = normalizeAttrs(lost);
	const F = normalizeAttrs(found);

	let points = 0;

	// Fuzzy single-string comparison.  Empty strings never match — an unknown
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
	// Confidence should reflect how many IDENTIFYING details were found,
	// not just how recognisable the object type is.
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

/**
 * Normalise a structured-attribute object for comparison.
 * Deduplicates arrays, removes empty strings, strips trailing suffixes,
 * and ensures all expected fields exist with safe defaults.
 */
function normalizeAttrs(attrs) {
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

// ---------------------------------------------------------------------------
// Deterministic metadata scoring
// ---------------------------------------------------------------------------
// These replace the previous LLM-based Step 3.  Every function is pure:
// same inputs → same output, no AI calls, no randomness.

/** Tokenise a string: lowercase, strip punctuation, split on whitespace. */
function tokenise(s) {
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
const STOP_WORDS = new Set([
	'a', 'an', 'the', 'is', 'was', 'are', 'were', 'be', 'been',
	'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with',
	'it', 'its', 'this', 'that', 'my', 'me', 'i', 'you', 'your',
	'found', 'lost', 'item', 'has', 'have', 'had', 'not', 'no',
	'very', 'just', 'about', 'near', 'around', 'from',
]);

/** Remove stop-words from a token array. */
function removeStopWords(tokens) {
	return tokens.filter(t => !STOP_WORDS.has(t) && t.length > 1);
}

/**
 * Jaccard similarity: size(intersection) / size(union).
 * Returns 0-1.  Both-empty → 0 (no evidence).
 */
function jaccard(setA, setB) {
	if (setA.size === 0 && setB.size === 0) return 0;
	const intersection = new Set([...setA].filter(x => setB.has(x)));
	const union = new Set([...setA, ...setB]);
	return intersection.size / union.size;
}

// ---------------------------------------------------------------------------
// Title similarity
// ---------------------------------------------------------------------------

/**
 * 0-100 deterministic title similarity.
 *
 * "Dell XPS Laptop" vs "Dell Laptop Found" → high score.
 * "Water bottle" vs "Backpack" → near zero.
 */
function computeTitleSimilarity(titleA, titleB) {
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

// ---------------------------------------------------------------------------
// Description similarity
// ---------------------------------------------------------------------------

/**
 * 0-100 deterministic description similarity.
 *
 * Compares meaningful tokens.  High-frequency descriptive words (colors,
 * objects) carry standard weight; rare/specific words carry more.
 */
function computeDescriptionSimilarity(descA, descB) {
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

// ---------------------------------------------------------------------------
// Category score
// ---------------------------------------------------------------------------

/**
 * 100 if categories match exactly after normalisation, 0 otherwise.
 * Simple and deterministic.
 */
function computeCategoryScore(catA, catB) {
	const a = normaliseWord(catA);
	const b = normaliseWord(catB);
	if (!a || !b) return 0;
	return a === b ? 100 : 0;
}

// ---------------------------------------------------------------------------
// Location score
// ---------------------------------------------------------------------------

/**
 * 0-100 deterministic location similarity.
 *
 * "Library" vs "Main Library" → high (substring containment).
 * "Library" vs "Cafeteria" → 0.
 * "Block A Library" vs "Block B Library" → moderate (word overlap).
 */
function computeLocationScore(locA, locB) {
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

// ---------------------------------------------------------------------------
// Time score
// ---------------------------------------------------------------------------

/**
 * 0-100 deterministic time-proximity score.
 *
 * Parses dateTime strings in common formats (ISO, "YYYY-MM-DD HH:MM").
 * Falls back to 50 if parsing fails (neutral — no penalty, no boost).
 */
function computeTimeScore(timeA, timeB) {
	const parse = (s) => {
		if (!s) return null;
		// Try ISO / common formats.
		const d = new Date(s);
		if (!isNaN(d.getTime())) return d;
		// Try "YYYY-MM-DD HH:MM" or "YYYY-MM-DD HH:MM:SS"
		const m = String(s).match(/^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})/);
		if (m) {
			const d2 = new Date(m[1] + 'T' + m[2] + ':00');
			if (!isNaN(d2.getTime())) return d2;
		}
		return null;
	};

	const dA = parse(timeA);
	const dB = parse(timeB);
	if (!dA || !dB) return 50; // unparseable — neutral

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
// /ai/test
// ---------------------------------------------------------------------------

async function handleAiTest(env) {
	if (!env || !env.AI) {
		return { success: false, ai: "not bound", hint: "Ensure wrangler.jsonc contains {\"ai\":{\"binding\":\"AI\"}}" };
	}

	const MODEL = "@cf/meta/llama-3.2-11b-vision-instruct";
	const messages = [
		{ role: "user", content: "Say hello in one short sentence." }
	];

	const isAgreementDone = (msg) => msg.includes("5016") && msg.includes("Thank you for agreeing");
	const isLicenseNeeded = (msg) => msg.includes("5016") && !msg.includes("Thank you for agreeing");

	async function tryNormal() {
		return await env.AI.run(MODEL, { messages });
	}

	try {
		const result = await tryNormal();
		return {
			success: true,
			ai: "connected",
			model: MODEL,
			result: result,
		};
	} catch (firstErr) {
		const firstMsg = String(firstErr.message || firstErr);

		if (isLicenseNeeded(firstMsg)) {
			try {
				await env.AI.run(MODEL, { prompt: "agree" });
			} catch (agreeErr) {
				const agreeMsg = String(agreeErr.message || agreeErr);
				if (!isAgreementDone(agreeMsg)) {
					return {
						success: false,
						ai: "agreement_failed",
						error: { message: agreeMsg, name: agreeErr.name || null },
						step: "license_agreement",
					};
				}
			}
		} else if (isAgreementDone(firstMsg)) {
			// Agreement already done — retry.
		} else {
			return {
				success: false,
				ai: "error",
				model: MODEL,
				error: {
					message: firstMsg,
					name: firstErr.name || null,
					code: firstErr.code || null,
					reference: firstErr.reference || null,
				},
			};
		}

		try {
			const result = await tryNormal();
			return {
				success: true,
				ai: "connected",
				model: MODEL,
				result: result,
				note: "license agreement completed",
			};
		} catch (retryErr) {
			return {
				success: false,
				ai: "error_after_agreement",
				model: MODEL,
				error: {
					message: String(retryErr.message || retryErr),
					name: retryErr.name || null,
					code: retryErr.code || null,
					reference: retryErr.reference || null,
				},
			};
		}
	}
}

// ---------------------------------------------------------------------------
// /ai/match-test — Lost & Found matching prototype
// ---------------------------------------------------------------------------

/** Maximum image size the Worker will fetch (5 MiB). */
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

/**
 * Fetch a public image URL and return the raw base64 bytes the model expects
 * (no `data:` prefix).  Also returns the MIME type and full data URI for
 * debugging.
 */
async function fetchImageAsBase64(imageUrl, label) {
	let response;
	try {
		response = await fetch(imageUrl, {
			headers: { Accept: "image/*" },
		});
	} catch {
		throw new Error(`${label}: Could not fetch image from \"${imageUrl}\".`);
	}

	if (!response.ok) {
		throw new Error(
			`${label}: Image fetch returned HTTP ${response.status} from \"${imageUrl}\".`
		);
	}

	const contentType = (response.headers.get("Content-Type") || "").toLowerCase();
	if (!contentType.startsWith("image/")) {
		throw new Error(
			`${label}: URL does not point to an image (Content-Type: \"${contentType}\").`
		);
	}

	const arrayBuffer = await response.arrayBuffer();
	if (arrayBuffer.byteLength > MAX_IMAGE_BYTES) {
		throw new Error(
			`${label}: Image is too large (${(arrayBuffer.byteLength / 1024 / 1024).toFixed(1)} MiB; max ${MAX_IMAGE_BYTES / 1024 / 1024} MiB).`
		);
	}

	// Convert ArrayBuffer → base64 in chunks to stay within Worker CPU limits.
	const bytes = new Uint8Array(arrayBuffer);
	const chunkSize = 8192;
	let binary = "";
	for (let i = 0; i < bytes.length; i += chunkSize) {
		binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
	}
	const base64 = btoa(binary);
	const mimeType = contentType.split(";")[0].trim(); // strip charset if present
	const dataUri = `data:${mimeType};base64,${base64}`;

	return { base64, mimeType, dataUri };
}

// ---------------------------------------------------------------------------
// POST /ai/vision-test — single-image sanity check
// ---------------------------------------------------------------------------

async function handleVisionTest(request, env) {
	if (!env || !env.AI) {
		return jsonError("AI binding is not available.", 503);
	}

	let body;
	try { body = await request.json(); } catch {
		return jsonError("Request body must be valid JSON.");
	}
	if (!body || typeof body.imageUrl !== 'string' || body.imageUrl.trim() === '') {
		return jsonError("Missing required field: imageUrl (a public HTTPS image URL).");
	}

	const MODEL = "@cf/meta/llama-3.2-11b-vision-instruct";

	let img;
	try {
		img = await fetchImageAsBase64(body.imageUrl, "imageUrl");
	} catch (e) {
		return jsonError(e.message);
	}

		const messages = [
			{
				role: "user",
				content: [
					{ type: "image_url", image_url: { url: img.dataUri } },
					{ type: "text", text: "Describe the item shown in this image in detail." },
				],
			},
		];

		try {
			const aiResult = await env.AI.run(MODEL, { messages });
			const output = typeof aiResult === 'string' ? aiResult
				: (aiResult.response || aiResult.text || JSON.stringify(aiResult));
			return Response.json({
				success: true,
				model: MODEL,
				imageMimeType: img.mimeType,
				description: output,
			});
		} catch (e) {
			return Response.json({
				success: false,
				error: {
					message: String(e.message || e),
					name: e.name || null,
					code: e.code || null,
					reference: e.reference || null,
				},
			}, { status: 502 });
		}
}

// ---------------------------------------------------------------------------
// POST /ai/match-test — two-image Lost vs Found comparison
// ---------------------------------------------------------------------------

/**
 * Weighted-factor matching using Llama 3.2 Vision.
 *
 * Three-step pipeline:
 *   (1) Vision call — structured attributes from the lost item image.
 *   (2) Vision call — structured attributes from the found item image.
 *   (3) Deterministic scoring — image similarity + title + description +
 *       category + location + time, all computed in the Worker.
 * No LLM is used for metadata scoring — all five metadata factors are
 * pure functions (same inputs → same output).
 *
 * Weighted overall score (threshold 50):
 *   title 10% + description 30% + category 15% + location 10% +
 *   time 10% + image 25%
 */
async function handleMatchTest(request, env) {
	if (!env || !env.AI) {
		return jsonError("AI binding is not available. Check wrangler.jsonc.", 503);
	}

	// Parse & validate the request body.
	let body;
	try {
		body = await request.json();
	} catch {
		return jsonError("Request body must be valid JSON.");
	}

	if (!body || typeof body !== 'object') {
		return jsonError("Request body must be a JSON object.");
	}

	const lost = body.lostItem;
	const found = body.foundItem;
	if (!lost || typeof lost !== 'object') return jsonError("Missing required field: lostItem");
	if (!found || typeof found !== 'object') return jsonError("Missing required field: foundItem");

	const lostErr = validateItem(lost, 'lostItem');
	if (lostErr) return jsonError(lostErr);
	const foundErr = validateItem(found, 'foundItem');
	if (foundErr) return jsonError(foundErr);

	// Fetch both images and convert to base64.
	let lostImg, foundImg;
	try {
		lostImg = await fetchImageAsBase64(lost.imageUrl, "lostItem.imageUrl");
	} catch (e) {
		return jsonError(e.message);
	}
	try {
		foundImg = await fetchImageAsBase64(found.imageUrl, "foundItem.imageUrl");
	} catch (e) {
		return jsonError(e.message);
	}

		const MODEL = "@cf/meta/llama-3.2-11b-vision-instruct";

		// Construct the structured-attribute vision prompt for one item.
		const visionPrompt = (label, item) =>
`Analyse the image of this ${label} item.  Extract ONLY what you can
actually SEE in the image.  Do NOT invent details that are not visible.

Item metadata (may help — but prefer what is visible in the image):
  Title:       ${item.title}
  Description: ${item.description}
  Category:    ${item.category}
  Location:    ${item.location}
  Date/Time:   ${item.dateTime}

PRIORITY: Focus on IDENTIFYING details that would distinguish this
specific item from other similar items.  The most valuable fields are:
  - brand / logo
  - model name or number
  - visible text (labels, tags, serial numbers, writing)
  - stickers, keychains, patches, pins, custom decorations
  - damage: scratches, cracks, dents, stains, tears
  - unique colour patterns, unusual markings
  - distinctive accessories attached to the item

Generic information like "black", "rectangular", "plastic" is less
useful for matching — still report it, but spend more effort looking
for the identifying details listed above.

CONFIDENCE calibration:
- 90-100 = I found MULTIPLE identifying details (logo, text, damage, stickers, unique features)
- 70-89  = I found ONE clear identifying detail
- 40-69  = The object type is clear but I found NO identifying details (e.g. a plain black backpack with nothing unique visible)
- 10-39  = The image is unclear or the object is partially visible
- 0-9    = I cannot determine what the object is

Reply with EXACTLY this JSON object and nothing else.  Use empty strings
and empty arrays for anything you cannot determine from the image:
{
  "objectType": "",
  "brand": "",
  "model": "",
  "primaryColor": "",
  "secondaryColors": [],
  "shape": "",
  "material": "",
  "visibleText": "",
  "logos": [],
  "distinctiveFeatures": [],
  "condition": "",
  "damageOrMarks": [],
  "accessories": [],
  "sizeOrFormFactor": "",
  "confidence": 0
}`;

		// --- Step 1: Vision — lost item structured attributes ---
		let lostAttrs, lostRaw;
		try {
			const lostResult = await env.AI.run(MODEL, {
				messages: [{
					role: "user",
					content: [
						{ type: "image_url", image_url: { url: lostImg.dataUri } },
						{ type: "text", text: visionPrompt("lost", lost) },
					],
				}],
			});
			lostRaw = typeof lostResult === 'string' ? lostResult
				: (lostResult.response || lostResult.text || JSON.stringify(lostResult));
			lostAttrs = extractJson(lostRaw);
		} catch (e) {
			return Response.json({
				success: false,
				error: { step: "describe_lost", message: String(e.message || e) },
			}, { status: 502 });
		}
		if (!lostAttrs || typeof lostAttrs.objectType !== 'string') {
			return Response.json({
				success: false,
				error: "Vision model did not return structured attributes for the lost item image.",
			}, { status: 502 });
		}

		// --- Step 2: Vision — found item structured attributes ---
		let foundAttrs, foundRaw;
		try {
			const foundResult = await env.AI.run(MODEL, {
				messages: [{
					role: "user",
					content: [
						{ type: "image_url", image_url: { url: foundImg.dataUri } },
						{ type: "text", text: visionPrompt("found", found) },
					],
				}],
			});
			foundRaw = typeof foundResult === 'string' ? foundResult
				: (foundResult.response || foundResult.text || JSON.stringify(foundResult));
			foundAttrs = extractJson(foundRaw);
		} catch (e) {
			return Response.json({
				success: false,
				error: { step: "describe_found", message: String(e.message || e) },
			}, { status: 502 });
		}
		if (!foundAttrs || typeof foundAttrs.objectType !== 'string') {
			return Response.json({
				success: false,
				error: "Vision model did not return structured attributes for the found item image.",
			}, { status: 502 });
		}

		// --- Compute imageScore programmatically (deterministic) ---
		const imageScore = computeImageSimilarity(lostAttrs, foundAttrs);

		// --- Step 3: Deterministic metadata scoring (no LLM) ---
		const titleScore       = computeTitleSimilarity(lost.title, found.title);
		const descriptionScore = computeDescriptionSimilarity(lost.description, found.description);
		const categoryScore    = computeCategoryScore(lost.category, found.category);
		const locationScore    = computeLocationScore(lost.location, found.location);
		const timeScore        = computeTimeScore(lost.dateTime, found.dateTime);

		// Build an explainable reason string from the scores.
		const reasonParts = [];
		if (imageScore >= 70)  reasonParts.push(`strong visual match (${imageScore}%)`);
		else if (imageScore >= 40) reasonParts.push(`moderate visual match (${imageScore}%)`);
		else if (imageScore > 0)   reasonParts.push(`low visual similarity (${imageScore}%)`);
		else                       reasonParts.push('no visual similarity');

		if (titleScore >= 60)      reasonParts.push('titles match well');
		else if (titleScore === 0) reasonParts.push('titles differ');
		if (descriptionScore >= 60) reasonParts.push('descriptions overlap');
		else if (descriptionScore === 0) reasonParts.push('descriptions differ');
		if (categoryScore === 100) reasonParts.push('same category');
		else reasonParts.push('different categories');
		if (locationScore >= 80) reasonParts.push('location matches');
		else if (locationScore > 0) reasonParts.push('partial location match');
		if (timeScore >= 85) reasonParts.push('times are close');
		else if (timeScore >= 60) reasonParts.push('times are within a day or two');
		else reasonParts.push('times are far apart');
		const reason = reasonParts.join('; ') + '.';

		const overallScore = Math.round(
			titleScore       * 0.10 +
			descriptionScore * 0.30 +
			categoryScore    * 0.15 +
			locationScore    * 0.10 +
			timeScore        * 0.10 +
			imageScore       * 0.25
		);
		const isMatch = overallScore >= 50;

		return Response.json({
			success: true,
			match: {
				overallScore,
				titleScore,
				descriptionScore,
				categoryScore,
				locationScore,
				timeScore,
				imageScore,
				isMatch,
				reason,
			},
		});
}

// ---------------------------------------------------------------------------
// Second-account AI helper — calls the REST API with auto-license-agreement
// ---------------------------------------------------------------------------

/**
 * Call the Workers AI REST API on the SECOND account.
 * Handles model license agreement (code 5016) automatically.
 */
async function callSecondAccountAI(env, model, body) {
	const accountId = env.CF_ACCOUNT_ID;
	const apiToken = env.CF_API_TOKEN;
	if (!accountId || !apiToken) {
		return { error: 'CF_ACCOUNT_ID and CF_API_TOKEN must be set.' };
	}
	const url = `${CF_API_BASE}/${accountId}/ai/run/${model}`;
	const headers = {
		'Authorization': `Bearer ${apiToken}`,
		'Content-Type': 'application/json',
	};

	let response = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
	let result = await response.json();

	// Auto-agree to model license if required.
	if (!response.ok && result.errors) {
		const hasLicenseError = result.errors.some(
			e => String(e.code) === '5016' && String(e.message || '').includes('agree')
		);
		if (hasLicenseError) {
			// Submit the "agree" prompt.
			await fetch(url, {
				method: 'POST',
				headers,
				body: JSON.stringify({ prompt: 'agree' }),
			});
			// Retry the original request.
			response = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
			result = await response.json();
		}
	}

	return { ok: response.ok, status: response.status, result };
}

// ---------------------------------------------------------------------------
// GET /ai/new-account-test — verify SECOND Cloudflare account connectivity
// ---------------------------------------------------------------------------

async function handleNewAccountTest(env) {
	const MODEL = '@cf/meta/llama-3.2-11b-vision-instruct';

	const body = {
		messages: [
			{ role: 'user', content: 'Say hello in one short sentence.' },
		],
	};

	let r;
	try {
		r = await callSecondAccountAI(env, MODEL, body);
	} catch (e) {
		return {
			success: false,
			accountConnected: false,
			error: `Network error reaching Cloudflare API: ${e.message || e}`,
		};
	}

	if (!r.ok) {
		return {
			success: false,
			accountConnected: false,
			httpStatus: r.status,
			cfErrors: r.result.errors || null,
			cfMessages: r.result.messages || null,
		};
	}

	// Extract the text response from the AI result.
	const aiOutput = typeof r.result.result === 'string'
		? r.result.result
		: (r.result.result?.response || r.result.result?.text || JSON.stringify(r.result.result));

	return {
		success: true,
		accountConnected: true,
		model: MODEL,
		response: aiOutput,
	};
}

// ---------------------------------------------------------------------------
// POST /ai/multi-image-test — test multi-image capability on second account
// ---------------------------------------------------------------------------

async function handleMultiImageTest(request, env) {
	// Parse body.
	let body;
	try { body = await request.json(); } catch {
		return jsonError('Request body must be valid JSON.');
	}

	const imageUrl1 = typeof body.imageUrl1 === 'string' ? body.imageUrl1.trim() : '';
	const imageUrl2 = typeof body.imageUrl2 === 'string' ? body.imageUrl2.trim() : '';
	if (!imageUrl1) return jsonError('Missing required field: imageUrl1');
	if (!imageUrl2) return jsonError('Missing required field: imageUrl2');

	// Fetch both images as base64 data URIs.
	let img1, img2;
	try {
		img1 = await fetchImageAsBase64(imageUrl1, 'imageUrl1');
	} catch (e) {
		return jsonError(e.message);
	}
	try {
		img2 = await fetchImageAsBase64(imageUrl2, 'imageUrl2');
	} catch (e) {
		return jsonError(e.message);
	}

	const MODEL = '@cf/meta/llama-3.2-11b-vision-instruct';

	// Build a single request with BOTH images in the content array.
	const aiBody = {
		messages: [
			{
				role: 'user',
				content: [
					{ type: 'image_url', image_url: { url: img1.dataUri } },
					{ type: 'image_url', image_url: { url: img2.dataUri } },
					{
						type: 'text',
						text: 'Analyze both images together. Describe what is shown in each image and determine whether they appear to show the same physical item. Explain the visual evidence.',
					},
				],
			},
		],
	};

	let r;
	try {
		r = await callSecondAccountAI(env, MODEL, aiBody);
	} catch (e) {
		return Response.json({
			success: false,
			multiImageSupported: false,
			error: `Network error: ${e.message || e}`,
		}, { status: 502 });
	}

	if (!r.ok) {
		// Check if the error is specifically about multiple images.
		const errors = r.result.errors || [];
		const errorMessages = errors.map(e => e.message || '').join(' ');
		const errorCodes = errors.map(e => String(e.code || '')).join(',');

		const isImageLimitError =
			errorMessages.includes('one image') ||
			errorMessages.includes('single image') ||
			errorMessages.includes('multiple images') ||
			errorMessages.includes('too many images') ||
			errorCodes.includes('3030');

		return Response.json({
			success: false,
			multiImageSupported: false,
			httpStatus: r.status,
			cfErrors: errors,
			error: isImageLimitError
				? 'Model rejected multiple images in one request — only single-image input is supported.'
				: `API error: ${errorMessages || 'Unknown error'}`,
		}, { status: isImageLimitError ? 200 : 502 });
	}

	// Success — extract the response text.
	const aiOutput = typeof r.result.result === 'string'
		? r.result.result
		: (r.result.result?.response || r.result.result?.text || JSON.stringify(r.result.result));

	return Response.json({
		success: true,
		multiImageSupported: true,
		model: MODEL,
		response: aiOutput,
	});
}

// ---------------------------------------------------------------------------
// POST /ai/openrouter-multi-image-test — test Gemini multi-image via OpenRouter
// ---------------------------------------------------------------------------

const OPENROUTER_BASE = 'https://openrouter.ai/api/v1/chat/completions';

async function handleOpenRouterMultiImageTest(request, env) {
	const apiKey = env.OPENROUTER_API_KEY;
	if (!apiKey) {
		return Response.json({
			success: false,
			error: 'OPENROUTER_API_KEY is not set. Add it to .dev.vars.',
		}, { status: 500 });
	}

	// Parse body.
	let body;
	try { body = await request.json(); } catch {
		return jsonError('Request body must be valid JSON.');
	}

	const image1Url = typeof body.image1Url === 'string' ? body.image1Url.trim() : '';
	const image2Url = typeof body.image2Url === 'string' ? body.image2Url.trim() : '';
	if (!image1Url) return jsonError('Missing required field: image1Url');
	if (!image2Url) return jsonError('Missing required field: image2Url');

	// Fetch both images as base64 data URIs.
	let img1, img2;
	try {
		img1 = await fetchImageAsBase64(image1Url, 'image1Url');
	} catch (e) {
		return jsonError(e.message);
	}
	try {
		img2 = await fetchImageAsBase64(image2Url, 'image2Url');
	} catch (e) {
		return jsonError(e.message);
	}

	const MODEL = 'google/gemini-2.5-flash';
	const requestBody = {
		model: MODEL,
		messages: [
			{
				role: 'user',
				content: [
					{ type: 'image_url', image_url: { url: img1.dataUri } },
					{ type: 'image_url', image_url: { url: img2.dataUri } },
					{
						type: 'text',
						text: 'Analyze both images together. Describe what is shown in each image and determine whether they appear to show the same physical item. Explain the visual evidence.',
					},
				],
			},
		],
	};

	let response;
	try {
		response = await fetch(OPENROUTER_BASE, {
			method: 'POST',
			headers: {
				'Authorization': `Bearer ${apiKey}`,
				'Content-Type': 'application/json',
				'HTTP-Referer': 'http://localhost:8787',
			},
			body: JSON.stringify(requestBody),
		});
	} catch (e) {
		return Response.json({
			success: false,
			multiImageSupported: false,
			error: `Network error calling OpenRouter: ${e.message || e}`,
		}, { status: 502 });
	}

	const result = await response.json();

	if (!response.ok) {
		return Response.json({
			success: false,
			multiImageSupported: false,
			httpStatus: response.status,
			openRouterError: result.error || result,
		}, { status: 502 });
	}

	// Extract the text response.
	const choice = result.choices?.[0];
	const aiOutput = choice?.message?.content || choice?.text || JSON.stringify(result);

	return Response.json({
		success: true,
		multiImageSupported: true,
		model: MODEL,
		provider: 'openrouter',
		response: aiOutput,
	});
}

// ---------------------------------------------------------------------------
// POST /ai/gemini-match-test — full Lost vs Found comparison via Gemini 2.5 Flash
// ---------------------------------------------------------------------------

/**
 * Validate a single item object for the gemini-match-test endpoint.
 * Returns an error string or null.
 */
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

const GEMINI_MODEL = 'google/gemini-2.5-flash';
const MAX_IMAGES_PER_ITEM = 3;
const BATCH_MAX_CANDIDATES = 10;

// ---------------------------------------------------------------------------
// Reusable Gemini comparison — call this for each lost↔found pair
// ---------------------------------------------------------------------------

/**
 * Fetch and encode images for one item.  Returns an array of { dataUri } objects.
 * Swallows individual image fetch failures (logs warning, skips image).
 */
async function fetchItemImages(imageUrls, label) {
	const images = [];
	const urls = imageUrls.slice(0, MAX_IMAGES_PER_ITEM);
	for (let i = 0; i < urls.length; i++) {
		try {
			const img = await fetchImageAsBase64(urls[i], `${label}[${i}]`);
			images.push(img);
		} catch (e) {
			console.warn(`Skipping ${label}[${i}]: ${e.message}`);
		}
	}
	if (images.length === 0 && urls.length > 0) {
		throw new Error(`${label}: Could not fetch any of the provided images.`);
	}
	return images;
}

/**
 * Build the content array for a Gemini multi-image comparison request.
 * Interleaves text labels with images: "LOST ITEM image 1:", image, "FOUND ITEM image 1:", image, prompt.
 */
function buildGeminiContent(lostImages, foundImages, lost, found) {
	const promptText = `Compare these two items to determine if they are the SAME physical object.

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

	const content = [];
	for (let i = 0; i < lostImages.length; i++) {
		content.push({ type: 'text', text: i === 0 ? 'LOST ITEM image 1:' : `LOST ITEM image ${i + 1} (alternate angle):` });
		content.push({ type: 'image_url', image_url: { url: lostImages[i].dataUri } });
	}
	for (let i = 0; i < foundImages.length; i++) {
		content.push({ type: 'text', text: i === 0 ? 'FOUND ITEM image 1:' : `FOUND ITEM image ${i + 1} (alternate angle):` });
		content.push({ type: 'image_url', image_url: { url: foundImages[i].dataUri } });
	}
	content.push({ type: 'text', text: promptText });
	return content;
}

/**
 * Core Gemini pair comparison.
 * @param {object} lost — { title, description, category, location, dateTime, imageUrls }
 * @param {object} found — { title, description, category, location, dateTime, imageUrls }
 * @param {string} apiKey — OpenRouter API key
 * @returns {{ visualScore, titleScore, descriptionScore, categoryScore,
 *            locationScore, timeScore, confidence, reason, overallScore, isMatch }}
 * @throws on network errors or unparseable AI response
 */
async function geminiComparePair(lost, found, apiKey) {
	const lostImages = await fetchItemImages(lost.imageUrls, 'lostItem');
	const foundImages = await fetchItemImages(found.imageUrls, 'foundItem');

	const content = buildGeminiContent(lostImages, foundImages, lost, found);

	const response = await fetch(OPENROUTER_BASE, {
		method: 'POST',
		headers: {
			'Authorization': `Bearer ${apiKey}`,
			'Content-Type': 'application/json',
			'HTTP-Referer': 'http://localhost:8787',
		},
		body: JSON.stringify({
			model: GEMINI_MODEL,
			messages: [{ role: 'user', content }],
		}),
	});

	const result = await response.json();

	if (!response.ok) {
		const errInfo = result.error || result;
		throw new Error(`OpenRouter error ${response.status}: ${JSON.stringify(errInfo)}`);
	}

	const aiText = result.choices?.[0]?.message?.content || result.choices?.[0]?.text || '';
	if (!aiText) {
		throw new Error('Gemini returned an empty response.');
	}

	const scores = extractJson(aiText);
	if (!scores || typeof scores.visualScore === 'undefined') {
		throw new Error(`Gemini did not return parseable JSON. Raw: ${aiText.substring(0, 300)}`);
	}

	const visualScore      = clampScore(scores.visualScore);
	const titleScore       = clampScore(scores.titleScore);
	const descriptionScore = clampScore(scores.descriptionScore);
	const categoryScore    = clampScore(scores.categoryScore);
	const locationScore    = clampScore(scores.locationScore);
	const timeScore        = clampScore(scores.timeScore);
	const confidence       = clampScore(scores.confidence);
	const reason           = typeof scores.reason === 'string' ? scores.reason : '';

	const overallScore = Math.round(
		titleScore       * 0.10 +
		descriptionScore * 0.30 +
		categoryScore    * 0.15 +
		locationScore    * 0.10 +
		timeScore        * 0.10 +
		visualScore      * 0.25
	);

	return {
		visualScore, titleScore, descriptionScore, categoryScore,
		locationScore, timeScore, confidence, reason,
		overallScore, isMatch: overallScore >= 50,
		imagesProcessed: { lost: lostImages.length, found: foundImages.length, total: lostImages.length + foundImages.length },
	};
}

// ---------------------------------------------------------------------------
// POST /ai/gemini-match-test — single pair comparison (keep for testing)
// ---------------------------------------------------------------------------

async function handleGeminiMatchTest(request, env) {
	const apiKey = env.OPENROUTER_API_KEY;
	if (!apiKey) {
		return Response.json({ success: false, error: 'OPENROUTER_API_KEY is not set.' }, { status: 500 });
	}

	let body;
	try { body = await request.json(); } catch {
		return jsonError('Request body must be valid JSON.');
	}

	const lostErr = validateGeminiItem(body.lostItem, 'lostItem');
	if (lostErr) return jsonError(lostErr);
	const foundErr = validateGeminiItem(body.foundItem, 'foundItem');
	if (foundErr) return jsonError(foundErr);

	try {
		const result = await geminiComparePair(body.lostItem, body.foundItem, apiKey);
		return Response.json({ success: true, model: GEMINI_MODEL, provider: 'openrouter', match: result });
	} catch (e) {
		return Response.json({ success: false, error: e.message || String(e) }, { status: 502 });
	}
}

// ---------------------------------------------------------------------------
// POST /ai/batch-match — compare one anchor item against multiple candidates
// ---------------------------------------------------------------------------

/**
 * Deterministic candidate filter: returns true if the candidate is worth
 * sending to Gemini (same category AND location is compatible).
 */
function candidateFilter(anchor, candidate) {
	// Same category — exact match required.
	const anchorCat = (anchor.category || '').trim().toLowerCase();
	const candCat = (candidate.category || '').trim().toLowerCase();
	if (anchorCat !== candCat) return false;
	return true;
}

/**
 * Batch-match request body:
 * {
 *   anchorItem: { title, description, category, location, dateTime, imageUrls },
 *   candidateItems: [{ id, title, description, category, location, dateTime, imageUrls }, ...],
 *   maxCandidates?: number  // default 5
 * }
 */
async function handleBatchMatch(request, env) {
	const apiKey = env.OPENROUTER_API_KEY;
	if (!apiKey) {
		return Response.json({ success: false, error: 'OPENROUTER_API_KEY is not set.' }, { status: 500 });
	}

	let body;
	try { body = await request.json(); } catch {
		return jsonError('Request body must be valid JSON.');
	}

	const anchorErr = validateGeminiItem(body.anchorItem, 'anchorItem');
	if (anchorErr) return jsonError(anchorErr);

	if (!Array.isArray(body.candidateItems) || body.candidateItems.length === 0) {
		return jsonError('candidateItems must be a non-empty array.');
	}

	const anchor = body.anchorItem;
	const maxCandidates = Math.min(
		typeof body.maxCandidates === 'number' ? body.maxCandidates : 5,
		BATCH_MAX_CANDIDATES
	);

	// Validate all candidates.
	const candidates = [];
	for (let i = 0; i < body.candidateItems.length; i++) {
		const c = body.candidateItems[i];
		const err = validateGeminiItem(c, `candidateItems[${i}]`);
		if (err) return jsonError(err);
		if (typeof c.id !== 'string' || c.id.trim() === '') {
			return jsonError(`candidateItems[${i}].id is required.`);
		}
		candidates.push(c);
	}

	// Deterministic candidate filtering.
	const filtered = candidates.filter(c => candidateFilter(anchor, c));
	const selected = filtered.slice(0, maxCandidates);

	// Compare anchor against each candidate (sequentially to avoid rate limits).
	const results = [];
	for (const candidate of selected) {
		try {
			const match = await geminiComparePair(anchor, candidate, apiKey);
			results.push({ candidateId: candidate.id, ...match });
		} catch (e) {
			results.push({ candidateId: candidate.id, error: e.message || String(e) });
		}
	}

	// Sort by overallScore descending (errors at bottom).
	results.sort((a, b) => {
		if (a.error && !b.error) return 1;
		if (!a.error && b.error) return -1;
		return (b.overallScore || 0) - (a.overallScore || 0);
	});

	return Response.json({
		success: true,
		model: GEMINI_MODEL,
		provider: 'openrouter',
		anchorId: anchor.id || null,
		totalCandidates: candidates.length,
		filteredCount: filtered.length,
		comparedCount: selected.length,
		results,
	});
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

export default {
	async fetch(request, env) {
		const url = new URL(request.url);

			// POST /ai/match-test
			if (request.method === 'POST' && url.pathname === '/ai/match-test') {
				return handleMatchTest(request, env);
			}

			// POST /ai/vision-test — single-image sanity check
			if (request.method === 'POST' && url.pathname === '/ai/vision-test') {
				return handleVisionTest(request, env);
			}

			// POST /ai/multi-image-test — test multi-image on second account
			if (request.method === 'POST' && url.pathname === '/ai/multi-image-test') {
				return handleMultiImageTest(request, env);
			}

			// POST /ai/openrouter-multi-image-test — Gemini multi-image via OpenRouter
			if (request.method === 'POST' && url.pathname === '/ai/openrouter-multi-image-test') {
				return handleOpenRouterMultiImageTest(request, env);
			}

			// POST /ai/gemini-match-test — full Lost vs Found via Gemini 2.5 Flash
			if (request.method === 'POST' && url.pathname === '/ai/gemini-match-test') {
				return handleGeminiMatchTest(request, env);
			}

			// POST /ai/batch-match — compare anchor item against multiple candidates
			if (request.method === 'POST' && url.pathname === '/ai/batch-match') {
				return handleBatchMatch(request, env);
			}

		// GET routes
		if (request.method === 'GET') {
			if (url.pathname === '/ai/test') {
				return Response.json(await handleAiTest(env));
			}
			if (url.pathname === '/ai/new-account-test') {
				return Response.json(await handleNewAccountTest(env));
			}
			if (responses[url.pathname]) {
				return Response.json(responses[url.pathname]);
			}
		}

		return new Response('Not Found', { status: 404 });
	},
};
