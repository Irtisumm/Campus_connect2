import 'item.dart';

/// One row of the Notifications screen.
///
/// There is no `notifications` collection in Firestore — `firestore.rules`
/// governs only `users` and `items`, and Firestore is default-deny, so a new
/// collection could be neither read nor written. Notifications are therefore
/// *derived* from the reports the caller may already see: every report is one
/// row, and because the underlying query is a live snapshot, a status change
/// re-emits its row without a refresh.
///
/// This is a plain view model, not a document — it is built in [AppState] from
/// an [Item] and never written anywhere. Named `AppNotification` because both
/// `mock_data.dart` and the Flutter framework already export a `Notification`.
class AppNotification {
  /// The source report's Firestore document ID. Doubles as the row identity
  /// the screen keys its read-state off.
  final String id;

  /// The headline the row displays.
  final String text;

  /// When the report last changed — `updatedAt`, or `createdAt` for a report
  /// that has never been touched since submission. Formatting is left to the
  /// screen so it can reuse the same `relativeTime` helper as every other
  /// Lost & Found list.
  final DateTime? at;

  const AppNotification({required this.id, required this.text, this.at});

  /// The row a student sees for their own report.
  factory AppNotification.forOwner(Item item) {
    final kind = item.isLost ? 'lost' : 'found';
    final String text;
    switch (item.status) {
      case ItemStatus.active:
        text = 'Your $kind report “${item.title}” is active.';
      case ItemStatus.awaitingHandover:
        text = 'Your found report “${item.title}” is awaiting handover — '
            'please bring the item to the Inventory Office.';
      case ItemStatus.matchedPending:
        text = 'A possible match is pending for “${item.title}”.';
      case ItemStatus.inInventory:
        text = 'Your found report “${item.title}” is in inventory.';
      case ItemStatus.resolved:
        text = 'Your $kind report “${item.title}” was resolved.';
      case ItemStatus.returned:
        text = 'Your found item “${item.title}” was returned to its owner.';
      case ItemStatus.closed:
        text = 'Your $kind report “${item.title}” was closed.';
    }
    return AppNotification(id: item.id, text: text, at: _stamp(item));
  }

  /// The row an admin sees — the same report, attributed to its reporter.
  factory AppNotification.forAdmin(Item item) {
    final kind = item.isLost ? 'lost' : 'found';
    return AppNotification(
      id: item.id,
      text: '${item.reportedByStudentId} reported a $kind item: '
          '“${item.title}” (${item.status.wireValue}).',
      at: _stamp(item),
    );
  }

  static DateTime? _stamp(Item item) => item.updatedAt ?? item.createdAt;
}
