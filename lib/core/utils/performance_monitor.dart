import 'package:flutter/foundation.dart';

/// AR-05: Lightweight performance monitoring utility.
///
/// Provides stopwatch-based timing for critical operations. Timings are
/// logged in debug mode only (no overhead in release builds).
///
/// Usage:
/// ```dart
/// final timer = PerformanceMonitor.start('saveInvoice');
/// await invoiceRepo.saveInvoiceWithJournalEntries(...);
/// PerformanceMonitor.end(timer);
/// ```
///
/// Or with automatic try/catch:
/// ```dart
/// await PerformanceMonitor.track('processDueTemplates', () async {
///   await service.processDueTemplates();
/// });
/// ```
class PerformanceMonitor {
  PerformanceMonitor._();

  static final Map<String, Stopwatch> _activeTimers = {};
  static final List<PerformanceRecord> _records = [];
  static const int _maxRecords = 100;

  /// Start a named timer. Returns the key to pass to [end].
  static String start(String name) {
    if (!kDebugMode) return name;
    final sw = Stopwatch()..start();
    _activeTimers[name] = sw;
    return name;
  }

  /// End a named timer and log the elapsed time.
  static void end(String name) {
    if (!kDebugMode) return;
    final sw = _activeTimers.remove(name);
    if (sw == null) return;
    sw.stop();
    final elapsedMs = sw.elapsedMilliseconds;
    _addRecord(PerformanceRecord(name: name, elapsedMs: elapsedMs));
    if (elapsedMs > 100) {
      debugPrint('⚡ PerformanceMonitor: "$name" took ${elapsedMs}ms');
    }
  }

  /// Track an async operation with automatic timing.
  static Future<T> track<T>(String name, Future<T> Function() operation) async {
    if (!kDebugMode) return await operation();
    start(name);
    try {
      return await operation();
    } finally {
      end(name);
    }
  }

  /// Track a sync operation with automatic timing.
  static T trackSync<T>(String name, T Function() operation) {
    if (!kDebugMode) return operation();
    start(name);
    try {
      return operation();
    } finally {
      end(name);
    }
  }

  /// Get all recorded performance entries (debug mode only).
  static List<PerformanceRecord> get records {
    if (!kDebugMode) return const [];
    return List.unmodifiable(_records);
  }

  /// Get the slowest N operations.
  static List<PerformanceRecord> getSlowestOperations({int count = 10}) {
    if (!kDebugMode) return const [];
    final sorted = List<PerformanceRecord>.from(_records)
      ..sort((a, b) => b.elapsedMs.compareTo(a.elapsedMs));
    return sorted.take(count).toList();
  }

  /// Clear all records.
  static void clear() {
    _records.clear();
    _activeTimers.clear();
  }

  /// Log a summary of the slowest operations.
  static void logSummary() {
    if (!kDebugMode) return;
    final slowest = getSlowestOperations(count: 5);
    if (slowest.isEmpty) return;
    debugPrint('⚡ PerformanceMonitor — Top 5 slowest operations:');
    for (final r in slowest) {
      debugPrint('  ${r.name}: ${r.elapsedMs}ms');
    }
  }

  static void _addRecord(PerformanceRecord record) {
    _records.add(record);
    if (_records.length > _maxRecords) {
      _records.removeAt(0);
    }
  }
}

/// A single performance measurement record.
class PerformanceRecord {
  final String name;
  final int elapsedMs;
  final DateTime timestamp;

  PerformanceRecord({
    required this.name,
    required this.elapsedMs,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'PerformanceRecord($name: ${elapsedMs}ms)';
}
