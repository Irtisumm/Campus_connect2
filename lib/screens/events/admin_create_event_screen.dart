import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Premium admin create/edit event form.
///
/// The screen owns only presentation state and delegates all event writes and
/// image uploads to [AppState]. It is used for both the admin create route and
/// the admin edit route so the two flows cannot drift visually.
class AdminCreateEventScreen extends StatefulWidget {
  final String? id;

  const AdminCreateEventScreen({super.key, this.id});

  @override
  State<AdminCreateEventScreen> createState() => _AdminCreateEventScreenState();
}

class _AdminCreateEventScreenState extends State<AdminCreateEventScreen> {
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _organizerCtrl = TextEditingController();
  final _maxParticipantsCtrl = TextEditingController();
  final _noticeCtrl = TextEditingController();

  String _category = 'Academic';
  bool _loaded = false;
  bool _saving = false;
  bool _removeCoverImage = false;
  File? _coverImageFile;
  String? _coverImageUrl;
  String? _coverImagePublicId;
  double? _uploadProgress;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _locationCtrl.dispose();
    _organizerCtrl.dispose();
    _maxParticipantsCtrl.dispose();
    _noticeCtrl.dispose();
    super.dispose();
  }

  Event? _findEvent(List<Event> events) {
    if (widget.id == null) return null;
    for (final event in events) {
      if (event.id == widget.id) return event;
    }
    return null;
  }

  void _loadEvent(Event event) {
    if (_loaded) return;
    _titleCtrl.text = event.title;
    _descriptionCtrl.text = event.description;
    _dateCtrl.text = event.date;
    _timeCtrl.text = event.time;
    _locationCtrl.text = event.location;
    _organizerCtrl.text = event.organizer;
    _maxParticipantsCtrl.text =
        event.maxParticipants > 0 ? event.maxParticipants.toString() : '';
    _category = event.category;
    _coverImageUrl = event.coverImageUrl;
    _coverImagePublicId = event.coverImagePublicId;
    _loaded = true;
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _formatTime(TimeOfDay value) {
    final hour = value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_dateCtrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: _AdminCreatePalette.pink,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateCtrl.text = _formatDate(picked));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: _AdminCreatePalette.pink,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _timeCtrl.text = _formatTime(picked));
  }

  Future<void> _pickCoverImage(AppState appState) async {
    try {
      final file = await appState.pickEventCoverImage();
      if (file == null || !mounted) return;
      if (await file.length() > 5 * 1024 * 1024) {
        _toast('Please choose an image smaller than 5 MB');
        return;
      }
      setState(() {
        _coverImageFile = file;
        _removeCoverImage = false;
      });
    } catch (error) {
      if (mounted) _toast('Unable to select image: $error');
    }
  }

  void _removeCover() {
    setState(() {
      _coverImageFile = null;
      _removeCoverImage = true;
    });
  }

  Future<void> _savePublished(AppState appState, Event? existing) async {
    if (_saving) return;
    if (_titleCtrl.text.trim().isEmpty) {
      _toast('Title is required');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _uploadProgress = null;
    });

    try {
      String? coverUrl = _removeCoverImage ? null : _coverImageUrl;
      String? coverPublicId = _removeCoverImage ? null : _coverImagePublicId;

      if (_coverImageFile != null) {
        final upload = await appState.uploadEventCoverToCloudinary(
          _coverImageFile!,
          onProgress: (sent, total) {
            if (!mounted || total <= 0) return;
            setState(() => _uploadProgress = sent / total);
          },
        );
        coverUrl = upload.url;
        coverPublicId = upload.publicId;
      }

      if (existing == null) {
        final created = await appState.createEvent(Event(
          id: '',
          title: _titleCtrl.text.trim(),
          category: _category,
          date: _dateCtrl.text.trim(),
          time: _timeCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          organizer: _organizerCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          status: 'Published',
          hostStudentId: appState.userId,
          maxParticipants: int.tryParse(_maxParticipantsCtrl.text.trim()) ?? 0,
          coverImageUrl: coverUrl,
          coverImagePublicId: coverPublicId,
        ));
        if (created == null) throw StateError('Event could not be created');
        final approved = await appState.approveEvent(created.id);
        if (!approved) throw StateError('Event could not be published');
        if (!mounted) return;
        _toast('Event published');
        context.pop();
      } else {
        final updated = existing.copyWith(
          title: _titleCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          date: _dateCtrl.text.trim(),
          time: _timeCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          organizer: _organizerCtrl.text.trim(),
          category: _category,
          status:
              existing.status == 'Published' ? existing.status : 'Published',
          maxParticipants: int.tryParse(_maxParticipantsCtrl.text.trim()) ?? 0,
          coverImageUrl: coverUrl,
          coverImagePublicId: coverPublicId,
        );
        final updatedOk = await appState.updateEvent(updated);
        if (!updatedOk) throw StateError('Event could not be updated');
        if (_removeCoverImage && _coverImageFile == null) {
          final cleared = await appState.clearEventCoverImage(existing.id);
          if (!cleared) throw StateError('Cover image could not be removed');
        }
        if (mounted) _toast('Event updated');
      }
    } catch (error) {
      if (mounted) _toast('Unable to save event: $error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _confirmDelete(AppState appState, Event event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Event',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: Text(
          'Are you sure you want to delete "${event.title}"? This action cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await appState.deleteEvent(event.id);
    if (!mounted) return;
    _toast(ok ? 'Event deleted' : 'Unable to delete event');
    if (ok) context.pop();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) => StreamBuilder<List<Event>>(
        stream: appState.watchAllEvents(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              backgroundColor: _AdminCreatePalette.background,
              body: _AdminCreateStateMessage(
                icon: Icons.cloud_off_rounded,
                title: 'Unable to load events',
                subtitle: 'Please check your connection and try again.',
                onBack: () => context.pop(),
              ),
            );
          }
          if (widget.id != null && !snapshot.hasData) {
            return const Scaffold(
              backgroundColor: _AdminCreatePalette.background,
              body: _AdminCreateLoadingState(),
            );
          }

          final event = _findEvent(snapshot.data ?? const <Event>[]);
          if (widget.id != null && snapshot.hasData && event == null) {
            return Scaffold(
              backgroundColor: _AdminCreatePalette.background,
              body: _AdminCreateStateMessage(
                icon: Icons.event_busy_rounded,
                title: 'Event not found',
                subtitle: 'This event may have been removed or is unavailable.',
                onBack: () => context.pop(),
              ),
            );
          }
          if (event != null) _loadEvent(event);

          final editing = event != null;
          return Scaffold(
            backgroundColor: _AdminCreatePalette.background,
            body: SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  _AdminCreateHeader(
                    editing: editing,
                    onBack: () => context.pop(),
                  ),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        28 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        const _AdminCreateModeCard(),
                        if (editing) ...[
                          const SizedBox(height: 12),
                          _AdminCreateStatusCard(status: event.status),
                        ],
                        const SizedBox(height: 18),
                        _AdminCreateFieldCard(
                          controller: _titleCtrl,
                          icon: Icons.title_rounded,
                          label: 'Title',
                          hint: 'Enter event title',
                        ),
                        const SizedBox(height: 12),
                        _AdminCreateFieldCard(
                          controller: _descriptionCtrl,
                          icon: Icons.subject_rounded,
                          label: 'Description',
                          hint: 'Enter event description',
                          multiline: true,
                        ),
                        const SizedBox(height: 12),
                        _AdminCreateDropdownCard(
                          value: _category,
                          onChanged: (value) =>
                              setState(() => _category = value ?? _category),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _AdminCreatePickerCard(
                                icon: Icons.calendar_month_rounded,
                                label: 'Date',
                                value: _dateCtrl.text,
                                hint: 'Select date',
                                trailingIcon: Icons.calendar_month_outlined,
                                onTap: _pickDate,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _AdminCreatePickerCard(
                                icon: Icons.access_time_rounded,
                                label: 'Time',
                                value: _timeCtrl.text,
                                hint: 'Select time',
                                trailingIcon: Icons.access_time_rounded,
                                onTap: _pickTime,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _AdminCreateFieldCard(
                          controller: _locationCtrl,
                          icon: Icons.location_on_outlined,
                          label: 'Location',
                          hint: 'Enter event location',
                        ),
                        const SizedBox(height: 12),
                        _AdminCreateFieldCard(
                          controller: _organizerCtrl,
                          icon: Icons.person_outline_rounded,
                          label: 'Organizer',
                          hint: 'Enter organizer name',
                        ),
                        const SizedBox(height: 12),
                        _AdminCreateFieldCard(
                          controller: _maxParticipantsCtrl,
                          icon: Icons.groups_rounded,
                          label: 'Max Participants',
                          hint: 'Enter maximum number',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 22),
                        const _AdminCreateSectionTitle(
                          title: 'Event Image',
                          subtitle: 'Upload an image to represent your event',
                        ),
                        const SizedBox(height: 10),
                        _AdminCreateUploadCard(
                          file: _coverImageFile,
                          imageUrl: _coverImageUrl,
                          removed: _removeCoverImage,
                          uploading: _saving && _coverImageFile != null,
                          progress: _uploadProgress,
                          onPick: () => _pickCoverImage(appState),
                          onRemove: _removeCover,
                        ),
                        const SizedBox(height: 22),
                        _AdminCreatePrimaryButton(
                          label: editing
                              ? (event.status == 'Published'
                                  ? 'Update Event'
                                  : 'Publish Event')
                              : 'Publish',
                          icon: Icons.send_rounded,
                          busy: _saving,
                          progress: _uploadProgress,
                          onPressed: () => _savePublished(appState, event),
                        ),
                        if (!editing) ...[
                          const SizedBox(height: 12),
                          _AdminCreateSecondaryButton(
                            label: 'Save as Draft',
                            icon: Icons.save_outlined,
                            onPressed:
                                _saving ? null : () => _toast('Saved as draft'),
                          ),
                        ],
                        if (editing) ...[
                          const SizedBox(height: 26),
                          const _AdminCreateSectionTitle(
                            title: 'Admin Tools',
                            subtitle: 'Manage this event after review',
                          ),
                          const SizedBox(height: 12),
                          if (event.status != 'Completed')
                            _AdminCreateSecondaryButton(
                              label: 'Mark as Completed',
                              icon: Icons.check_circle_outline_rounded,
                              color: const Color(0xFF2E7D32),
                              onPressed: _saving
                                  ? null
                                  : () async {
                                      final ok = await appState
                                          .markEventCompleted(event.id);
                                      if (mounted) {
                                        _toast(ok
                                            ? 'Event marked as completed'
                                            : 'Unable to update event');
                                      }
                                    },
                            ),
                          if (event.status != 'Completed')
                            const SizedBox(height: 12),
                          _AdminCreateFieldCard(
                            controller: _noticeCtrl,
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'Send Notice to Host',
                            hint: 'Type a message to send to the event host',
                            multiline: true,
                          ),
                          const SizedBox(height: 10),
                          _AdminCreateSecondaryButton(
                            label: 'Send Notice',
                            icon: Icons.send_outlined,
                            onPressed: _saving
                                ? null
                                : () async {
                                    if (_noticeCtrl.text.trim().isEmpty) {
                                      _toast('Please enter a notice message');
                                      return;
                                    }
                                    final ok = await appState.addEventMessage(
                                        event.id, _noticeCtrl.text.trim());
                                    if (!mounted) return;
                                    _noticeCtrl.clear();
                                    _toast(ok
                                        ? 'Notice sent to event host'
                                        : 'Unable to send notice');
                                  },
                          ),
                          const SizedBox(height: 12),
                          _AdminCreateSecondaryButton(
                            label: 'Delete Event',
                            icon: Icons.delete_outline_rounded,
                            color: AppTheme.danger,
                            onPressed: _saving
                                ? null
                                : () => _confirmDelete(appState, event),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

abstract final class _AdminCreatePalette {
  static const background = Color(0xFFFFFBFD);
  static const ink = Color(0xFF111A35);
  static const muted = Color(0xFF6A7894);
  static const pink = Color(0xFFD9164F);
  static const pinkBright = Color(0xFFEE3B65);
  static const pinkSoft = Color(0xFFFCEBF1);
  static const pinkBorder = Color(0x25D9164F);
  static const gold = Color(0xFFB87505);
  static const goldSoft = Color(0xFFFFF7E8);
}

class _AdminCreateHeader extends StatelessWidget {
  final bool editing;
  final VoidCallback onBack;

  const _AdminCreateHeader({required this.editing, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFB50945), Color(0xFFEF315F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .35)),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 23),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      editing ? 'Edit Event' : 'Create Event',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      editing
                          ? 'Update the details for this event'
                          : 'Fill in the details to create a new event',
                      maxLines: 2,
                      style: const TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminCreateModeCard extends StatelessWidget {
  const _AdminCreateModeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _AdminCreatePalette.goldSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x35E3A11A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F1C35),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8B5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.shield_rounded,
                color: _AdminCreatePalette.gold, size: 25),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ADMIN MODE',
                    style: TextStyle(
                        color: _AdminCreatePalette.gold,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .3)),
                SizedBox(height: 3),
                Text(
                  'You have full access to create and manage events.',
                  maxLines: 2,
                  style: TextStyle(
                      color: _AdminCreatePalette.muted,
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.workspace_premium_rounded,
              color: Color(0xFFE49A12), size: 30),
        ],
      ),
    );
  }
}

class _AdminCreateStatusCard extends StatelessWidget {
  final String status;

  const _AdminCreateStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AdminCreatePalette.pinkBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: _AdminCreatePalette.muted, size: 18),
          const SizedBox(width: 9),
          const Text('Current status',
              style: TextStyle(
                  color: _AdminCreatePalette.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          StatusBadge(status),
        ],
      ),
    );
  }
}

