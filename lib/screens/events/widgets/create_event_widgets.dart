import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/create_event_tokens.dart';

/// ── Create Event screen — presentational widgets ─────────────────
///
/// Every widget in the redesign's component tree (design spec §1) lives
/// here. All are [StatelessWidget]s with `const` constructors where
/// possible, and draw every visual value exclusively from
/// [CreateEventTokens]. No Provider, no FilePicker, no AppState, no other
/// project imports — the screen (create_event_screen.dart) owns all state,
/// controllers, focus, pickers, and submit/cancel logic and passes values
/// in via constructor parameters.

/// Variant selector for [EventInfoCard].
enum EventInfoVariant { approval, deadline }

/// Pinned gradient header: translucent bubbles, circular back button,
/// title + subtitle.
///
/// Height is driven by the content (safe-area top inset + back button +
/// title + subtitle + bottom padding) instead of a fixed constant, so the
/// white sheet that begins at the header's lower edge can never cover the
/// subtitle, and the header grows cleanly with larger accessibility text
/// scales instead of clipping.
class CreateEventHeader extends StatelessWidget {
  const CreateEventHeader({
    super.key,
    required this.onBack,
    required this.topInset,
  });

  final VoidCallback onBack;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration:
          const BoxDecoration(gradient: CreateEventTokens.headerGradient),
      child: ClipRect(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _HeaderBubblesPainter()),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                CreateEventTokens.spaceLg,
                topInset + CreateEventTokens.spaceSm,
                CreateEventTokens.spaceLg,
                CreateEventTokens.spaceLg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    button: true,
                    label: 'Back',
                    child: Tooltip(
                      message: 'Back',
                      child: Material(
                        color: CreateEventTokens.backButtonColor,
                        shape: const CircleBorder(
                          side: BorderSide(
                            color: CreateEventTokens.backButtonBorderColor,
                            width: CreateEventTokens.borderWidthBackButton,
                          ),
                        ),
                        child: SizedBox(
                          width: CreateEventTokens.backButtonSize,
                          height: CreateEventTokens.backButtonSize,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onBack,
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              size: 22,
                              color: CreateEventTokens.backButtonIconColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: CreateEventTokens.spaceMd),
                  const Text(
                    'Create Event',
                    style: CreateEventTokens.headerTitle,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Fill in the details to create your event.',
                    style: CreateEventTokens.headerSubtitle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White sheet surface with 30 px top radii, overlapping the header.
class CreateEventSheet extends StatelessWidget {
  const CreateEventSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: CreateEventTokens.surfaceColor,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CreateEventTokens.sheetTopRadius),
        ),
      ),
      child: child,
    );
  }
}

/// Pale pink / pale cream informational card (no tap target).
class EventInfoCard extends StatelessWidget {
  const EventInfoCard({super.key, required this.variant});

  final EventInfoVariant variant;

