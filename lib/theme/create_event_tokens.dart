import 'package:flutter/material.dart';

/// ── Create Event screen design tokens ──────────────────────────────
///
/// Single source of truth for the redesigned `CreateEventScreen`
/// (dark-raspberry → vivid-pink header, white overlapping sheet, field
/// cards, PDF upload card). Constants only: no widgets, no logic, no
/// imports of screens/services — safe to import from any file in
/// `lib/` and from `lib/theme/` neighbors.
///
/// Every value below is mirrored by `docs/create_event_design_spec.md`.
abstract final class CreateEventTokens {
  CreateEventTokens._(); // lint-safe: class is `abstract final`

  // ── Font ──────────────────────────────────────────────────────
  static const String fontFamily = 'Inter';

  // ══════════════════════════════════════════════════════════════
  // Header (dark raspberry → vivid pink)
  // ══════════════════════════════════════════════════════════════
  static const Color headerGradientStart = Color(0xFFAF0845);
  static const Color headerGradientEnd = Color(0xFFEE2F6F);

  /// Raw gradient stops (list form) for painters/animations.
  static const List<Color> headerGradientColors = <Color>[
    headerGradientStart,
    headerGradientEnd,
  ];

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: headerGradientColors,
  );

  /// Content height of the header *below* the safe-area top inset.
  /// Total header height = `MediaQuery.paddingOf(context).top +
  /// headerContentHeight` → ≈176 logical px on a 44 px inset device
  /// (inside the 175–185 px requirement, inset included).
  static const double headerContentHeight = 132;

  /// Minimum total header height in logical px (inset included).
  static const double headerMinTotalHeight = 176;

  static const Color headerTitleColor = Color(0xFFFFFFFF);
  static const Color headerSubtitleColor = Color(0xE6FFFFFF); // 90% white

  // Translucent circular bubble decorations (clipped to the header).
  static const Color bubbleRing = Color(0x1FFFFFFF); // 12% white, stroke
  static const Color bubbleFill = Color(0x14FFFFFF); // 8% white, filled
  static const Color bubbleFillFaint = Color(0x0DFFFFFF); // 5% white, filled

  // 48×48 translucent circular back button.
  static const Color backButtonColor = Color(0x2EFFFFFF); // 18% white
  static const Color backButtonBorderColor = Color(0x40FFFFFF); // 25% white
  static const Color backButtonIconColor = Color(0xFFFFFFFF);

  // ══════════════════════════════════════════════════════════════
  // Surface / sheet
  // ══════════════════════════════════════════════════════════════
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color scaffoldColor = Color(0xFFFFFFFF);

  /// How far the sheet's rounded top overlaps the header's lower edge.
  static const double sheetOverlap = 28;

  // ══════════════════════════════════════════════════════════════
  // Info cards
  // ══════════════════════════════════════════════════════════════
  // 1. Admin approval (pale pink)
  static const Color infoPinkCardColor = Color(0xFFFBEAF2);
  static const Color infoPinkTileColor = Color(0xFFF8DCE8);
  static const Color infoPinkHeadingColor = Color(0xFFAF0845);
  static const Color infoPinkChevronColor = Color(0xFFAF0845);

  // 2. Submission deadline (pale warm cream)
  static const Color infoCreamCardColor = Color(0xFFFBF3E2);
  static const Color infoCreamTileColor = Color(0xFFF7E8C8);
  static const Color infoCreamHeadingColor = Color(0xFF8A5F0A);
  static const Color infoCreamChevronColor = Color(0xFF9A6A0F);

  static const Color infoCardTextColor = Color(0xFF4A4450);

  // ══════════════════════════════════════════════════════════════
  // Section headers
  // ══════════════════════════════════════════════════════════════
  static const Color sectionLabelColor = Color(0xFF6E6778);
  static const Color sectionRuleColor = Color(0xFFE9E5EE);

  // ══════════════════════════════════════════════════════════════
  // Field cards
  // ══════════════════════════════════════════════════════════════
  static const Color fieldCardColor = Color(0xFFFFFFFF);
  static const Color fieldCardBorderColor = Color(0xFFEDEAF2);
  static const Color fieldCardFocusBorderColor = Color(0xFFC2185B);
  static const Color fieldCardErrorBorderColor = Color(0xFFC2185B);

  static const Color fieldLabelColor = Color(0xFF1B1523); // near-black ink
  static const Color fieldHelperColor = Color(0xFF7A7386); // 4.54:1 on white
  static const Color fieldValueColor = Color(0xFF1B1523);
  static const Color fieldCounterColor = Color(0xFF6E6778);
  static const Color fieldErrorTextColor = Color(0xFF9C0F4B); // 8.1:1 on white

  // Pale-pink 48×48 icon tile.
  static const Color tileColor = Color(0xFFFBE9F1);
  static const Color tileIconColor = Color(0xFFB01255);
  static const Color tileIconErrorColor = Color(0xFFC2185B);

  // ══════════════════════════════════════════════════════════════
  // Approval letter (PDF) upload
  // ══════════════════════════════════════════════════════════════
  static const Color uploadCardColor = Color(0xFFFDF2F7);
  static const Color uploadCardDashedBorderColor = Color(0xFFE5A8C3);
  static const Color uploadTileColor = Color(0xFFF8DCE8);
  static const Color uploadTileIconColor = Color(0xFFB01255);
  static const Color uploadFileNameColor = Color(0xFF1B1523);
  static const Color uploadHintColor = Color(0xFF7A7386);
  static const Color uploadErrorTextColor = Color(0xFF9C0F4B);

  // Cover image upload card.
  static const Color coverUploadColor = Color(0xFFFFF7FA);
  static const Color coverUploadDashedBorderColor = Color(0xFFED7B9A);
  static const Color coverUploadIconColor = Color(0xFFB01255);
  static const Color coverUploadLabelColor = Color(0xFF1B1523);
  static const Color coverUploadHintColor = Color(0xFF6A7894);
  static const Color coverUploadOverlayStart = Color(0x00000000);
  static const Color coverUploadOverlayEnd = Color(0x94000000);
  static const Color coverUploadRemoveBg = Color(0x61000000);
  static const Color coverUploadRemoveIconColor = Color(0xFFFFFFFF);
  static const Color coverUploadProgressLabelColor = Color(0xFFFFFFFF);
  static const double coverUploadHeight = 172;
  static const double coverUploadIconEmptySize = 42;
  static const double coverUploadRemoveButtonSize = 38;
  static const double coverUploadRemoveIconSize = 20;
  static const double coverUploadDashedBorderWidth = 1.4;
  static const double coverUploadDashedDashWidth = 7;
  static const double coverUploadDashedDashGap = 5;

  // Choose PDF outlined button.
  static const Color choosePdfLabelColor = Color(0xFFB01255);
  static const Color choosePdfBorderColor = Color(0x4DB01255); // 30% raspberry
  static const Color choosePdfIconColor = Color(0xFFB01255);

  // Lock privacy note.
  static const Color lockIconColor = Color(0xFF6E6778);
  static const Color lockCaptionColor = Color(0xFF6E6778);

  // ══════════════════════════════════════════════════════════════
  // Primary / secondary actions
  // ══════════════════════════════════════════════════════════════
  static const LinearGradient submitGradient = headerGradient;

  /// Desaturated gradient shown while submitting (button disabled).
  static const LinearGradient submitDisabledGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFD68FA8), Color(0xFFE7B3C6)],
  );

  static const Color submitLabelColor = Color(0xFFFFFFFF);
  static const Color submitLoadingColor = Color(0xFFFFFFFF);

  static const Color cancelLabelColor = Color(0xFFB01255);
  static const Color cancelBorderColor = Color(0x4DB01255); // 30% raspberry
  static const Color cancelCardColor = Color(0xFFFFFFFF);

  // ══════════════════════════════════════════════════════════════
  // Radii
  // ══════════════════════════════════════════════════════════════
  static const double sheetTopRadius = 30; // requirement 28–32
  static const double cardRadius = 16;
  static const double tileRadius = 14;
  static const double backButtonRadius = 24; // circular (48/2)
  static const double buttonRadius = 14;
  static const double choosePdfButtonRadius = 12;
  static const double counterChipRadius = 999;

  // ══════════════════════════════════════════════════════════════
  // Spacing scale (8-pt based)
  // ══════════════════════════════════════════════════════════════
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double spaceXxl = 24;
  static const double spaceHuge = 32;

  /// Horizontal padding of the sheet's content (responsive down to 320 px).
  static const double contentPaddingHorizontal = 20;

  /// Vertical rhythm: gap before a section header.
  static const double sectionGapTop = 24;

  /// Vertical rhythm: gap between a section header and its first content.
  static const double sectionGapBottom = 10;

  /// Gap between consecutive field cards.
  static const double fieldGap = 12;

  /// Gap between the two info cards.
  static const double infoCardGap = 12;

  /// Inner padding of a field card.
  static const EdgeInsets fieldCardPadding = EdgeInsets.fromLTRB(16, 14, 16, 14);

  /// Inner padding of an info card.
  static const EdgeInsets infoCardPadding = EdgeInsets.fromLTRB(14, 14, 14, 14);

  /// Inner padding of the PDF upload card.
  static const EdgeInsets uploadCardPadding = EdgeInsets.all(16);

  /// Padding below the form so the last action never sits flush with
  /// the screen edge; the keyboard inset is *added* to this at runtime.
  static const double scrollBottomPadding = 32;

  // ══════════════════════════════════════════════════════════════
  // Sizes
  // ══════════════════════════════════════════════════════════════
  static const double backButtonSize = 48;
  static const double iconTileSize = 48;
  static const double iconTileIconSize = 22;
  static const double trailingIconSize = 20;
  static const double chevronSize = 20;
  static const double lockIconSize = 14;
  static const double choosePdfIconSize = 16;
  static const double submitIconSize = 18;
  static const double submitLoadingIndicatorSize = 20;

  /// Field card heights: requirement ~70–78 (except Description).
  /// Cards use *minimum* heights so text scaling never clips content.
  static const double fieldCardMinHeight = 76;
  static const double descriptionCardMinHeight = 160; // requirement 150–170
  static const double infoCardMinHeight = 84;

  /// Primary/secondary action heights: requirement 56.
  static const double primaryButtonHeight = 56;
  static const double secondaryButtonHeight = 56;

  /// Upload card action button height (compact, still ≥44 touch target).
  static const double choosePdfButtonHeight = 44;

  /// Max content width on tablets (content centers inside the sheet).
  static const double contentMaxWidth = 560;

  /// Below this viewport width the upload card stacks its button below
  /// the text instead of sitting on the right.
  static const double narrowBreakpoint = 360;

  // ══════════════════════════════════════════════════════════════
  // Border widths
  // ══════════════════════════════════════════════════════════════
  static const double borderWidthIdle = 1.0;
  static const double borderWidthFocused = 1.6;
  static const double borderWidthError = 1.6;
  static const double borderWidthBackButton = 1.0;
  static const double borderWidthCancelButton = 1.5;
  static const double dashedBorderWidth = 1.4;
  static const double dashedBorderDashWidth = 6;
  static const double dashedBorderDashGap = 5;

  // ══════════════════════════════════════════════════════════════
  // Shadows
  // ══════════════════════════════════════════════════════════════
  static const BoxShadow fieldCardShadow = BoxShadow(
    color: Color(0x0D2A1B3D), // 5% cool near-black
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  static const BoxShadow submitButtonShadow = BoxShadow(
    color: Color(0x4DAF0845), // 30% raspberry
    blurRadius: 16,
    offset: Offset(0, 6),
  );

  // ══════════════════════════════════════════════════════════════
  // Type scale (all Inter, matches app font)
  // ══════════════════════════════════════════════════════════════
  static const TextStyle headerTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: headerTitleColor,
    letterSpacing: -0.5,
    height: 1.15,
  );

  static const TextStyle headerSubtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: headerSubtitleColor,
    height: 1.35,
  );

  static const TextStyle infoCardHeading = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const TextStyle infoCardBody = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: infoCardTextColor,
    height: 1.45,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: sectionLabelColor,
    letterSpacing: 1.2,
  );

  static const TextStyle fieldLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: fieldLabelColor,
    height: 1.2,
  );

  static const TextStyle fieldLabelFocused = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: fieldCardFocusBorderColor,
    height: 1.2,
  );

  static const TextStyle fieldHelper = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: fieldHelperColor,
    height: 1.35,
  );

  static const TextStyle fieldValue = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: fieldValueColor,
    height: 1.2,
  );

  static const TextStyle fieldError = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: fieldErrorTextColor,
    height: 1.35,
  );

  static const TextStyle fieldCounter = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: fieldCounterColor,
  );

  static const TextStyle uploadFileName = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: uploadFileNameColor,
    height: 1.25,
  );

  static const TextStyle uploadHint = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: uploadHintColor,
    height: 1.35,
  );

  static const TextStyle lockCaption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: lockCaptionColor,
    height: 1.3,
  );

  static const TextStyle primaryButtonLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: submitLabelColor,
    letterSpacing: 0.2,
  );

  static const TextStyle secondaryButtonLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: cancelLabelColor,
    letterSpacing: 0.2,
  );

  static const TextStyle choosePdfLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: choosePdfLabelColor,
  );
}
