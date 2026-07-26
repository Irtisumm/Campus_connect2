import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ReleaseStepper extends StatelessWidget {
  final String status;

  const ReleaseStepper({super.key, required this.status});

  static const _steps = ['Requested', 'Pending Return', 'Returned', 'Completed'];

  int _currentIndex() {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'release requested') return 0;
    if (normalized == 'requested') return 0;
    if (normalized == 'pending return') return 1;
    if (normalized == 'returned') return 2;
    if (normalized == 'completed') return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          children: List.generate(_steps.length, (index) {
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
                    if (index != _steps.length - 1)
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
                      _steps[index],
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
