// ---------------------------------------------------------------------------
// Batch-match request contract: validation, prompt construction, filtering
// ---------------------------------------------------------------------------
//
// These moved out of `src/index.js` because Cloudflare treats EVERY named
// export of the entry module as a Worker entrypoint, which must be a function
// or an ExportedHandler. A plain `export const BATCH_MAX_CANDIDATES = 10`
// therefore made workerd refuse to start the module at all:
//
//   Uncaught TypeError: Incorrect type for map entry
//   'BATCH_MAX_CANDIDATES': the provided value is not of type
//   'function or ExportedHandler'.
//
// The entry module now exposes only `export default`. The logic below is a
// verbatim move -- no behaviour change.

/**
 * Validate a single item object for the gemini-match-test endpoint.
 * Returns an error string or null.
 */
export function validateGeminiItem(obj, label) {
		if (!obj || typeof obj !== 'object') return `${label} must be a JSON object.`;
	for (const field of ['title', 'description', 'category']) {
		if (typeof obj[field] !== 'string' || obj[field].trim() === '') {
			return `${label}.${field} is required and must be a non-empty string.`;
		}
	}
	// location is OPTIONAL â€” inventory items don't carry a location.
	// Empty string is the honest "not observed" signal; null/absent also ok.
	// When provided (non-null, non-empty), it must be a valid non-empty string.
	if (obj.location != null &&
	    obj.location !== '' &&
	    (typeof obj.location !== 'string' || obj.location.trim() === '')) {
		return `${label}.location must be a non-empty string when provided.`;
	}
	// dateTime is OPTIONAL â€” the report forms don't ask for a date/time.
	// Empty string means "unknown"; null/absent also ok.
	// When provided (non-null, non-empty), it must be a valid non-empty string.
	if (obj.dateTime != null &&
	    obj.dateTime !== '' &&
	    (typeof obj.dateTime !== 'string' || obj.dateTime.trim() === '')) {
		return `${label}.dateTime must be a non-empty string when provided.`;
	}
		// imageUrls is optional â€” items without images fall back to text-only comparison.
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

/**
 * Hard cap on candidates evaluated per batch request. The Flutter client's
 * `_aiMaxCandidates` must not exceed this.
 */
export const BATCH_MAX_CANDIDATES = 10;

/**
 * Build the content array for a Gemini multi-image comparison request.
 * Interleaves text labels with images: "LOST ITEM image 1:", image, "FOUND ITEM image 1:", image, prompt.
 *
 * The model is asked for VISUAL analysis ONLY. Title, description, category,
 * location and time are scored deterministically in `src/scoring.js`, so the
 * prompt deliberately omits them — requesting numbers we discard would only
 * add variance and cost.
 */
export function buildGeminiContent(lostImages, foundImages, lost, found) {
	const promptText = `Compare the IMAGES of these two items to decide whether they show the SAME physical object.

LOST: "${lost.title}" | ${lost.category}
"${lost.description}"

FOUND: "${found.title}" | ${found.category}
"${found.description}"

The text above is context only. Judge ONLY what is VISIBLE in the images.

Look for: brand, logo, model name/number, visible text or labels, stickers,
engravings, scratches, cracks, dents, stains, wear patterns, keychains,
straps, accessories, colour and shape.

Return these fields:

- visualScore (0-100): visual similarity of the two objects.
    90+   = multiple IDENTIFYING details match (logo AND model, or a unique mark)
    60-89 = one clear identifying detail matches
    40-59 = same object type and colour but NO identifying detail
    0-19  = clearly different objects
  A shared colour or shape is NOT an identifying detail.

- matchingFeatures: array of SHORT phrases naming each specific visual detail
  that matches. Name the actual detail, e.g.
    "Nike swoosh logo on front pocket", "deep scratch near top-right corner",
    "same CU Malaysia sticker", "identical frayed left strap".
  Use [] when nothing specific matches. Never invent details you cannot see.

- conflictingFeatures: array of SHORT phrases naming each specific visual
  detail that CONTRADICTS a match, e.g.
    "different colour: lost is red, found is blue",
    "different brand label: Samsung vs Apple",
    "found item has a model label the lost item lacks".
  Use [] when nothing contradicts.

- confidence (0-100): how certain you are, given image quality and how much
  of each object is visible.

- reason: one short sentence.

CRITICAL: Two generic items (e.g. both plain "black backpack") must get
visualScore <= 50 unless you can actually SEE a matching logo, sticker, text,
or damage mark. Do not raise the score because the items are the same type.

Do NOT score title, description, category, location, or time. Those are
computed separately and any values you return for them are ignored.

Reply ONLY with this JSON and nothing else:
{"visualScore":0,"matchingFeatures":[],"conflictingFeatures":[],"confidence":0,"reason":""}`;

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
 * Deterministic candidate filter: returns true if the candidate is worth
 * sending to Gemini (same category).
 */
export function candidateFilter(anchor, candidate) {
	const anchorCat = (anchor.category || '').trim().toLowerCase();
	const candCat = (candidate.category || '').trim().toLowerCase();
	if (anchorCat !== candCat) return false;
	return true;
}