  @override
  Widget build(BuildContext context) {
    final Color cardColor;
    final Color tileColor;
    final Color headingColor;
    final Color chevronColor;
    final IconData icon;
    final String heading;
    final String body;
    switch (variant) {
      case EventInfoVariant.approval:
        cardColor = CreateEventTokens.infoPinkCardColor;
        tileColor = CreateEventTokens.infoPinkTileColor;
        headingColor = CreateEventTokens.infoPinkHeadingColor;
        chevronColor = CreateEventTokens.infoPinkChevronColor;
        icon = Icons.verified_user_outlined;
        heading = 'Admin approval required';
        body =
            'Your event will be reviewed and approved by admin before publishing.';
      case EventInfoVariant.deadline:
        cardColor = CreateEventTokens.infoCreamCardColor;
        tileColor = CreateEventTokens.infoCreamTileColor;
        headingColor = CreateEventTokens.infoCreamHeadingColor;
        chevronColor = CreateEventTokens.infoCreamChevronColor;
        icon = Icons.calendar_month_outlined;
        heading = 'Submission deadline';
        body =
            'Events must be submitted at least 10 days before the event date to allow admin review.';
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: CreateEventTokens.infoCardMinHeight,
      ),
      child: Container(
        padding: CreateEventTokens.infoCardPadding,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(CreateEventTokens.cardRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: CreateEventTokens.iconTileSize,
              height: CreateEventTokens.iconTileSize,
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius:
                    BorderRadius.circular(CreateEventTokens.tileRadius),
              ),
              child: Icon(icon, size: 24, color: headingColor),
            ),
            const SizedBox(width: CreateEventTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    heading,
                    style: CreateEventTokens.infoCardHeading
                        .copyWith(color: headingColor),
                  ),
                  const SizedBox(height: CreateEventTokens.spaceXs),
                  Text(body, style: CreateEventTokens.infoCardBody),
                ],
              ),
            ),
            const SizedBox(width: CreateEventTokens.spaceSm),
            ExcludeSemantics(
              child: Icon(
                Icons.chevron_right_rounded,
                size: CreateEventTokens.chevronSize,
                color: chevronColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uppercase gray section label with a thin rule to its right.
class CreateEventSectionHeader extends StatelessWidget {
  const CreateEventSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The label may wrap down to the row width minus the 10 px rule gap;
        // the trailing rule then fills whatever width is left. At 1.0 scale
        // the label keeps its natural single-line width and the rule spans to
        // the right edge exactly as before; at 2.0 text scale the label wraps
        // instead of overflowing (design spec §5 forbids clamping textScaler).
        final double labelMaxWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth > 10.0 ? constraints.maxWidth - 10.0 : 0.0)
            : double.infinity;
        return Row(
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: labelMaxWidth),
              child: Text(
                label.toUpperCase(),
                style: CreateEventTokens.sectionLabel,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                color: CreateEventTokens.sectionRuleColor,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Base field card: 48×48 pale-pink icon tile, label, helper, input slot,
/// error slot, and idle/focused/error border + label states (design §3.1).
class CreateEventFieldCard extends StatelessWidget {
  const CreateEventFieldCard({
    super.key,
    required this.icon,
    required this.label,
    this.helper,
    this.trailing,
    this.child,
    this.errorText,
    this.focused = false,
    this.minHeight,
    this.onTap,
    this.semanticsLabel,
  });

  final IconData icon;
  final String label;
  final String? helper;
  final Widget? trailing;
  final Widget? child;
  final String? errorText;
  final bool focused;
  final double? minHeight;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final bool hasError = errorText != null;
    final Color borderColor = hasError
        ? CreateEventTokens.fieldCardErrorBorderColor
        : focused
            ? CreateEventTokens.fieldCardFocusBorderColor
            : CreateEventTokens.fieldCardBorderColor;
    final double borderWidth = hasError
        ? CreateEventTokens.borderWidthError
        : focused
            ? CreateEventTokens.borderWidthFocused
            : CreateEventTokens.borderWidthIdle;
    final Color tileIconColor = hasError
        ? CreateEventTokens.tileIconErrorColor
        : CreateEventTokens.tileIconColor;
    final TextStyle labelStyle = focused && !hasError
        ? CreateEventTokens.fieldLabelFocused
        : CreateEventTokens.fieldLabel;

    final Widget card = Container(
      constraints: BoxConstraints(
        minHeight: minHeight ?? CreateEventTokens.fieldCardMinHeight,
      ),
      decoration: BoxDecoration(
        color: CreateEventTokens.fieldCardColor,
        borderRadius: BorderRadius.circular(CreateEventTokens.cardRadius),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: const <BoxShadow>[CreateEventTokens.fieldCardShadow],
      ),
      child: Padding(
        padding: CreateEventTokens.fieldCardPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: CreateEventTokens.iconTileSize,
              height: CreateEventTokens.iconTileSize,
              decoration: BoxDecoration(
                color: CreateEventTokens.tileColor,
                borderRadius:
                    BorderRadius.circular(CreateEventTokens.tileRadius),
              ),
              child: Icon(
                icon,
                size: CreateEventTokens.iconTileIconSize,
                color: tileIconColor,
              ),
            ),
            const SizedBox(width: CreateEventTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(child: Text(label, style: labelStyle)),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  if (helper != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: CreateEventTokens.spaceXs,
                      ),
                      child: Text(
                        helper!,
                        style: CreateEventTokens.fieldHelper,
                      ),
                    ),
                  if (child != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: CreateEventTokens.spaceSm,
                      ),
                      child: child!,
                    ),
                  if (hasError)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: CreateEventTokens.spaceXs,
                      ),
                      child: Text(
                        errorText!,
                        style: CreateEventTokens.fieldError,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return card;
    }
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CreateEventTokens.cardRadius),
          child: card,
        ),
      ),
    );
  }
}