class _AdminCreateSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _AdminCreateSectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: _AdminCreatePalette.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(subtitle,
            style: const TextStyle(
                color: _AdminCreatePalette.muted,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _AdminCreateFieldCard extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String hint;
  final bool multiline;
  final TextInputType? keyboardType;

  const _AdminCreateFieldCard({
    required this.controller,
    required this.icon,
    required this.label,
    required this.hint,
    this.multiline = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 15, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AdminCreatePalette.pinkBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x070F1C35),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AdminCreateIconTile(icon: icon),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: _AdminCreatePalette.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  minLines: multiline ? 3 : 1,
                  maxLines: multiline ? 5 : 1,
                  keyboardType: keyboardType,
                  textInputAction: multiline
                      ? TextInputAction.newline
                      : TextInputAction.next,
                  style: const TextStyle(
                      color: _AdminCreatePalette.ink,
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    hintText: hint,
                    hintStyle: const TextStyle(
                        color: _AdminCreatePalette.muted,
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminCreateDropdownCard extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  const _AdminCreateDropdownCard(
      {required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AdminCreatePalette.pinkBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x070F1C35),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          const _AdminCreateIconTile(icon: Icons.category_rounded),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Category',
                    style: TextStyle(
                        color: _AdminCreatePalette.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: value,
                    isExpanded: true,
                    isDense: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _AdminCreatePalette.muted, size: 22),
                    style: const TextStyle(
                        color: _AdminCreatePalette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                    items: const ['Academic', 'Sport', 'Club', 'General']
                        .map((item) =>
                            DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminCreatePickerCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final IconData trailingIcon;
  final VoidCallback onTap;

  const _AdminCreatePickerCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.trailingIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(11, 12, 10, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _AdminCreatePalette.pinkBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x070F1C35),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              _AdminCreateIconTile(icon: icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: _AdminCreatePalette.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      value.isEmpty ? hint : value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: value.isEmpty
                              ? _AdminCreatePalette.muted
                              : _AdminCreatePalette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(trailingIcon, color: _AdminCreatePalette.muted, size: 21),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminCreateIconTile extends StatelessWidget {
  final IconData icon;

  const _AdminCreateIconTile({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _AdminCreatePalette.pinkSoft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: _AdminCreatePalette.pink, size: 23),
    );
  }
}

class _AdminCreateUploadCard extends StatelessWidget {
  final File? file;
  final String? imageUrl;
  final bool removed;
  final bool uploading;
  final double? progress;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _AdminCreateUploadCard({
    required this.file,
    required this.imageUrl,
    required this.removed,
    required this.uploading,
    required this.progress,
    required this.onPick,
    required this.onRemove,
  });

  bool get hasPreview =>
      file != null || (!removed && imageUrl != null && imageUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: CustomPaint(
        painter: const _AdminCreateDashedPainter(),
        child: Material(
          color: const Color(0xFFFFF7FA),
          child: InkWell(
            onTap: uploading ? null : onPick,
            child: SizedBox(
              height: 172,
              child: hasPreview ? _preview() : _emptyState(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.cloud_upload_outlined,
            color: _AdminCreatePalette.pink, size: 42),
        SizedBox(height: 9),
        Text('Upload Image',
            style: TextStyle(
                color: _AdminCreatePalette.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('PNG, JPG or WEBP (Max 5MB)',
            style: TextStyle(
                color: _AdminCreatePalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _preview() {
    final image = file != null
        ? Image.file(file!, fit: BoxFit.cover, width: double.infinity)
        : Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: _AdminCreatePalette.muted, size: 38),
            ),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: .58)],
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
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.black.withValues(alpha: .38),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: uploading ? null : onRemove,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 38,
                height: 38,
                child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminCreatePrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final double? progress;
  final VoidCallback onPressed;

  const _AdminCreatePrimaryButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.progress,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: busy
                    ? const [Color(0xFFD88EA7), Color(0xFFE7B4C6)]
                    : const [
                        _AdminCreatePalette.pink,
                        _AdminCreatePalette.pinkBright
                      ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: busy
                  ? const []
                  : const [
                      BoxShadow(
                        color: Color(0x32D9164F),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
            ),
            child: Center(
              child: busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          progress == null
                              ? 'Saving...'
                              : 'Uploading ${(progress! * 100).round()}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 21),
                        const SizedBox(width: 9),
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminCreateSecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _AdminCreateSecondaryButton({
    required this.label,
    required this.icon,
    this.color = _AdminCreatePalette.pink,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: disabled ? color.withValues(alpha: .45) : color,
          backgroundColor: Colors.white,
          side: BorderSide(
              color: disabled ? color.withValues(alpha: .18) : color,
              width: 1.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _AdminCreateLoadingState extends StatelessWidget {
  const _AdminCreateLoadingState();

  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(color: _AdminCreatePalette.pink),
      );
}

class _AdminCreateStateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _AdminCreateStateMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _AdminCreatePalette.pink, size: 50),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _AdminCreatePalette.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _AdminCreatePalette.muted,
                      fontSize: 14,
                      height: 1.4)),
              const SizedBox(height: 18),
              _AdminCreateSecondaryButton(
                label: 'Go Back',
                icon: Icons.arrow_back_rounded,
                onPressed: onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminCreateDashedPainter extends CustomPainter {
  const _AdminCreateDashedPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFED7B9A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(18),
      ));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end =
            (distance + 7) < metric.length ? distance + 7 : metric.length;
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
