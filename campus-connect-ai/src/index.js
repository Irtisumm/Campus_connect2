// ---------------------------------------------------------------------------
// Deterministic scoring — imported from the single source of truth.
// ---------------------------------------------------------------------------
// `src/scoring.js` holds every pure scoring function. The Worker and the test
// suites both import from it, so there is no hand-synced duplicate to drift.
import {
	computeImageSimilarity,
	computeTitleSimilarity,
	computeDescriptionSimilarity,
	computeCategoryScore,
	computeLocationScore,
	computeTimeScore,
	computeOverallScore,
	hasValue,
	parseDateTime,
	scorePair,
	MATCH_THRESHOLD,
} from './scoring.js';

// The batch-match request contract. These live in their own module because
// Cloudflare treats every NAMED export of the entry module as a Worker
// entrypoint, which must be a function or an ExportedHandler — a plain
// `export const BATCH_MAX_CANDIDATES = 10` here stops workerd from starting
// the Worker at all. This entry module therefore exposes `export default` only.
import {
	validateGeminiItem,
	buildGeminiContent,
	candidateFilter,
	BATCH_MAX_CANDIDATES,
} from './batch.js';

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

// ---------------------------------------------------------------------------
// TEMPORARY diagnostic logging (production 500 audit)
// ---------------------------------------------------------------------------
// Remove these two helpers and their call sites once the 500 is resolved.
//
// SAFETY CONTRACT — these must never receive or emit:
//   • API keys or any part of them (only Boolean presence + integer length)
//   • Authorization headers
//   • base64 image data or data: URIs
//   • request/response payload bodies
//   • any other secret
// Only counts, lengths, booleans, scores, stage names and error name/message.

/** Fields that must never be echoed, even if a caller passes them by mistake. */
const REDACT_KEYS = /key|token|secret|auth|password|bearer|credential|datauri|base64/i;

/** Strip anything sensitive or oversized from a detail object. */
function safeDetail(detail) {
	if (!detail || typeof detail !== 'object') return '';
	const parts = [];
	for (const [k, v] of Object.entries(detail)) {
		// Allow the explicit presence/length probes; block everything else
		// whose name looks sensitive.
		const isSafeProbe = k === 'hasOpenRouterKey' || k === 'keyLength';
		if (!isSafeProbe && REDACT_KEYS.test(k)) {
			parts.push(`${k}=<redacted>`);
			continue;
		}
		if (v === null || v === undefined) {
			parts.push(`${k}=null`);
		} else if (typeof v === 'number' || typeof v === 'boolean') {
			parts.push(`${k}=${v}`);
		} else {
			// Strings are truncated hard and stripped of any data: URI.
			const s = String(v).replace(/data:[^;]+;base64,[A-Za-z0-9+/=]*/g, '<base64>');
			parts.push(`${k}=${s.slice(0, 120)}`);
		}
	}
	return parts.length ? ' ' + parts.join(' ') : '';
}

/** `[AI WORKER DEBUG] <stage>` plus safe key=value detail. */
function debugStage(stage, detail) {
	console.log(`[AI WORKER DEBUG] ${stage}${safeDetail(detail)}`);
}

/** `[AI WORKER ERROR] stage= / name= / message=` on three lines. */
function debugError(stage, error, detail) {
	const name = error && error.name ? error.name : 'Error';
	const rawMessage = error && error.message ? error.message : String(error);
	// Defensive: never let a key or base64 blob ride along in a message.
	const message = String(rawMessage)
		.replace(/data:[^;]+;base64,[A-Za-z0-9+/=]*/g, '<base64>')
		.replace(/sk-[A-Za-z0-9-_]+/g, '<redacted-key>')
		.replace(/Bearer\s+\S+/gi, 'Bearer <redacted>')
		.slice(0, 400);
	console.error(`[AI WORKER ERROR] stage=${stage}${safeDetail(detail)}`);
	console.error(`[AI WORKER ERROR] name=${name}`);
	console.error(`[AI WORKER ERROR] message=${message}`);
}

/** Extract a JSON object from an AI text response that may be wrapped in
 *  markdown fences or have extra text before/after.  Also handles the case
 *  where the AI binding already returns a parsed object. */