/// Live `n/100` title counter (pill, `liveRegion` semantics).
class CreateEventCounter extends StatelessWidget {
  const CreateEventCounter({super.key, required this.count, required this.max});

  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '$count of $max characters',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CreateEventTokens.spaceSm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: CreateEventTokens.fieldCardBorderColor,
          borderRadius:
              BorderRadius.circular(CreateEventTokens.counterChipRadius),
        ),
        child: Text('$count/$max', style: CreateEventTokens.fieldCounter),
      ),
    );
  }
}

/// Borderless [TextFormField] embedded in a [CreateEventFieldCard].
class CreateEventTextField extends StatelessWidget {
  const CreateEventTextField({
    super.key,
    required this.controller,
    this.validator,
    this.focusNode,
    this.onChanged,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.inputFormatters,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final int? minLines;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      validator: validator,
      onChanged: onChanged,
      enabled: enabled,
      style: CreateEventTokens.fieldValue,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      scrollPadding: const EdgeInsets.only(bottom: 120),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: CreateEventTokens.fieldHelper,
        counterText: '',
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        errorStyle: CreateEventTokens.fieldError,
        errorMaxLines: 2,
      ),
    );
  }
}

/// Dropdown embedded in a [CreateEventFieldCard], trailing `expand_more`.
class CreateEventDropdownField extends StatelessWidget {
  const CreateEventDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.focusNode,
    this.enabled = true,
    this.semanticsLabel,
  });

  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final FormFieldValidator<String>? validator;
  final FocusNode? focusNode;
  final bool enabled;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final Widget dropdown = DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      focusNode: focusNode,
      icon: const Icon(
        Icons.expand_more_rounded,
        size: CreateEventTokens.chevronSize,
        color: CreateEventTokens.fieldHelperColor,
      ),
      style: CreateEventTokens.fieldValue,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        hintText: 'Select',
        hintStyle: CreateEventTokens.fieldHelper,
        errorStyle: CreateEventTokens.fieldError,
        errorMaxLines: 2,
      ),
      items: items
          .map(
            (String item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
                style: CreateEventTokens.fieldValue,
              ),
            ),
          )
          .toList(),
      onChanged: enabled ? onChanged : null,
      validator: validator,
    );

    if (semanticsLabel == null) {
      return dropdown;
    }
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: dropdown,
    );
  }
}

/// Read-only display field; whole card tappable, trailing icon.
class CreateEventPickerField extends StatelessWidget {
  const CreateEventPickerField({
    super.key,
    required this.valueText,
    required this.placeholder,
    required this.trailingIcon,
    this.errorText,
  });

  final String? valueText;
  final String placeholder;
  final IconData trailingIcon;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final bool hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                valueText ?? placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueText != null
                    ? CreateEventTokens.fieldValue
                    : CreateEventTokens.fieldHelper,
              ),
            ),
            const SizedBox(width: CreateEventTokens.spaceSm),
            Icon(
              trailingIcon,
              size: CreateEventTokens.trailingIconSize,
              color: hasError
                  ? CreateEventTokens.tileIconErrorColor
                  : CreateEventTokens.fieldHelperColor,
            ),
          ],
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: CreateEventTokens.spaceXs),
            child: Text(errorText!, style: CreateEventTokens.fieldError),
          ),
      ],
    );
  }
}

