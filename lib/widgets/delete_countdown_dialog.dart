import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Destructive-action confirmation dialog with a short countdown.
///
/// The confirm button stays disabled until the countdown reaches zero, so an
/// irreversible action (e.g. archiving an election) can never be triggered by
/// an accidental tap. Returns `true` when the caller confirms, `null` when
/// cancelled or dismissed. The timer is torn down on every exit path — closing
/// and reopening the dialog always starts a fresh countdown, and there is no
/// way to bypass the wait via UI state.
Future<bool?> showArchiveCountdownDialog(
  BuildContext context, {
  required String itemName,
  required String warning,
  int countdownSeconds = 3,
  String confirmLabel = 'Archive Election',
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogCtx) => _CountdownDialog(
      itemName: itemName,
      warning: warning,
      countdownSeconds: countdownSeconds,
      confirmLabel: confirmLabel,
    ),
  );
}

class _CountdownDialog extends StatefulWidget {
  final String itemName;
  final String warning;
  final int countdownSeconds;
  final String confirmLabel;

  const _CountdownDialog({
    required this.itemName,
    required this.warning,
    required this.countdownSeconds,
    required this.confirmLabel,
  });

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Non-positive counts start enabled — there is nothing to wait for.
    _remaining = widget.countdownSeconds > 0 ? widget.countdownSeconds : 0;
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    }
  }

  void _tick(Timer timer) {
    if (_remaining <= 1) {
      timer.cancel();
      _timer = null;
    }
    setState(() => _remaining = _remaining > 0 ? _remaining - 1 : 0);
  }

  @override
  void dispose() {
    // The countdown must not survive the dialog: cancel on every exit path so
    // a dismissed-then-reopened dialog always restarts from the full duration.
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counting = _remaining > 0;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Archive Election?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.itemName,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text(widget.warning,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5)),
          if (counting) ...[
            const SizedBox(height: 12),
            Text('Please wait $_remaining seconds…',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: counting ? null : () => Navigator.pop(context, true),
          child: Text(
            counting ? 'Please wait ${_remaining}s…' : widget.confirmLabel,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
