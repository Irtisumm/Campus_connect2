# Create Event Screen — Design Specification (Redesign)

- **Owner:** Agent 2 (Visual-system and Component Architect)
- **Date:** 2026-08-14
- **Source of truth (visual):** `D:\Aa . MAY - Semister All Subject\Project-2\Photos of work\Event detils.png`
- **Token file (source of truth for values):** `D:\Campus_connect2\lib\theme\create_event_tokens.dart` — the spec below mirrors it 1:1; where they ever disagree, the Dart token file wins (it is the artifact that compiles).
- **Target screen:** `CreateEventScreen`, route `/events/create` (registered in `D:\Campus_connect2\lib\main.dart:127`).
- **Read-only on:** `lib/screens/events/events_screens.dart`, `lib/main.dart`, `lib/models/event.dart`, `lib/services/*`, `lib/theme/app_theme.dart`, `lib/theme/luxe.dart`, `lib/widgets/common.dart`. Agent 4 implements; this spec only defines.

---

## 1. Component tree

The screen is a **pinned header + scrolling sheet** composition. Header stays fixed; the white sheet scrolls beneath it (overlapping the header's lower edge by 28 px). Single `SingleChildScrollView` — no nested scroll views anywhere.

```
CreateEventScreen (StatefulWidget, _CreateEventScreenState)        lib/screens/events/create_event_screen.dart
│  Owns ALL form state: controllers, FocusNodes, validators, pickers, submit/cancel logic.
│  Visual widgets below are presentational; they receive value/state via constructor params.
└─ Scaffold (backgroundColor = scaffoldColor, resizeToAvoidBottomInset: true)
   └─ Column
      ├─ CreateEventHeader                          (presentational)  create_event_widgets.dart
      │  ├─ Stack: headerGradient container (height = topInset + headerContentHeight)
      │  │  ├─ _HeaderBubbles  (custom painter, translucent circles, clipped)
      │  │  ├─ Back button: 48×48 circular, backButtonColor, Icons.arrow_back_rounded
      │  │  └─ Title column: "Create Event" (headerTitle) + "Fill in the details
      │  │     to create your event." (headerSubtitle)
      │  └─ onBack callback → existing back behavior (context.pop())
      │
      └─ Expanded
         └─ Transform.translate(offset: Offset(0, -sheetOverlap))   // sheet overlaps header
            └─ SingleChildScrollView
               │  padding: EdgeInsets.fromLTRB(contentPaddingHorizontal, sheetTopRadius,
               │                    contentPaddingHorizontal, scrollBottomPadding + viewInsets.bottom)
               │  keyboardDismissBehavior: onDrag
               └─ CreateEventSheet (Container: white, top radii 30, centered inner
                  column max-width contentMaxWidth)
                  └─ Column (crossAxisAlignment: start)
                     ├─ EventInfoCard.approval         "Admin approval required"
                     ├─ EventInfoCard.deadline         "Submission deadline"
                     ├─ CreateEventSectionHeader       "EVENT DETAILS"
                     ├─ CreateEventFieldCard.title        (Event Title + 0/100 counter)
                     ├─ CreateEventFieldCard.dropdown     (Category)
                     ├─ CreateEventFieldCard.dropdown     (Event Type)
                     ├─ CreateEventFieldCard.numeric      (Max Participants)
                     ├─ CreateEventFieldCard.picker       (Date)
                     ├─ CreateEventFieldCard.picker       (Time)
                     ├─ CreateEventFieldCard.text         (Location)
                     ├─ CreateEventFieldCard.text         (Organizer)
                     ├─ CreateEventFieldCard.multiline    (Description)
                     ├─ CreateEventSectionHeader       "APPROVAL LETTER (PDF)"
                     ├─ PdfUploadCard                 (dashed pink border + DashedRRectPainter)
                     ├─ PdfSecurityNote               (lock icon + "Your document will be secure…")
                     ├─ CreateEventSubmitButton       "Submit for Approval" (full width, 56 px)
                     ├─ CreateEventCancelButton       "Cancel" (outlined, 56 px)
                     └─ bottom safe-area padding (SafeArea or padding.bottom)
```

Widget-name table (all presentational widgets live in `lib/screens/events/widgets/create_event_widgets.dart`, all `StatelessWidget`, `const` constructors where possible):

| Widget | Purpose | State via params |
|---|---|---|
| `CreateEventHeader` | Gradient header, bubbles, back, title, subtitle | `onBack`, `topInset` |
| `CreateEventSheet` | White surface w/ 30 px top radii + width-clamped content | `child` |
| `EventInfoCard` | Pale pink / pale cream info card (two variants via `variant`) | `variant`, static text (no callbacks — informational only) |
| `CreateEventSectionHeader` | Uppercase gray label + thin rule to the right | `label` |
| `CreateEventFieldCard` | Base field card: 48×48 pale-pink icon tile, label, helper, input slot, error slot, focus/error visuals | `icon`, `label`, `helper`, `trailing`, `focused`, `errorText`, `child`, `minHeight`, `onTap` (picker variant) |
| `CreateEventCounter` | Live `n/100` title counter at far right of the label row | `count`, `max` |
| `CreateEventTextField` | Borderless `TextFormField` embedded in a `CreateEventFieldCard` (text / numeric / multiline variants) | `controller`, `validator`, `inputFormatters`, `keyboardType`, `maxLines` |
| `CreateEventDropdownField` | Dropdown embedded in a `CreateEventFieldCard`, trailing `expand_more` chevron | `value`, `items`, `onChanged`, `validator` |
| `CreateEventPickerField` | Read-only display field; whole card tappable, trailing icon | `valueText`, `placeholder`, `trailingIcon`, `onTap`, `errorText` |
| `PdfUploadCard` | Pink-tinted dashed-border upload card + "Choose PDF" outlined button; replace/remove selected file | `fileName` (null = none), `onChoose`, `onRemove`, `errorText`, `compact` (narrow layout) |
| `PdfSecurityNote` | Lock icon + "Your document will be secure and confidential" | — |
| `CreateEventSubmitButton` | 56 px gradient button, send icon, loading state | `submitting`, `onPressed` |
| `CreateEventCancelButton` | 56 px white outlined button, raspberry border/label | `onPressed` |
| `_DashedRRectPainter` | Private `CustomPainter` for the dashed PDF border (uses dash tokens) | — |

**Header composition detail (in `CreateEventHeader`):**
- Container height = `topInset + CreateEventTokens.headerContentHeight` where `topInset = MediaQuery.paddingOf(context).top` (≈176 px total on a 44 px inset device — satisfies the 175–185 px requirement **including** the safe-area inset).
- Gradient: `headerGradient` (#AF0845 top-left → #EE2F6F bottom-right).
- Bubble decorations: `CustomPaint` with 3 concentric translucent circles at top-right (radii ~46/72/98, stroke, `bubbleRing`) plus 2 filled circles (bottom-left ~38, mid-right ~12, `bubbleFill`/`bubbleFillFaint`). Wrap in `ClipRect` so circles never escape the header. `IgnorePointer` on the decoration.
- Back button: 48×48 circular (`backButtonRadius`), `backButtonColor` fill, 1 px `backButtonBorderColor` border, white `Icons.arrow_back_rounded`, `Semantics(button: true, label: 'Back')`. `onPressed` = existing back behavior — **plain `context.pop()`**; do NOT add content-discard logic here (the cancel button owns discard confirmation; see §3). Positioning: `Positioned(left: 16, top: topInset + 8)`.
- Title block: left-aligned at 16 px, `headerTitle` 22 px w800 white, then 6 px gap, `headerSubtitle` 13 px w500 90 % white. Anchored to the bottom of the header with 16 px bottom padding so the text sits in the gradient's lower (vivid pink) region, exactly like the reference.

**Info cards detail (in `EventInfoCard`):**
- Pink variant (`EventInfoVariant.approval`): bg `infoPinkCardColor` (#FBEAF2), tile `infoPinkTileColor` (#F8DCE8) 48×48 radius 14, icon `Icons.verified_user_outlined` 24 px `infoPinkHeadingColor`, heading "Admin approval required" in `infoPinkHeadingColor` (#AF0845) w700 14 px, body "Your event will be reviewed and approved by admin before publishing." in `infoCardBody` (#4A4450) 12 px, trailing `Icons.chevron_right_rounded` 20 px `infoPinkChevronColor`.
- Cream variant (`EventInfoVariant.deadline`): bg `infoCreamCardColor` (#FBF3E2), tile `infoCreamTileColor` (#F7E8C8), icon `Icons.calendar_month_outlined` 24 px `infoCreamHeadingColor`, heading "Submission deadline" in `infoCreamHeadingColor` (#8A5F0A) w700 14 px, body "Events must be submitted at least 10 days before the event date to allow admin review." in `infoCardBody`, trailing `Icons.chevron_right_rounded` 20 px `infoCreamChevronColor`.
- Both: radius `cardRadius` (16), `infoCardPadding`, `infoCardMinHeight` 84, no border, no shadow, **no `onTap`** (informational only — no dead navigation). Chevrons are `ExcludeSemantics` (decorative affordance).

**Section headers detail (in `CreateEventSectionHeader`):**
- Label uppercase via `label.toUpperCase()`, `sectionLabel` style (11 px w700 letterSpacing 1.2, `sectionLabelColor` #6E6778), then 10 px gap, then `Expanded(Container(height: 1, color: sectionRuleColor))` — the thin light-gray rule.
- Rhythm: `sectionGapTop` 24 above the header, `sectionGapBottom` 10 below it, before first content. This replaces the old `SectionLabel` widget for this screen only (the shared `SectionLabel` in `lib/widgets/common.dart` stays untouched).

---

## 2. Design tokens

All values below are exported from `lib/theme/create_event_tokens.dart` (`abstract final class CreateEventTokens`). Format: `tokenName = value (usage)`.

### Colors

| Token | Value | Usage |
|---|---|---|
| `headerGradientStart` | `#AF0845` | dark raspberry, gradient start (top-left) |
| `headerGradientEnd` | `#EE2F6F` | vivid pink, gradient end (bottom-right) |
| `headerGradient` | LinearGradient topLeft→bottomRight of the two above | header background AND submit button |
| `headerTitleColor` | `#FFFFFF` | "Create Event" |
| `headerSubtitleColor` | `#E6FFFFFF` (90 % white) | subtitle on header |
| `bubbleRing` / `bubbleFill` / `bubbleFillFaint` | `#1FFFFFFF` / `#14FFFFFF` / `#0DFFFFFF` | translucent bubble decorations (12/8/5 % white) |
| `backButtonColor` / `backButtonBorderColor` | `#2EFFFFFF` / `#40FFFFFF` | 48×48 back button fill/border (18/25 % white) |
| `surfaceColor` / `scaffoldColor` | `#FFFFFF` | sheet + scaffold background |
| `infoPinkCardColor` / `infoPinkTileColor` | `#FBEAF2` / `#F8DCE8` | approval info card / its tile |
| `infoPinkHeadingColor` | `#AF0845` | "Admin approval required" + chevron |
| `infoCreamCardColor` / `infoCreamTileColor` | `#FBF3E2` / `#F7E8C8` | deadline info card / its tile |
| `infoCreamHeadingColor` / `infoCreamChevronColor` | `#8A5F0A` / `#9A6A0F` | "Submission deadline" / its chevron |
| `infoCardTextColor` | `#4A4450` | info card body text |
| `sectionLabelColor` / `sectionRuleColor` | `#6E6778` / `#E9E5EE` | section label / thin rule |
| `fieldCardColor` | `#FFFFFF` | field card fill |
| `fieldCardBorderColor` | `#EDEAF2` | idle border (very subtle cool gray) |
| `fieldCardFocusBorderColor` | `#C2185B` | focused border + focused label |
| `fieldCardErrorBorderColor` | `#C2185B` | error border + error tile icon |
| `fieldLabelColor` | `#1B1523` | near-black semibold label |
| `fieldHelperColor` | `#7A7386` | helper/placeholder line (4.54:1 on white) |
| `fieldValueColor` | `#1B1523` | entered/chosen values |
| `fieldCounterColor` | `#6E6778` | 0/100 counter (5.4:1) |
| `fieldErrorTextColor` | `#9C0F4B` | error text (8.1:1) |
| `tileColor` / `tileIconColor` | `#FBE9F1` / `#B01255` | pale-pink 48×48 field icon tile / its icon |
| `tileIconErrorColor` | `#C2185B` | tile icon while errored |
| `uploadCardColor` / `uploadCardDashedBorderColor` | `#FDF2F7` / `#E5A8C3` | PDF card fill / dashed border |
| `uploadTileColor` / `uploadTileIconColor` | `#F8DCE8` / `#B01255` | PDF icon tile / icon |
| `uploadFileNameColor` | `#1B1523` | bold selected-file name |
| `uploadHintColor` | `#7A7386` | "Upload an official approval letter (PDF)" |
| `uploadErrorTextColor` | `#9C0F4B` | "Approval letter is required" |
| `choosePdfLabelColor` / `choosePdfIconColor` | `#B01255` | "Choose PDF" label + upload icon |
| `choosePdfBorderColor` | `#4DB01255` | Choose PDF outline (30 % raspberry) |
| `lockIconColor` / `lockCaptionColor` | `#6E6778` | lock icon + privacy caption |
| `submitDisabledGradient` | `#D68FA8` → `#E7B3C6` | submit button while submitting |
| `submitLabelColor` | `#FFFFFF` | "Submit for Approval" |
| `cancelLabelColor` / `cancelBorderColor` | `#B01255` / `#4DB01255` | Cancel button label / outline |
| `submitButtonShadow` | `#4DAF0845` @ 30 %, blur 16, dy 6 | submit elevation |
| `fieldCardShadow` | `#0D2A1B3D` @ 5 %, blur 12, dy 4 | field card elevation |

### Spacing scale (`spaceXs…spaceHuge` = 4 / 8 / 12 / 16 / 20 / 24 / 32)

| Token | Value | Usage |
|---|---|---|
| `contentPaddingHorizontal` | 20 | sheet horizontal padding |
| `sectionGapTop` / `sectionGapBottom` | 24 / 10 | rhythm before a section / before its contents |
| `fieldGap` | 12 | between consecutive field cards |
| `infoCardGap` | 12 | between the two info cards |
| `scrollBottomPadding` | 32 | base bottom padding (keyboard inset added at runtime) |
| `fieldCardPadding` | LTRB(16,14,16,14) | field card inner padding |
| `infoCardPadding` / `uploadCardPadding` | LTRB(14,14,14,14) / all(16) | card inner paddings |
| `sheetOverlap` | 28 | sheet overlap over the header's lower edge |

### Radii & sizes

| Token | Value | Requirement |
|---|---|---|
| `sheetTopRadius` | 30 | sheet top corners 28–32 |
| `cardRadius` | 16 | info + field cards |
| `tileRadius` | 14 | 48×48 icon tiles (matches project's Luxe.rSmall) |
| `backButtonRadius` | 24 | circular 48×48 back button |
| `buttonRadius` | 14 | submit + cancel buttons |
| `choosePdfButtonRadius` | 12 | Choose PDF outlined button |
| `counterChipRadius` | 999 | pill shapes |
| `headerContentHeight` / `headerMinTotalHeight` | 132 / 176 | header sizing (see §1) |
| `fieldCardMinHeight` | 76 | field cards 70–78 (min-height, grows with text scale) |
| `descriptionCardMinHeight` | 160 | description card 150–170 |
| `infoCardMinHeight` | 84 | info cards |
| `primaryButtonHeight` / `secondaryButtonHeight` | 56 / 56 | actions |
| `choosePdfButtonHeight` | 44 | upload action (≥44 touch target) |
| `backButtonSize` / `iconTileSize` | 48 / 48 | |
| `iconTileIconSize` / `trailingIconSize` / `chevronSize` | 22 / 20 / 20 | icons |
| `contentMaxWidth` | 560 | tablet content clamp |
| `narrowBreakpoint` | 360 | PDF card layout switch (see §5) |

### Border widths

| Token | Value |
|---|---|
| `borderWidthIdle` | 1.0 |
| `borderWidthFocused` / `borderWidthError` | 1.6 / 1.6 |
| `borderWidthBackButton` | 1.0 |
| `borderWidthCancelButton` | 1.5 |
| `dashedBorderWidth` / `dashedBorderDashWidth` / `dashedBorderDashGap` | 1.4 / 6 / 5 |

### Type scale (all `Inter` — the app font)

| Token | Size / weight / color / notes |
|---|---|
| `headerTitle` | 22 / w800 / #FFFFFF / ls −0.5 |
| `headerSubtitle` | 13 / w500 / #E6FFFFFF |
| `infoCardHeading` | 14 / w700 / per-variant heading color |
| `infoCardBody` | 12 / w500 / #4A4450 / lh 1.45 |
| `sectionLabel` | 11 / w700 / #6E6778 / ls 1.2 |
| `fieldLabel` (+ `fieldLabelFocused`) | 15 / w600 / #1B1523 (→#C2185B focused) |
| `fieldHelper` | 12 / w400 / #7A7386 |
| `fieldValue` | 14 / w500 / #1B1523 |
| `fieldError` | 12 / w600 / #9C0F4B |
| `fieldCounter` | 12 / w600 / #6E6778 |
| `uploadFileName` | 14 / w700 / #1B1523 |
| `uploadHint` | 12 / w400 / #7A7386 |
| `lockCaption` | 11 / w500 / #6E6778 |
| `primaryButtonLabel` / `secondaryButtonLabel` | 15 / w700 / #FFFFFF / #B01255 |
| `choosePdfLabel` | 13 / w700 / #B01255 |

---

## 3. Field-state specification

### 3.1 Universal card states (all fields share these visuals)

| State | Border | Tile icon | Label | Notes |
|---|---|---|---|---|
| **Idle** | `fieldCardBorderColor`, 1.0 | `tileIconColor` | `fieldLabelColor` | helper/placeholder in `fieldHelper` |
| **Focused** | `fieldCardFocusBorderColor`, 1.6 | `tileIconColor` | `fieldLabelFocused` (raspberry) | label color change = non-color cue; card gains no shadow change |
| **Error** | `fieldCardErrorBorderColor`, 1.6 | `tileIconErrorColor` | `fieldLabelColor` (unchanged) | **error text always renders** below the input slot (inside the card, `fieldError` style) — never color-only |
| **Disabled** (only while submitting) | `fieldCardBorderColor` at reduced opacity (0.6) | tile icon at 0.5 opacity | `fieldLabelColor` at 0.5 opacity | whole form wrapped in `AbsorbPointer` while `_submitting` |

**Validation trigger rules (global):**
- `Form` starts with `AutovalidateMode.disabled` — **no errors before interaction**.
- After the first failed submit attempt, flip to `AutovalidateMode.onUserInteraction` (errors appear per-field as the user edits, and clear on valid input).
- The Date field is additionally **revalidated at submit** (a picker choice can't go stale in the UI, but the submit check is the source of truth for the 10-day rule).
- On failed submit: scroll the first invalid field into view (`Scrollable.ensureVisible` via its `GlobalKey`), then focus it where applicable.
- Error text location: inside the card, directly below the input slot (2 px below the border area, `fieldError` style). For the upload card, below the card. For picker fields (Date/Time), below the card content.

### 3.2 Per-field specification

| # | Field | Widget / input | Icon tile | Helper / placeholder | Validation & triggers | Error copy |
|---|---|---|---|---|---|---|
| 1 | **Title** | `CreateEventTextField`, `TextInputAction.next`, `maxLength: 100`, default counter suppressed (`counterText: ''`), custom `CreateEventCounter` at far right of the label row (live 0/100 via controller listener) | `Icons.title_rounded` | "Enter a catchy title for your event" | required, non-empty after trim; **live 100-char cap** (input formatter + maxLength) | "Event title is required" (counter also turns `fieldErrorTextColor` when count == 100 is irrelevant — keep it muted; do not error on length, the cap prevents overflow) |
| 2 | **Category** | `CreateEventDropdownField`, items `['Academic','Sport','Club','General']` (existing `_cats`), trailing `Icons.expand_more_rounded` | `Icons.category_outlined` | "Select a category" | required; error on submit attempt / after interaction | "Select a category" |
| 3 | **Event type** | `CreateEventDropdownField`, items `['Open','Club','Club+Payment','Paid']` (existing `_eventTypes`), trailing `Icons.expand_more_rounded` | `Icons.groups_outlined` | "Select event type" | required | "Select an event type" |
| 4 | **Max Participants** | `CreateEventTextField` numeric: `keyboardType: number`, `FilteringTextInputFormatter.digitsOnly` (kills negatives/decimals/unsafe text) | `Icons.people_outline_rounded` | "Enter maximum number of participants" / input hint "0 = unlimited" | optional; empty or unparsable → **0 (unlimited)** at submit (existing model semantics, see §8) | "Enter a valid number" (only if text present and `int.tryParse` fails — practically unreachable with digitsOnly, kept as defense) |
| 5 | **Date** | `CreateEventPickerField` — whole card tappable (`InkWell` + `Semantics(button)`), trailing `Icons.calendar_month_rounded` | `Icons.calendar_today_outlined` | "Pick the event date" | required; `showDatePicker(firstDate: today + 10 days, lastDate: today + 365 days)` (existing rule) — enforced **at pick AND revalidated at submit** | "Pick the event date (at least 10 days from today)" |
| 6 | **Time** | `CreateEventPickerField` — whole card tappable, trailing `Icons.access_time_rounded` | `Icons.schedule_outlined` | "Pick the start time" | required; `showTimePicker`, display via `DateFormat('h:mm a')` (model stores display strings like "10:00 AM") | "Pick the start time" |
| 7 | **Location** | `CreateEventTextField`, `TextInputAction.next` | `Icons.location_on_outlined` | "Add event location" | required | "Event location is required" |
| 8 | **Organizer** | `CreateEventTextField`, `TextInputAction.next` | `Icons.badge_outlined` | "Enter organizer or department name" | required | "Organizer is required" |
| 9 | **Description** | `CreateEventTextField` multiline (`maxLines: 5`, `minLines: 5`, `TextInputAction.newline`, `maxLength: 2000`, counter suppressed), card `descriptionCardMinHeight` 160, **top-aligned** label/helper (`alignLabelWithHint` behavior replicated by placing label+helper in the label row, not as a floating label) | `Icons.notes_rounded` | "Provide a detailed description of your event" | required | "Provide a description" |

**PDF upload field:**

| State | Visual | Error copy |
|---|---|---|
| Empty | `PdfUploadCard`: pink-tinted `uploadCardColor` fill, dashed border (`dashedBorderWidth` 1.4, dash 6 / gap 5, `uploadCardDashedBorderColor`), 48×48 `uploadTileColor` tile with `Icons.picture_as_pdf_rounded` 24 px, **"No PDF selected"** bold (`uploadFileName`), "Upload an official approval letter (PDF)" (`uploadHint`), right side outlined "Choose PDF" button (44 px high, radius 12, `choosePdfBorderColor` 1 px border, `choosePdfLabelColor` label, `Icons.upload_rounded` 16 px leading) | — (no error pre-interaction) |
| Selected | Same card; file name replaces "No PDF selected" (`uploadFileName` style, max 1 line, middle-ellipsis truncation); a small round **remove** affordance (`Icons.close_rounded` 16 px in a 24 px circle) appears next to the name or button — tapping removes the selection back to empty state | — |
| Error (submit attempted, no PDF) | Same card; dashed border + remove/choose button keep colors; error text below the card | "Approval letter is required" |
| Disabled | `AbsorbPointer` (whole form) while submitting | — |

Both tapping the card and the "Choose PDF" button invoke the **existing** `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: false)` flow (replacement = re-pick; removal = the remove affordance).

**Primary / secondary actions:**

- **Submit for Approval** (`CreateEventSubmitButton`): full-width 56 px, radius `buttonRadius`, `submitGradient` (header gradient), `submitButtonShadow`, white `Icons.send_rounded` 18 px + label "Submit for Approval" (`primaryButtonLabel`). While submitting: swap gradient for `submitDisabledGradient`, drop the shadow, replace the icon with a 20 px white `CircularProgressIndicator` (strokeWidth 2.4), label becomes "Submitting…", wrapped in `Semantics(liveRegion: true, label: 'Submitting event, please wait')`, `onPressed: null`. Duplicate-tap protection via a `_submitting` flag checked before `await`.
- **Cancel** (`CreateEventCancelButton`): full-width 56 px, radius `buttonRadius`, white fill, 1.5 px `cancelBorderColor` border, "Cancel" in `secondaryButtonLabel` raspberry. Behavior: if the form is dirty → show a **discard-confirmation dialog** (title "Discard changes?", body "You have unsaved changes.", actions "Keep editing" / "Discard"); if clean → `context.pop()`. Dirty = any controller non-empty OR any dropdown value chosen OR date/time chosen OR a PDF is selected.
- **Back (header)**: always plain `context.pop()` — no discard dialog (matches "back must trigger the existing navigation behavior").
- **On success**: keep the existing `_done` success branch ("Event Submitted!" + "Your event is pending admin approval…" + Back to Events → `context.go('/events')`), re-skinned minimally to the new palette. **On failure**: keep all form data, show a single retryable error (snackbar "Unable to submit event. Please try again."), re-enable the submit button; no Firebase error strings leak to the UI (service layer already translates).

**Dirty / discard details:** the old screen had no discard confirmation; adding it is additive and permitted ("preserve or add the discard-confirmation dialog"). Dialog uses the app's existing dialog conventions (system `AlertDialog`; `showDeleteCountdownDialog` in `lib/widgets/delete_countdown_dialog.dart` is overkill here — plain `showDialog` is fine).

---

## 4. Icon mapping + semantic labels

All icons are Material Icons already in the project's dependency set — **no new deps, no raster assets**.

| Location | Icon | Semantic label / tooltip (icon-only controls) |
|---|---|---|
| Header back | `Icons.arrow_back_rounded` (white, 22 px) | `Semantics(button: true, label: 'Back')` + `tooltip: 'Back'` |
| Approval info tile | `Icons.verified_user_outlined` (24 px, #AF0845) | decorative — `ExcludeSemantics` (heading text carries meaning) |
| Deadline info tile | `Icons.calendar_month_outlined` (24 px, #8A5F0A) | decorative — `ExcludeSemantics` |
| Info card chevrons | `Icons.chevron_right_rounded` (20 px) | decorative — `ExcludeSemantics` |
| Title tile | `Icons.title_rounded` | decorative (field label + input carry meaning) |
| Category tile | `Icons.category_outlined` | decorative |
| Category dropdown chevron | `Icons.expand_more_rounded` (20 px) | decorative; the dropdown trigger gets `Semantics(button: true, label: 'Category, select a category')` |
| Event type tile | `Icons.groups_outlined` | decorative |
| Event type dropdown chevron | `Icons.expand_more_rounded` | as Category |
| Max participants tile | `Icons.people_outline_rounded` | decorative |
| Date tile | `Icons.calendar_today_outlined` | decorative |
| Date trailing | `Icons.calendar_month_rounded` (20 px) | whole card: `Semantics(button: true, label: 'Date, pick the event date')` |
| Time tile | `Icons.schedule_outlined` | decorative |
| Time trailing | `Icons.access_time_rounded` (20 px) | whole card: `Semantics(button: true, label: 'Time, pick the start time')` |
| Location tile | `Icons.location_on_outlined` | decorative |
| Organizer tile | `Icons.badge_outlined` | decorative |
| Description tile | `Icons.notes_rounded` | decorative |
| Title counter | — | `Semantics(liveRegion: true, label: '$n of 100 characters')` |
| PDF tile | `Icons.picture_as_pdf_rounded` (24 px) | decorative |
| Choose PDF button | `Icons.upload_rounded` (16 px) leading | button already labeled "Choose PDF"; card tap: `Semantics(button: true, label: 'Upload approval letter PDF')` |
| Remove PDF | `Icons.close_rounded` (16 px, 24 px circle) | `Semantics(button: true, label: 'Remove selected PDF')` |
| Privacy note lock | `Icons.lock_outline_rounded` (14 px, `lockIconColor`) | decorative (adjacent caption text) |
| Submit icon | `Icons.send_rounded` (18 px, white) | decorative (button labeled); loading spinner: `Semantics(label: 'Submitting, please wait')` |

Every tappable surface is ≥44×44 logical px (48×48 tiles, 48×48 back, 56 px buttons, 44 px Choose PDF, full-card tap zones for Date/Time/PDF card).

---

## 5. Responsive plan

- **320 px (narrowest supported):** `contentPaddingHorizontal` 20 → 280 px content width. Field cards: fixed 48 px tile + 12 px gap, text column `Expanded` (label/helper wrap to 2 lines if needed — cards are min-height, never fixed height). Dropdown labels wrap. Title counter remains at the far right of the label row. **PDF card** switches to stacked layout below `narrowBreakpoint` (360): `LayoutBuilder` → if `constraints.maxWidth < 360`, the "Choose PDF" button renders below the text row, full-width of the card (still 44 px tall); otherwise it sits on the right. Verified safe: at 320 px, card inner width = 280−32 = 248 px, which cannot hold tile(48)+gap(12)+text+button(≈110) in one row — stacking is mandatory.
- **~390 px (reference width):** everything single-row exactly as the reference image; helper lines fit on one line (label 15 px + helper 12 px inside ≈310 px content width).
- **Tablets / large phones:** the sheet stays full-bleed white (rounded top), but its inner `Column` is constrained to `contentMaxWidth` (560) and centered (`Center` + `ConstrainedBox`). Header bubbles stay proportionally positioned (fraction-of-width anchors). Buttons and cards grow to the 560 px clamp, not to screen edge.
- **Text scaling:** all fixed sizes are pixel-based; layouts must not assume fixed heights — field cards use `minHeight`, info cards use `minHeight`, labels/helpers wrap (`maxLines` unset on labels/helpers except the PDF file name). At 200 % scale the form scrolls (single scroll view already handles it). Do **not** clamp `textScaler` (accessibility-hostile); do not put the title counter inside a fixed-width box — give it `mainAxisSize.min` + `Flexible` so it never overflows at large scale.
- **Keyboard insets:** `Scaffold.resizeToAvoidBottomInset: true` (default) + the scroll view's bottom padding = `scrollBottomPadding (32) + MediaQuery.viewInsetsOf(context).bottom` (recomputed in `build`). Additionally set `scrollPadding: EdgeInsets.only(bottom: 120)` on every `TextFormField` so the focused field scrolls above the keyboard. Keyboard must not cover the focused field nor the submit action.
- **Safe areas:** header height includes `MediaQuery.paddingOf(context).top` (§1); sheet content adds `SafeArea(top: false)` / bottom padding = `MediaQuery.paddingOf(context).bottom` so landscape/gesture-bar devices are safe.
- **Scroll strategy:** exactly ONE `SingleChildScrollView` for the sheet (header is pinned, not scrollable). No `ListView`/`GridView`/`NestedScrollView` anywhere. `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`.

---

## 6. File-layout plan for Agent 4 (ownership boundaries)

**Decision: extract the redesigned screen into a new file, keep the class name and route identical.** Rationale: `events_screens.dart` is 1,963 lines of many screens; the new screen is ~700+ lines of state+layout; a dedicated file plus a presentational widgets file keeps the pipeline agents from colliding on one giant file, and `export` keeps every existing import (`main.dart`, anything importing `events_screens.dart`) working with **zero route changes**.

| File | Action | Owner | Notes |
|---|---|---|---|
| `lib/screens/events/create_event_screen.dart` | **CREATE** | Agent 4 | Full `CreateEventScreen` + `_CreateEventScreenState`: all form state, controllers, FocusNodes, validators, date/time pickers, PDF picker, submit/cancel logic, `_done` success branch. Class name **must remain `CreateEventScreen`** (route `/events/create` in `main.dart:127` uses it). Needs a private `_toast` helper (the one in `events_screens.dart` is file-private) — copy the 4-line implementation. |
| `lib/screens/events/widgets/create_event_widgets.dart` | **CREATE** | Agent 4 | Every presentational widget in the §1 table (plus `_DashedRRectPainter`). Stateless, `const` constructors, imports only `flutter/material.dart` + `../theme/create_event_tokens.dart` (+ `app_theme.dart` only if a shared color is truly needed — prefer tokens). **No** Provider, **no** FilePicker, **no** state beyond widget params. |
| `lib/screens/events/events_screens.dart` | **MODIFY (surgical)** | Agent 4 | (a) Delete lines ~1200–1610: `CreateEventScreen` + `_CreateEventState` + `_buildCoverImagePicker` + `_pickCoverImage` + `_removeCoverImage` + `_pickApprovalPdf` + `_pickEventDate`. (b) Add `export 'create_event_screen.dart';` next to the existing exports (lines 15–16). Touch **nothing else**. |
| `lib/main.dart` | **UNCHANGED** | — | Route already points at `CreateEventScreen`; the export resolves it. |
| `lib/theme/create_event_tokens.dart` | CREATED by Agent 2 | Agent 2 | Constants only; import from the new screen/widgets files. |
| `docs/create_event_design_spec.md` | CREATED by Agent 2 | Agent 2 | This document. |
| `lib/models/event.dart`, `lib/services/app_state.dart`, `lib/services/event_service.dart` | **UNCHANGED** | — | `createEvent()` already forces `status: 'Pending'`, sets host/submittedDate, and `Event.toMap()` omits null cover-image fields. Submit path is behavior-compatible. |
| `lib/theme/app_theme.dart`, `lib/theme/luxe.dart`, `lib/widgets/common.dart` | **UNCHANGED** | — | Old widgets (`GradientButton`, `SectionLabel`, `NoticeBox`…) remain for other screens; the new screen uses its own token-driven components. |

**Collision-avoidance rules:** Agent 3 (state/validation) and Agent 5+ must treat `create_event_screen.dart`, `create_event_widgets.dart`, and the events_screens.dart delete+export edit as Agent 4's exclusive turf. State/validation design lives *inside* `create_event_screen.dart` (its state class) — no separate controller file. No agent may add imports of `create_event_widgets.dart` outside Agent 4's two files.

---

## 7. Accessibility & semantics checklist

- [ ] Header back: 48×48 target, `tooltip` + `Semantics` label "Back"; contrast white on #AF0845 ≈ 7.1:1 (passes AAA).
- [ ] Title/subtitle on header: white 22 px w800 / 90 % white 13 px on #AF0845 → ≈7.1:1 / ≈6.2:1 (passes AA).
- [ ] Info cards: heading #AF0845 on #FBEAF2 ≈ 6.2:1; amber #8A5F0A on #FBF3E2 ≈ 5.1:1; body #4A4450 on both ≈ 8:1 — all pass AA. Chevrons are `ExcludeSemantics` (no dead "button" announcements — cards are informational).
- [ ] Section labels #6E6778 on white ≈ 5.4:1 (11 px bold — passes AA).
- [ ] Field labels #1B1523 on white ≈ 17.8:1. Helper #7A7386 ≈ 4.54:1 (12 px). Counter #6E6778 ≈ 5.4:1. Error #9C0F4B ≈ 8.1:1. Cancel label #B01255 on white ≈ 6.9:1.
- [ ] Error states are **never color-only**: border + tinted tile icon + always-visible error text (`fieldError`). Focus state is border + label color change (non-color cue preserved).
- [ ] Icon-only controls (back, remove PDF) have tooltip + semantics label. Picker cards are announced as buttons with their purpose. The title counter is a `liveRegion` announcing "n of 100 characters".
- [ ] Focus order is natural top-to-bottom: back → (info cards skipped, not focusable) → title → category → event type → max participants → date → time → location → organizer → description → PDF card → submit → cancel. Dropdowns/pickers are keyboard-operable (focus + Enter/Space activates; `Focus` + `InkWell`/`Semantics` wrapper).
- [ ] Submit loading: button disabled + spinner + `Semantics(liveRegion)` "Submitting, please wait"; screen-reader users are not left with a dead button.
- [ ] Touch targets: everything interactive ≥44×44 (tiles 48, back 48, buttons 56, Choose PDF 44, full-card picker tap zones).
- [ ] Text scaling: min-heights not fixed heights; wrapping labels/helpers; no `textScaler` clamp.
- [ ] Keyboard insets: bottom padding ≥ keyboard height + 32; `scrollPadding: bottom 120` on inputs; `ensureVisible` on submit validation scroll.
- [ ] Reduced motion: no infinite animations; the only transient visuals (snackbar, dialog) are standard platform components.

---

## 8. Risks / conflicts with business rules

1. **Cover-image UI omitted (required) but model support preserved.** The reference screen has no cover section. `Event.coverImageUrl` / `coverImagePublicId` / `AppState.pickEventCoverImage` / `uploadEventCoverToCloudinary` must stay untouched. The new screen simply submits `coverImageUrl: null` — `Event.toMap()` already omits null cover fields, and `EventCover` (event_widgets.dart:307) falls back to the category placeholder. **No Cloudinary call in the new screen.** If a later agent reintroduces cover UI, it must live in `create_event_widgets.dart`/`create_event_screen.dart` only.
2. **Title 100-char counter is a UI-only rule.** The `Event` model has no title length limit and no server-side validation. Enforce `maxLength: 100` + live counter in the UI; do NOT add model validation (out of scope, other screens/admin editor would break on legacy data). **Only render the 0/100 counter because the enforced max IS 100** — consistent with the requirement.
3. **`Max Participants` semantics: 0 = unlimited.** The model (`Event.maxParticipants`, `Event.isFull`) treats 0 as no limit and the old UI used hint "0 = unlimited". New helper text is "Enter maximum number of participants" with the input placeholder "0 = unlimited"; empty/unparsable input submits 0. `digitsOnly` formatter prevents negatives/decimals.
4. **Paid/Club event configuration has no visible UI in the reference.** Old screen conditionally showed a "Require Club ID" checkbox and an "Entry Fee (RM)" field for `Club`/`Club+Payment`/`Paid` event types; the reference shows neither. Mapping (must be implemented by Agent 4 to keep model writes consistent): `isPrivate = eventType ∈ {Club, Club+Payment}`; `isPaid = eventType ∈ {Club+Payment, Paid}`; `clubIdRequired = false`; `price = 0.0`. **Risk:** a "Paid" event created here gets price 0.0. Decision recorded: follow the reference exactly; flag to lead that a follow-up may want to re-add conditional price/Club-ID fields (kept out so the pipeline matches the image).
5. **10-day deadline rule (business rule, must be preserved).** Existing: `firstDate = today + 10 days` at pick AND `daysUntilEvent < 10` rejection at submit with toast. New: same `firstDate` at pick, plus per-field error + scroll-to-field at submit instead of toast-only. Both layers kept.
6. **Approval PDF remains mandatory.** Existing submit rejects missing PDF. New: same rule; error renders on the upload card after a submit attempt. `hasApprovalLetter: true`, `approvalLetterPath: file.path`, `approvalLetterName: file.name` preserved exactly (admin detail screen reads these).
7. **Status/submission lifecycle unchanged.** `AppState.createEvent` forces `status: 'Pending'`, sets `hostStudentId`/`submittedDate`; success branch keeps existing "Event Submitted!" + `context.go('/events')`. `_eventTypes`/`_cats` option lists unchanged.
8. **Back/cancel behavior.** Back = plain `pop()` (existing). Cancel = new discard dialog only when dirty (additive). No discard dialog on back — matches "no content discard without the existing confirmation behavior" (there was none on back; we only add it to Cancel, which is the explicit exit affordance).
9. **Screen class identity.** `CreateEventScreen` name and const constructor must survive the move (route + any other importers). Do not rename to `NewCreateEventScreen` etc.

---

## Appendix A — What must NOT change (preservation checklist)

- Route `/events/create` in `main.dart:127` → `const CreateEventScreen()`.
- `AppState.createEvent` / `EventService.createEvent` / `Event` model — zero edits.
- `_cats = ['Academic','Sport','Club','General']`, `_eventTypes = ['Open','Club','Club+Payment','Paid']`.
- Status 'Pending', `submittedDate` today, `hasApprovalLetter: true` + path/name from picked PDF.
- Success flow (`_done` branch) → "Event Submitted!" → `context.go('/events')`.
- FilePicker config: `FileType.custom, allowedExtensions: ['pdf'], allowMultiple: false`.
- Date bounds: today + 10 days → today + 365 days.
- Everything else in `events_screens.dart` (24+ other screens) untouched.