/// Pink-tinted dashed-border upload card + "Choose PDF" button + optional
/// remove affordance. Error text renders below the card.
class PdfUploadCard extends StatelessWidget {
  const PdfUploadCard({
    super.key,
    this.fileName,
    required this.onChoose,
    this.onRemove,
    this.errorText,
  });

  final String? fileName;
  final VoidCallback onChoose;
  final VoidCallback? onRemove;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CreateEventTokens.uploadCardColor,
            borderRadius: BorderRadius.circular(CreateEventTokens.cardRadius),
          ),
          child: CustomPaint(
            painter: const _DashedRRectPainter(
              color: CreateEventTokens.uploadCardDashedBorderColor,
              strokeWidth: CreateEventTokens.dashedBorderWidth,
              dashWidth: CreateEventTokens.dashedBorderDashWidth,
              dashGap: CreateEventTokens.dashedBorderDashGap,
              radius: CreateEventTokens.cardRadius,
            ),
            child: Semantics(
              button: true,
              label: 'Upload approval letter PDF',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onChoose,
                  borderRadius:
                      BorderRadius.circular(CreateEventTokens.cardRadius),
                  child: Padding(
                    padding: CreateEventTokens.uploadCardPadding,
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                        final bool narrow = constraints.maxWidth <
                            CreateEventTokens.narrowBreakpoint;
                        final Widget textBlock = _buildTextBlock();
                        final Widget chooseButton = _buildChooseButton();
                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              textBlock,
                              const SizedBox(height: CreateEventTokens.spaceMd),
                              chooseButton,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            Expanded(child: textBlock),
                            const SizedBox(width: CreateEventTokens.spaceMd),
                            chooseButton,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: CreateEventTokens.spaceSm),
            child: Text(errorText!, style: CreateEventTokens.fieldError),
          ),
      ],
    );
  }

  Widget _buildTextBlock() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: CreateEventTokens.iconTileSize,
          height: CreateEventTokens.iconTileSize,
          decoration: BoxDecoration(
            color: CreateEventTokens.uploadTileColor,
            borderRadius: BorderRadius.circular(CreateEventTokens.tileRadius),
          ),
          child: const Icon(
            Icons.picture_as_pdf_rounded,
            size: 24,
            color: CreateEventTokens.uploadTileIconColor,
          ),
        ),
        const SizedBox(width: CreateEventTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      fileName ?? 'No PDF selected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CreateEventTokens.uploadFileName,
                    ),
                  ),
                  if (fileName != null && onRemove != null)
                    _buildRemoveButton(),
                ],
              ),
              const SizedBox(height: CreateEventTokens.spaceXs),
              const Text(
                'Upload an official approval letter (PDF)',
                style: CreateEventTokens.uploadHint,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRemoveButton() {
    return Semantics(
      button: true,
      label: 'Remove selected PDF',
      child: Tooltip(
        message: 'Remove PDF',
        child: Material(
          color: CreateEventTokens.uploadTileColor,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onRemove,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: CreateEventTokens.uploadTileIconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChooseButton() {
    return SizedBox(
      height: CreateEventTokens.choosePdfButtonHeight,
      child: OutlinedButton.icon(
        onPressed: onChoose,
        icon: const Icon(
          Icons.upload_rounded,
          size: CreateEventTokens.choosePdfIconSize,
          color: CreateEventTokens.choosePdfIconColor,
        ),
        label: const Text('Choose PDF'),
        style: OutlinedButton.styleFrom(
          foregroundColor: CreateEventTokens.choosePdfLabelColor,
          side: const BorderSide(
            color: CreateEventTokens.choosePdfBorderColor,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              CreateEventTokens.choosePdfButtonRadius,
            ),
          ),
          textStyle: CreateEventTokens.choosePdfLabel,
          padding: const EdgeInsets.symmetric(
            horizontal: CreateEventTokens.spaceMd,
          ),
        ),
      ),
    );
  }
}

/// Lock icon + privacy caption.
class PdfSecurityNote extends StatelessWidget {
  const PdfSecurityNote({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.lock_outline_rounded,
          size: CreateEventTokens.lockIconSize,
          color: CreateEventTokens.lockIconColor,
        ),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'Your document will be secure and confidential.',
            style: CreateEventTokens.lockCaption,
          ),
        ),
      ],
    );
  }
}

