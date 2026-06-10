import 'dart:math';

/// Generates a unique journal ID that avoids collisions.
///
/// Uses microseconds since epoch multiplied by 1000 plus a random component
/// to ensure uniqueness even when multiple entries are created in the same millisecond.
/// This replaces the previous approach of using `DateTime.now().millisecondsSinceEpoch`
/// which could produce duplicate IDs for concurrent operations.
int generateUniqueJournalId() {
  final micros = DateTime.now().microsecondsSinceEpoch;
  final random = Random().nextInt(1000);
  return micros * 1000 + random;
}
