import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A vertical stepper that visualises the locker release pipeline.
///
/// Two variants are supported, selected by [lockType]:
/// - **key**: Requested → Approved → Return QR Generated → Key Returned →
///   Deposit Refunded → Completed
/// - **digital**: Requested → Approved → Deposit Refunded → Completed
///
/// The current step is derived from [status] (the booking's `releaseStatus`)
/// and the companion flags [keyReturnGenerated] / [keyReturned].
class ReleaseStepper extends StatelessWidget {
  final String status;
  final String lockType;
  final bool keyReturnGenerated;
  final bool keyReturned;

  const ReleaseStepper({
    super.key,
    required this.status,
    this.lockType = 'key',
    this.keyReturnGenerated = false,
    this.keyReturned = false,
  });

  List<String> get _steps {
    if (lockType == 'digital') {
      return ['Requested', 'Approved', 'Deposit Refunded', 'Completed'];
    }
    return [
      'Requested',
      'Approved',
      'Return QR Generated',
      'Key Returned',
      'Deposit Refunded',
      'Completed',
    ];
  }

  int _currentIndex() {
    final s = status.trim().toLowerCase();
    if (lockType == 'digital') {
      // Digital: Requested → Approved → Deposit Refunded → Completed
      if (s == 'requested') return 0;
      if (s == 'approved') return 1;
      if (s == 'completed') return 3;
      // 'Returned' or 'Pending Return' should not happen for digital, but
      // if they do, treat as approved (step 1).
      return 1;
    }
    // Key: Requested → Approved → Return QR Generated → Key Returned →
    // Deposit Refunded → Completed
    if (s == 'requested') return 0;
    if (s == 'approved') return 1;
    if (s == 'pending return') return keyReturnGenerated ? 2 : 1;
    if (s == 'returned') return keyReturned ? 3 : 2;
    if (s == 'completed') return 5;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex();
    final steps = _steps;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          children: List.generate(steps.length, (index) {
            final isDone = index < current;
            final isActive = index == current;
            final color = isDone || isActive ? AppTheme.red : AppTheme.textMuted;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isDone || isActive ? AppTheme.red.withOpacity(0.12) : Colors.grey.withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDone || isActive ? AppTheme.red : Colors.grey.withOpacity(0.5),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          isDone ? Icons.check_rounded : (isActive ? Icons.radio_button_checked_rounded : Icons.circle_outlined),
                          size: 14,
                          color: color,
                        ),
                      ),
                    ),
                    if (index != steps.length - 1)
                      Container(
                        width: 2,
                        height: 20,
                        color: index < current ? AppTheme.red.withOpacity(0.6) : Colors.grey.withOpacity(0.4),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      steps[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