/// Dashed-border tappable card for uploading a cover image for the event.
///
/// Mirrors the admin `_AdminCreateUploadCard` but draws every visual value
/// from [CreateEventTokens] so it stays consistent with the student screen's
/// design system. Shows a preview when [file] is non-null, an empty cloud
/// upload state otherwise. Progress text renders while [uploading].
class CoverImageUploadCard extends StatelessWidget {
  const CoverImageUploadCard({
    super.key,
    required this.file,
    this.imageUrl,
    this.removed = false,
    this.uploading = false,
    this.progress,
    required this.onPick,
    required this.onRemove,
  });

  final File? file;
  final String? imageUrl;
  final bool removed;
  final bool uploading;
  final double? progress;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  bool get hasPreview =>
      file != null ||
      (!removed && imageUrl != null && imageUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CreateEventTokens.cardRadius),
      child: CustomPaint(
        painter: const _CoverImageDashedPainter(),
        child: Material(
          color: CreateEventTokens.coverUploadColor,
          child: InkWell(
            onTap: uploading ? null : onPick,
            child: SizedBox(
              height: CreateEventTokens.coverUploadHeight,
              child: hasPreview ? _preview() : _emptyState(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(
          Icons.image_outlined,
          color: CreateEventTokens.coverUploadIconColor,
          size: CreateEventTokens.coverUploadIconEmptySize,
        ),
        const SizedBox(height: 9),
        const Text(
          'Upload Cover Image',
          style: TextStyle(
            color: CreateEventTokens.coverUploadLabelColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'PNG, JPG or WEBP (Max 5 MB)',
          style: TextStyle(
            color: CreateEventTokens.coverUploadHintColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _preview() {
    final Widget image;
    if (file != null) {
      image = Image.file(
        file!,
        fit: BoxFit.cover,
        width: double.infinity,
      );
    } else {
      image = Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: CreateEventTokens.coverUploadHintColor,
            size: 38,
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        image,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                CreateEventTokens.coverUploadOverlayStart,
                CreateEventTokens.coverUploadOverlayEnd,
              ],
            ),
          ),
        ),
        Positioned(
          left: 14,
          bottom: 13,
          child: Text(
            uploading
                ? 'Uploading${progress == null ? '' : ' ${(progress! * 100).round()}%'}'
                : 'Tap to replace image',
            style: const TextStyle(
              color: CreateEventTokens.coverUploadProgressLabelColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: CreateEventTokens.coverUploadRemoveBg,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: uploading ? null : onRemove,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: CreateEventTokens.coverUploadRemoveButtonSize,
                height: CreateEventTokens.coverUploadRemoveButtonSize,
                child: Icon(
                  Icons.close_rounded,
                  color: CreateEventTokens.coverUploadRemoveIconColor,
                  size: CreateEventTokens.coverUploadRemoveIconSize,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Private dashed rounded-rectangle border for the cover image upload card.
class _CoverImageDashedPainter extends CustomPainter {
  const _CoverImageDashedPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = CreateEventTokens.coverUploadDashedBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = CreateEventTokens.coverUploadDashedBorderWidth;

    final Path path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(CreateEventTokens.cardRadius),
      ));

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end = (distance + CreateEventTokens.coverUploadDashedDashWidth)
            .clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + CreateEventTokens.coverUploadDashedDashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 56 px full-width gradient submit button with loading state.
class CreateEventSubmitButton extends StatelessWidget {
  const CreateEventSubmitButton({
    super.key,
    required this.submitting,
    required this.onPressed,
  });

  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Widget button = Container(
      height: CreateEventTokens.primaryButtonHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: submitting
            ? CreateEventTokens.submitDisabledGradient
            : CreateEventTokens.submitGradient,
        borderRadius: BorderRadius.circular(CreateEventTokens.buttonRadius),
        boxShadow: submitting
            ? const <BoxShadow>[]
            : const <BoxShadow>[CreateEventTokens.submitButtonShadow],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(CreateEventTokens.buttonRadius),
        child: InkWell(
          onTap: submitting ? null : onPressed,
          borderRadius: BorderRadius.circular(CreateEventTokens.buttonRadius),
          child: Center(
            child: submitting
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: CreateEventTokens.submitLoadingIndicatorSize,
                        height: CreateEventTokens.submitLoadingIndicatorSize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: CreateEventTokens.submitLoadingColor,
                        ),
                      ),
                      SizedBox(width: CreateEventTokens.spaceMd),
                      Text(
                        'Submitting…',
                        style: CreateEventTokens.primaryButtonLabel,
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.send_rounded,
                        size: CreateEventTokens.submitIconSize,
                        color: CreateEventTokens.submitLabelColor,
                      ),
                      SizedBox(width: CreateEventTokens.spaceSm),
                      Flexible(
                        child: Text(
                          'Submit for Approval',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: CreateEventTokens.primaryButtonLabel,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (submitting) {
      return Semantics(
        liveRegion: true,
        label: 'Submitting event, please wait',
        child: button,
      );
    }
    return button;
  }
}

/// 56 px white outlined cancel button, raspberry border/label.
class CreateEventCancelButton extends StatelessWidget {
  const CreateEventCancelButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: CreateEventTokens.secondaryButtonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: CreateEventTokens.cancelCardColor,
          foregroundColor: CreateEventTokens.cancelLabelColor,
          side: const BorderSide(
            color: CreateEventTokens.cancelBorderColor,
            width: CreateEventTokens.borderWidthCancelButton,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CreateEventTokens.buttonRadius),
          ),
          textStyle: CreateEventTokens.secondaryButtonLabel,
          padding: EdgeInsets.zero,
        ),
        child: const Text('Cancel'),
      ),
    );
  }
}

/// Translucent circular bubble decorations for the header (clipped).
class _HeaderBubblesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint ringPaint = Paint()
      ..color = CreateEventTokens.bubbleRing
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Three concentric rings anchored near the top-right.
    final Offset ringCenter = Offset(size.width * 0.92, size.height * 0.12);
    canvas.drawCircle(ringCenter, 46, ringPaint);
    canvas.drawCircle(ringCenter, 72, ringPaint);
    canvas.drawCircle(ringCenter, 98, ringPaint);

    final Paint fillPaint = Paint()
      ..color = CreateEventTokens.bubbleFill
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.06, size.height * 0.86),
      38,
      fillPaint,
    );

    final Paint faintPaint = Paint()
      ..color = CreateEventTokens.bubbleFillFaint
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.52),
      12,
      faintPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dashed rounded-rectangle border painter for the PDF upload card.
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashGap,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashGap;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final double inset = strokeWidth / 2;
    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          inset, inset, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius - inset),
    );

    final Path source = Path()..addRRect(rrect);
    final Path dashed = _dashPath(source, dashWidth, dashGap);
    canvas.drawPath(dashed, paint);
  }

  Path _dashPath(Path source, double dash, double gap) {
    final Path result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end = (distance + dash).clamp(0.0, metric.length);
        result.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gap;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashGap != dashGap ||
      oldDelegate.radius != radius;
}
