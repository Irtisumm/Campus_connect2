import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/create_event_tokens.dart';
import 'create_event_form_state.dart';
import 'widgets/create_event_widgets.dart';

/// Private toast helper (copied from `events_screens.dart` — that one is
/// file-private there, so this screen owns its own copy).
void _toast(BuildContext ctx, String msg) =>
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      duration: const Duration(seconds: 2),
    ));

/// Redesigned student "Create Event" screen (route `/events/create`).
///
/// Owns all form state (controllers, focus nodes, pickers, submit/cancel
/// logic) and drives the pure [CreateEventFormModel] from Agent 3. All
/// visuals come from [CreateEventTokens] via the presentational widgets in
/// `create_event_widgets.dart`.
class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  static const String _approvalLetterKey = 'approvalLetter';

  final CreateEventFormModel _model = CreateEventFormModel();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Text controllers (one per text field).
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _maxParticipantsController =
      TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _organizerController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Focus nodes (text fields + dropdowns; pickers scroll-only).
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _categoryFocus = FocusNode();
  final FocusNode _eventTypeFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();
  final FocusNode _maxParticipantsFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();
  final FocusNode _organizerFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();

  // Per-field GlobalKeys for scroll-into-view on failed submit.
  final Map<String, GlobalKey> _fieldKeys = <String, GlobalKey>{
    CreateEventFieldIds.title: GlobalKey(),
    CreateEventFieldIds.category: GlobalKey(),
    CreateEventFieldIds.eventType: GlobalKey(),
    CreateEventFieldIds.price: GlobalKey(),
    CreateEventFieldIds.maxParticipants: GlobalKey(),
    CreateEventFieldIds.date: GlobalKey(),
    CreateEventFieldIds.time: GlobalKey(),
    CreateEventFieldIds.location: GlobalKey(),
    CreateEventFieldIds.organizer: GlobalKey(),
    CreateEventFieldIds.description: GlobalKey(),
    _approvalLetterKey: GlobalKey(),
  };

  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  bool _pdfError = false;
  bool _discardConfirmed = false;

  // Cover image state (only the *selected* local file; no edit flow).
  File? _coverImageFile;
  double? _uploadProgress;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _maxParticipantsController.dispose();
    _locationController.dispose();
    _organizerController.dispose();
    _descriptionController.dispose();
    _titleFocus.dispose();
    _categoryFocus.dispose();
    _eventTypeFocus.dispose();
    _priceFocus.dispose();
    _maxParticipantsFocus.dispose();
    _locationFocus.dispose();
    _organizerFocus.dispose();
    _descriptionFocus.dispose();
    _model.dispose();
    super.dispose();
  }

  // ── Pickers ─────────────────────────────────────────────────────

  Future<void> _pickEventDate() async {
    final DateTime today = DateTime.now();
    final DateTime minDate = DateTime(today.year, today.month, today.day + 10);
    final DateTime lastDate =
        DateTime(today.year, today.month, today.day + 365);
    // A previously picked date can fall below the new `firstDate` after the
    // window rolls forward past midnight (the earliest allowed date is
    // `today + 10`). Clamp so `showDatePicker` never receives an
    // `initialDate` outside its bounds (which asserts in debug builds).
    final DateTime? current = _model.eventDate;
    final DateTime initialDate =
        current != null && !current.isBefore(minDate) ? current : minDate;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: minDate,
      lastDate: lastDate,
    );
    if (picked == null) return;
    _model.eventDate = picked;
  }

  Future<void> _pickEventTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _model.eventTime ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked == null) return;
    _model.eventTime = picked;
  }

  Future<void> _pickApprovalPdf() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf'],
        allowMultiple: false,
      );
    } catch (_) {
      // Platform-channel failures must never surface exception details,
      // paths, or stacks to the user — a safe, generic toast only, with
      // model state left untouched.
      if (mounted) {
        _toast(context, 'Unable to open file picker. Please try again.');
      }
      return;
    }
    if (result == null || result.files.isEmpty) return; // user cancelled
    if (!mounted) return;
    final PlatformFile file = result.files.single;
    // Usability guard: cap the approval letter at 10 MB. `size` is 0 when
    // the platform cannot determine it — an unknown size is admitted
    // rather than rejected on a value we do not have.
    if (file.size > 10 * 1024 * 1024) {
      _toast(context, 'Approval letter must be under 10 MB');
      return;
    }
    // Defense-in-depth: the `allowedExtensions` filter is the primary gate,
    // but not every platform honors it. Verify the picked file is actually
    // a PDF before committing it to the model (state stays unchanged).
    final String? ext = file.extension?.toLowerCase();
    final bool isPdf = ext == 'pdf' ||
        (ext == null && file.name.toLowerCase().endsWith('.pdf'));
    if (!isPdf) {
      _toast(context, 'Only PDF files are allowed');
      return;
    }
    _model.approvalPdf = file;
  }

  Future<void> _pickCoverImage(AppState appState) async {
    try {
      final File? file = await appState.pickEventCoverImage();
      if (file == null || !mounted) return;
      if (await file.length() > 5 * 1024 * 1024) {
        _toast(context, 'Please choose an image smaller than 5 MB');
        return;
      }
      setState(() => _coverImageFile = file);
    } catch (_) {
      if (mounted) {
        _toast(context, 'Unable to select image. Please try again.');
      }
    }
  }

  void _removeCover() {
    setState(() => _coverImageFile = null);
  }

  // ── Discard confirmation (lead decision #8) ────────────────────

  Future<void> _confirmDiscard() async {
    final bool? shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (shouldDiscard == true && mounted) {
      // Flip the flag inside setState so `PopScope.canPop` re-syncs on the
      // next rebuild (lead-review-note consistency fix). The pop stays an
      // imperative `context.pop()` — the GoRouter idiom — which completes
      // the confirmed discard.
      setState(() => _discardConfirmed = true);
      context.pop();
    }
  }

  void _handleCancel() {
    if (_model.isDirty || _coverImageFile != null) {
      _confirmDiscard();
    } else {
      context.pop();
    }
  }

  // ── Scroll / focus helpers ──────────────────────────────────────

  void _scrollToField(String id) {
    final GlobalKey? key = _fieldKeys[id];
    final BuildContext? fieldContext = key?.currentContext;
    if (fieldContext == null) return;
    Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.4,
    );
    final FocusNode? focusNode = _focusNodes[id];
    focusNode?.requestFocus();
  }

  bool get _showErrors => _autovalidateMode != AutovalidateMode.disabled;

  Map<String, FocusNode> get _focusNodes => <String, FocusNode>{
        CreateEventFieldIds.title: _titleFocus,
        CreateEventFieldIds.category: _categoryFocus,
        CreateEventFieldIds.eventType: _eventTypeFocus,
        CreateEventFieldIds.price: _priceFocus,
        CreateEventFieldIds.maxParticipants: _maxParticipantsFocus,
        CreateEventFieldIds.location: _locationFocus,
        CreateEventFieldIds.organizer: _organizerFocus,
        CreateEventFieldIds.description: _descriptionFocus,
      };

  // ── Submit ──────────────────────────────────────────────────────

  Future<void> _handleSubmit() async {
    final CreateEventFormModel model = _model;
    if (model.submitting) return;

    final AppState appState = context.read<AppState>();
    final SubmitEvaluation eval = model.evaluateSubmit(
      today: DateTime.now(),
      loggedIn: appState.userId != null && appState.userId!.isNotEmpty,
    );

    switch (eval.block) {
      case SubmitBlock.fieldError:
        setState(() {
          _autovalidateMode = AutovalidateMode.onUserInteraction;
        });
        _formKey.currentState?.validate();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToField(eval.fieldId!);
        });
        return;
      case SubmitBlock.tenDay:
        _toast(context, CreateEventErrorCopy.tenDay);
        return;
      case SubmitBlock.missingPdf:
        setState(() {
          _pdfError = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToField(_approvalLetterKey);
        });
        return;
      case SubmitBlock.notLoggedIn:
        _toast(context, CreateEventErrorCopy.notLoggedIn);
        return;
      case SubmitBlock.ready:
        break;
    }

    model.submitting = true;

    // Upload cover image first when one was selected.
    String? coverImageUrl;
    String? coverImagePublicId;
    if (_coverImageFile != null) {
      try {
        final upload = await appState.uploadEventCoverToCloudinary(
          _coverImageFile!,
          onProgress: (int sent, int total) {
            if (!mounted || total <= 0) return;
            setState(() => _uploadProgress = sent / total);
          },
        );
        coverImageUrl = upload.url;
        coverImagePublicId = upload.publicId;
      } catch (_) {
        if (mounted) {
          _toast(context, 'Unable to upload cover image. Please try again.');
          model.submitting = false;
          setState(() => _uploadProgress = null);
        }
        return;
      }
    }

    final Event draft = model.buildDraftEvent(
      hostStudentId: appState.userId!,
      today: DateTime.now(),
      coverImageUrl: coverImageUrl,
      coverImagePublicId: coverImagePublicId,
    );
    final Event? created = await appState.createEvent(draft);
    if (!mounted) return;
    if (created == null) {
      _toast(context, 'Unable to submit event. Please try again.');
      model.submitting = false;
      setState(() => _uploadProgress = null);
    } else {
      model.done = true; // leave `submitting` true; button must never re-enable
    }
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (BuildContext context, Widget? child) {
        if (_model.done) {
          return _buildSuccessScreen(context);
        }
        return PopScope(
          canPop: !_model.isDirty && _coverImageFile == null ||
              _model.done ||
              _discardConfirmed,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) {
              _confirmDiscard();
            }
          },
          child: Scaffold(
            backgroundColor: CreateEventTokens.scaffoldColor,
            body: Column(
              children: <Widget>[
                CreateEventHeader(
                  // Route through the same discard guard as Cancel: with
                  // GoRouter 14, a bare `context.pop()` is an imperative pop
                  // that bypasses the PopScope veto, silently discarding a
                  // dirty form. Clean forms still pop directly.
                  onBack: _handleCancel,
                  topInset: MediaQuery.paddingOf(context).top,
                ),
                // The white sheet begins exactly at the header's lower edge —
                // no overlap transform. The header owns all of its spacing,
                // and this single 24 px inner top padding is the only gap
                // between the rounded surface and the first info card.
                Expanded(
                  child: CreateEventSheet(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        CreateEventTokens.contentPaddingHorizontal,
                        CreateEventTokens.spaceXxl,
                        CreateEventTokens.contentPaddingHorizontal,
                        CreateEventTokens.scrollBottomPadding +
                            MediaQuery.viewInsetsOf(context).bottom +
                            MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: CreateEventTokens.contentMaxWidth,
                          ),
                          child: AbsorbPointer(
                            absorbing: _model.submitting,
                            child: Form(
                              key: _formKey,
                              autovalidateMode: _autovalidateMode,
                              child: _buildFormColumn(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormColumn() {
    final CreateEventFormModel model = _model;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const EventInfoCard(variant: EventInfoVariant.approval),
        const SizedBox(height: CreateEventTokens.infoCardGap),
        const EventInfoCard(variant: EventInfoVariant.deadline),
        const SizedBox(height: CreateEventTokens.sectionGapTop),
        const CreateEventSectionHeader(label: 'EVENT DETAILS'),
        const SizedBox(height: CreateEventTokens.sectionGapBottom),
        _titleCard(),
        const SizedBox(height: CreateEventTokens.fieldGap),
        _categoryCard(),
        const SizedBox(height: CreateEventTokens.fieldGap),
        _eventTypeCard(),
        if (model.isClub) ...<Widget>[
          const SizedBox(height: CreateEventTokens.fieldGap),
          _clubIdCard(),
        ],
        if (model.isPaid) ...<Widget>[
          const SizedBox(height: CreateEventTokens.fieldGap),
          _priceCard(),
        ],
        const SizedBox(height: CreateEventTokens.fieldGap),
        _maxParticipantsCard(),
        const SizedBox(height: CreateEventTokens.fieldGap),
        _dateCard(),
        const SizedBox(height: CreateEventTokens.fieldGap),
        _timeCard(),
        const SizedBox(height: CreateEventTokens.fieldGap),
        _locationCard(),
        const SizedBox(height: CreateEventTokens.fieldGap),
        _organizerCard(),
        const SizedBox(height: CreateEventTokens.fieldGap),
        _descriptionCard(),
        const SizedBox(height: CreateEventTokens.sectionGapTop),
        const CreateEventSectionHeader(label: 'COVER IMAGE'),
        const SizedBox(height: CreateEventTokens.sectionGapBottom),
        _coverImageCard(),
        const SizedBox(height: CreateEventTokens.sectionGapTop),
        const CreateEventSectionHeader(label: 'APPROVAL LETTER (PDF)'),
        const SizedBox(height: CreateEventTokens.sectionGapBottom),
        PdfUploadCard(
          key: _fieldKeys[_approvalLetterKey],
          fileName: model.approvalPdf?.name,
          onChoose: _pickApprovalPdf,
          onRemove:
              model.approvalPdf == null ? null : () => model.approvalPdf = null,
          errorText: (_pdfError && model.approvalPdf == null)
              ? CreateEventErrorCopy.approvalLetter
              : null,
        ),
        const SizedBox(height: CreateEventTokens.spaceSm),
        const PdfSecurityNote(),
        const SizedBox(height: CreateEventTokens.spaceXxl),
        CreateEventSubmitButton(
          submitting: model.submitting,
          onPressed: _handleSubmit,
        ),
        const SizedBox(height: CreateEventTokens.spaceMd),
        CreateEventCancelButton(onPressed: _handleCancel),
      ],
    );
  }

  Widget _titleCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.title],
      icon: Icons.title_rounded,
      label: 'Event Title',
      helper: 'Enter a catchy title for your event',
      trailing: CreateEventCounter(
        count: _model.title.characters.length,
        max: 100,
      ),
      child: CreateEventTextField(
        controller: _titleController,
        focusNode: _titleFocus,
        onChanged: (String v) => _model.title = v,
        validator: (String? v) => validateEventTitle(v ?? ''),
        hintText: 'e.g. Tech Talks 2024',
        textInputAction: TextInputAction.next,
        keyboardType: TextInputType.text,
        maxLength: 100,
      ),
    );
  }

  Widget _categoryCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.category],
      icon: Icons.category_outlined,
      label: 'Category',
      helper: 'Select a category',
      child: CreateEventDropdownField(
        value: _model.category,
        items: const <String>['Academic', 'Sport', 'Club', 'General'],
        onChanged: (String? v) => _model.category = v,
        validator: validateCategory,
        focusNode: _categoryFocus,
        semanticsLabel: 'Category, select a category',
      ),
    );
  }

  Widget _eventTypeCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.eventType],
      icon: Icons.groups_outlined,
      label: 'Event Type',
      helper: 'Select event type',
      child: CreateEventDropdownField(
        value: _model.eventType,
        items: const <String>['Open', 'Club', 'Club+Payment', 'Paid'],
        onChanged: (String? v) => _model.eventType = v,
        validator: validateEventType,
        focusNode: _eventTypeFocus,
        semanticsLabel: 'Event type, select an event type',
      ),
    );
  }

  Widget _clubIdCard() {
    return CreateEventFieldCard(
      icon: Icons.card_membership_outlined,
      label: 'Require Club ID',
      trailing: Switch(
        value: _model.clubIdRequired,
        onChanged: (bool v) => _model.clubIdRequired = v,
      ),
    );
  }

  Widget _priceCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.price],
      icon: Icons.payments_outlined,
      label: 'Entry Fee (RM)',
      child: CreateEventTextField(
        controller: _priceController,
        focusNode: _priceFocus,
        onChanged: (String v) => _model.priceText = v,
        validator: (String? v) =>
            validatePrice(text: v ?? '', isPaid: _model.isPaid),
        hintText: '0.00',
        textInputAction: TextInputAction.next,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
    );
  }

  Widget _maxParticipantsCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.maxParticipants],
      icon: Icons.people_outline_rounded,
      label: 'Max Participants',
      helper: 'Enter maximum number of participants',
      child: CreateEventTextField(
        controller: _maxParticipantsController,
        focusNode: _maxParticipantsFocus,
        onChanged: (String v) => _model.maxParticipantsText = v,
        validator: (String? v) => validateMaxParticipants(v ?? ''),
        hintText: '0 = unlimited',
        textInputAction: TextInputAction.next,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
      ),
    );
  }

  Widget _dateCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.date],
      icon: Icons.calendar_today_outlined,
      label: 'Date',
      helper: 'Pick the event date',
      onTap: _pickEventDate,
      semanticsLabel: 'Date, pick the event date',
      child: CreateEventPickerField(
        valueText: _model.eventDate == null
            ? null
            : createEventDateFormat.format(_model.eventDate!),
        placeholder: 'Select event date',
        trailingIcon: Icons.calendar_month_rounded,
        errorText:
            _showErrors ? _model.fieldErrors()[CreateEventFieldIds.date] : null,
      ),
    );
  }

  Widget _timeCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.time],
      icon: Icons.schedule_outlined,
      label: 'Time',
      helper: 'Pick the start time',
      onTap: _pickEventTime,
      semanticsLabel: 'Time, pick the start time',
      child: CreateEventPickerField(
        valueText: _model.timeText,
        placeholder: 'Select start time',
        trailingIcon: Icons.access_time_rounded,
        errorText:
            _showErrors ? _model.fieldErrors()[CreateEventFieldIds.time] : null,
      ),
    );
  }

  Widget _locationCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.location],
      icon: Icons.location_on_outlined,
      label: 'Location',
      helper: 'Add event location',
      child: CreateEventTextField(
        controller: _locationController,
        focusNode: _locationFocus,
        onChanged: (String v) => _model.location = v,
        validator: (String? v) => validateLocation(v ?? ''),
        textInputAction: TextInputAction.next,
        keyboardType: TextInputType.text,
      ),
    );
  }

  Widget _organizerCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.organizer],
      icon: Icons.badge_outlined,
      label: 'Organizer',
      helper: 'Enter organizer or department name',
      child: CreateEventTextField(
        controller: _organizerController,
        focusNode: _organizerFocus,
        onChanged: (String v) => _model.organizer = v,
        validator: (String? v) => validateOrganizer(v ?? ''),
        textInputAction: TextInputAction.next,
        keyboardType: TextInputType.text,
      ),
    );
  }

  Widget _descriptionCard() {
    return CreateEventFieldCard(
      key: _fieldKeys[CreateEventFieldIds.description],
      icon: Icons.notes_rounded,
      label: 'Description',
      helper: 'Provide a detailed description of your event',
      minHeight: CreateEventTokens.descriptionCardMinHeight,
      child: CreateEventTextField(
        controller: _descriptionController,
        focusNode: _descriptionFocus,
        onChanged: (String v) => _model.description = v,
        validator: (String? v) => validateDescription(v ?? ''),
        minLines: 5,
        maxLines: 5,
        textInputAction: TextInputAction.newline,
        keyboardType: TextInputType.multiline,
      ),
    );
  }

  Widget _coverImageCard() {
    final AppState appState = context.read<AppState>();
    return CoverImageUploadCard(
      file: _coverImageFile,
      uploading: _model.submitting && _coverImageFile != null,
      progress: _uploadProgress,
      onPick: () => _pickCoverImage(appState),
      onRemove: _removeCover,
    );
  }

  Widget _buildSuccessScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: CreateEventTokens.scaffoldColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: CreateEventTokens.contentMaxWidth,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: CreateEventTokens.headerGradientStart
                          .withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 48,
                      color: CreateEventTokens.headerGradientStart,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Event Submitted!',
                    style: TextStyle(
                      fontFamily: CreateEventTokens.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: CreateEventTokens.fieldLabelColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your event is pending admin approval.\nWe\'ll notify you when it\'s approved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: CreateEventTokens.fontFamily,
                      fontSize: 13,
                      color: CreateEventTokens.fieldHelperColor,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: CreateEventTokens.primaryButtonHeight,
                    child: ElevatedButton(
                      onPressed: () => context.go('/events'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CreateEventTokens.headerGradientStart,
                        foregroundColor: CreateEventTokens.submitLabelColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            CreateEventTokens.buttonRadius,
                          ),
                        ),
                        textStyle: CreateEventTokens.primaryButtonLabel,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('Back to Events'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