function extractJson(text) {
	// If the AI already returned a parsed object, use it.
	if (text && typeof text === 'object' && !Array.isArray(text)) {
		// Recognise the visual-only scoring output (visualScore), the legacy
		// scoring output (titleScore) and vision attributes (objectType).
		if ('visualScore' in text || 'titleScore' in text || 'objectType' in text) {
			return text;
		}
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
		// Availability is decided from the DATA; unavailable factors are
		// dropped from the weighting rather than scored 0 (see scoring.js).
		const locationAvailable = hasValue(lost.location) && hasValue(found.location);
		const timeAvailable = parseDateTime(lost.dateTime) !== null
			&& parseDateTime(found.dateTime) !== null;

		const locationScore    = locationAvailable
			? computeLocationScore(lost.location, found.location) : null;
		const timeScore        = timeAvailable
			? computeTimeScore(lost.dateTime, found.dateTime) : null;

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
		if (!locationAvailable) reasonParts.push('location not recorded (not scored)');
		else if (locationScore >= 80) reasonParts.push('location matches');
		else if (locationScore > 0) reasonParts.push('partial location match');
		else reasonParts.push('locations differ');
		if (!timeAvailable) reasonParts.push('time not recorded (not scored)');
		else if (timeScore >= 85) reasonParts.push('times are close');
		else if (timeScore >= 60) reasonParts.push('times are within a day or two');
		else reasonParts.push('times are far apart');
		const reason = reasonParts.join('; ') + '.';

		// Single shared formula, with renormalisation for missing factors.
		const combined = computeOverallScore({
			titleScore,
			descriptionScore,
			categoryScore,
			visualScore: imageScore,
			locationScore: locationScore ?? 0,
			timeScore: timeScore ?? 0,
			locationAvailable,
			timeAvailable,
		});
		const overallScore = combined.overallScore;
		const isMatch = overallScore >= MATCH_THRESHOLD;

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
				locationAvailable,
				timeAvailable,
				activeFactors: combined.activeFactors,
				activeWeightTotal: combined.activeWeightTotal,
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


const GEMINI_MODEL = 'google/gemini-2.5-flash';
const MAX_IMAGES_PER_ITEM = 3;

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
 * Core lost-vs-found pair comparison.
 *
 * Gemini supplies the VISUAL assessment only (visualScore, structured
 * evidence, confidence, reason). Every other factor — title, description,
 * category, location, time — plus weight renormalisation, the generic-item
 * visual cap, the conflict penalty and the final overall score are computed
 * deterministically by `scorePair` in `src/scoring.js`.
 *
 * The request is sent with `temperature: 0` and `top_p: 1` so the visual
 * assessment is as reproducible as the model allows.
 *
 * @param {object} lost   { title, description, category, location, dateTime, imageUrls }
 * @param {object} found  { title, description, category, location, dateTime, imageUrls }
 * @param {string} apiKey OpenRouter API key
 * @returns {object} scorePair() result plus imagesProcessed
 * @throws on network errors or an unparseable AI response
 */
async function geminiComparePair(lost, found, apiKey) {
	// TEMPORARY diagnostic stage markers — counts only, never image bytes.
	debugStage('image-extraction-start', {
		lostUrlCount: Array.isArray(lost.imageUrls) ? lost.imageUrls.length : 0,
		foundUrlCount: Array.isArray(found.imageUrls) ? found.imageUrls.length : 0,
	});
	const lostImages = await fetchItemImages(lost.imageUrls, 'lostItem');
	const foundImages = await fetchItemImages(found.imageUrls, 'foundItem');
	debugStage('image-extraction-done', {
		lostImages: lostImages.length,
		foundImages: foundImages.length,
	});

	const content = buildGeminiContent(lostImages, foundImages, lost, found);

	debugStage('gemini-request-start', {
		model: GEMINI_MODEL,
		contentParts: content.length,
		temperature: 0,
		topP: 1,
	});

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
			// Reproducibility: greedy decoding, no sampling randomness.
			// temperature 0 and top_p 1 are both supported by the OpenRouter
			// chat-completions API for this model.
			temperature: 0,
			top_p: 1,
		}),
	});

	const result = await response.json();

	debugStage('gemini-response-received', {
		httpStatus: response.status,
		ok: response.ok,
		hasChoices: Array.isArray(result && result.choices),
	});

	if (!response.ok) {
		const errInfo = result.error || result;
		// The provider's error object can echo request context, so log only its
		// message/code — never the whole object.
		debugError('gemini-response-received', new Error(
			`OpenRouter HTTP ${response.status}: ` +
			`${(errInfo && (errInfo.message || errInfo.code)) || 'unknown provider error'}`));
		throw new Error(`OpenRouter error ${response.status}: ${JSON.stringify(errInfo)}`);
	}

	const aiText = result.choices?.[0]?.message?.content || result.choices?.[0]?.text || '';
	if (!aiText) {
		debugError('gemini-response-received',
			new Error('Gemini returned an empty response.'));
		throw new Error('Gemini returned an empty response.');
	}

	const visual = extractJson(aiText);
	debugStage('json-parsed', {
		parsed: Boolean(visual),
		hasVisualScore: Boolean(visual && typeof visual.visualScore !== 'undefined'),
		matchingFeatureCount: visual && Array.isArray(visual.matchingFeatures)
			? visual.matchingFeatures.length : 0,
		conflictingFeatureCount: visual && Array.isArray(visual.conflictingFeatures)
			? visual.conflictingFeatures.length : 0,
	});
	if (!visual || typeof visual.visualScore === 'undefined') {
		debugError('json-parsed', new Error(
			'Gemini did not return parseable JSON with a visualScore field.'));
		throw new Error(`Gemini did not return parseable JSON. Raw: ${aiText.substring(0, 300)}`);
	}

	debugStage('scoring-start');

	// Deterministic scoring. Only the visual fields are taken from the model.
	const scored = scorePair(lost, found, {
		visualScore: visual.visualScore,
		confidence: visual.confidence,
		reason: visual.reason,
		evidence: {
			matchingFeatures: visual.matchingFeatures,
			conflictingFeatures: visual.conflictingFeatures,
		},
	});

	debugStage('scoring-success', {
		overallScore: scored.overallScore,
		visualScore: scored.visualScore,
		rawVisualScore: scored.rawVisualScore,
		visualCapped: scored.visualCapped,
		conflictPenalty: scored.conflictPenalty,
		activeWeightTotal: scored.activeWeightTotal,
		isMatch: scored.isMatch,
	});

	return {
		...scored,
		imagesProcessed: {
			lost: lostImages.length,
			found: foundImages.length,
			total: lostImages.length + foundImages.length,
		},
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
 * Batch-match request body:
 * {
 *   anchorItem: { title, description, category, location, dateTime, imageUrls },
 *   candidateItems: [{ id, title, description, category, location, dateTime, imageUrls }, ...],
 *   maxCandidates?: number  // default BATCH_MAX_CANDIDATES (10), hard cap 10
 * }
 *
 * `comparedCount` in the response reports exactly how many candidates were
 * evaluated, and `droppedCount` how many passed the filter but exceeded
 * `maxCandidates` — so a silent reduction can never go unnoticed again.
 */
async function handleBatchMatch(request, env) {
	// ── TEMPORARY DIAGNOSTIC LOGGING ───────────────────────────────────────
	// Stage markers for the production 500 audit. Never logs keys, headers,
	// base64 image bytes, or full request payloads — only counts, lengths,
	// booleans and error names/messages.
	let stage = 'batch-start';
	debugStage('batch-start');

	try {
		const apiKey = env.OPENROUTER_API_KEY;
		// Presence only — the value is never logged.
		debugStage('config-checked', {
			hasOpenRouterKey: Boolean(apiKey),
			keyLength: apiKey ? String(apiKey).length : 0,
		});
		if (!apiKey) {
			debugError('config-checked', new Error(
				'OPENROUTER_API_KEY is not set in the Worker environment. ' +
				'Set it with: wrangler secret put OPENROUTER_API_KEY'));
			return Response.json({
				success: false,
				error: 'OPENROUTER_API_KEY is not set.',
				stage: 'config-checked',
				hint: 'Run: wrangler secret put OPENROUTER_API_KEY',
			}, { status: 500 });
		}

		stage = 'request-parsed';
		let body;
		try {
			body = await request.json();
		} catch (e) {
			debugError('request-parsed', e);
			return jsonError('Request body must be valid JSON.');
		}
		// Guard against a JSON literal `null`/scalar body, which would make
		// every `body.x` deref below throw a TypeError → unhandled 500.
		if (!body || typeof body !== 'object' || Array.isArray(body)) {
			debugError('request-parsed',
				new Error('Request body must be a JSON object.'));
			return jsonError('Request body must be a JSON object.');
		}
		debugStage('request-parsed', {
			hasAnchorItem: Boolean(body.anchorItem),
			candidateCount: Array.isArray(body.candidateItems)
				? body.candidateItems.length : 0,
			maxCandidatesRequested: typeof body.maxCandidates === 'number'
				? body.maxCandidates : null,
		});

		stage = 'candidates-validated';
		const anchorErr = validateGeminiItem(body.anchorItem, 'anchorItem');
		if (anchorErr) {
			debugError('candidates-validated', new Error(anchorErr));
			return jsonError(anchorErr);
		}

		if (!Array.isArray(body.candidateItems) || body.candidateItems.length === 0) {
			debugError('candidates-validated',
				new Error('candidateItems must be a non-empty array.'));
			return jsonError('candidateItems must be a non-empty array.');
		}

		const anchor = body.anchorItem;
		// Default to the full batch capacity. Previously this defaulted to 5 while
		// the client fetched 10 candidates, so half were silently dropped.
		const requested = typeof body.maxCandidates === 'number'
			? body.maxCandidates
			: BATCH_MAX_CANDIDATES;
		const maxCandidates = Math.max(1, Math.min(requested, BATCH_MAX_CANDIDATES));

		// Validate all candidates.
		const candidates = [];
		for (let i = 0; i < body.candidateItems.length; i++) {
			const c = body.candidateItems[i];
			const err = validateGeminiItem(c, `candidateItems[${i}]`);
			if (err) {
				debugError('candidates-validated', new Error(err));
				return jsonError(err);
			}
			if (typeof c.id !== 'string' || c.id.trim() === '') {
				debugError('candidates-validated',
					new Error(`candidateItems[${i}].id is required.`));
				return jsonError(`candidateItems[${i}].id is required.`);
			}
			candidates.push(c);
		}

		// Deterministic candidate filtering.
		const filtered = candidates.filter(c => candidateFilter(anchor, c));
		const selected = filtered.slice(0, maxCandidates);
		debugStage('candidates-validated', {
			total: candidates.length,
			filtered: filtered.length,
			selected: selected.length,
			maxCandidates,
		});

		// Compare anchor against each candidate (sequentially to avoid rate limits).
		const results = [];
		for (const candidate of selected) {
			try {
				const match = await geminiComparePair(anchor, candidate, apiKey);
				results.push({ candidateId: candidate.id, ...match });
			} catch (e) {
				// Per-candidate failures are contained here: the batch still
				// returns HTTP 200 with an `error` on that candidate only.
				debugError('candidate-compare', e, { candidateId: candidate.id });
				results.push({ candidateId: candidate.id, error: e.message || String(e) });
			}
		}

		stage = 'response-serialized';
		// Sort by overallScore descending (errors at bottom).
		results.sort((a, b) => {
			if (a.error && !b.error) return 1;
			if (!a.error && b.error) return -1;
			return (b.overallScore || 0) - (a.overallScore || 0);
		});

		const okCount = results.filter(r => !r.error).length;
		debugStage('batch-success', {
			compared: selected.length,
			scored: okCount,
			failed: results.length - okCount,
			topScore: results.length && !results[0].error
				? results[0].overallScore : null,
		});

		return Response.json({
			success: true,
			model: GEMINI_MODEL,
			provider: 'openrouter',
			anchorId: anchor.id || null,
			totalCandidates: candidates.length,
			filteredCount: filtered.length,
			comparedCount: selected.length,
			// Non-zero means eligible candidates were NOT evaluated.
			droppedCount: filtered.length - selected.length,
			maxCandidates,
			threshold: MATCH_THRESHOLD,
			results,
		});
	} catch (e) {
		// Catch-all so an unexpected exception surfaces the failing stage in the
		// response instead of an opaque Cloudflare 500 with no diagnostics.
		debugError(stage, e);
		return Response.json({
			success: false,
			error: e && e.message ? e.message : String(e),
			errorName: e && e.name ? e.name : 'Error',
			stage,
		}, { status: 500 });
	}
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

export default {
	async fetch(request, env) {
		try {
			return await route(request, env);
		} catch (e) {
			// TEMPORARY: without this, any uncaught throw becomes an opaque
			// Cloudflare 500 with no body, which is what made this hard to
			// diagnose from the Flutter side.
			debugError('router', e);
			return Response.json({
				success: false,
				error: e && e.message ? e.message : String(e),
				errorName: e && e.name ? e.name : 'Error',
				stage: 'router',
			}, { status: 500 });
		}
	},
};

async function route(request, env) {
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
}
