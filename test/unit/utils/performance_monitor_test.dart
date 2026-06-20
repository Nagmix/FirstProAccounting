import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/performance_monitor.dart';

/// AR-05: unit tests for PerformanceMonitor.
void main() {
  group('PerformanceMonitor', () {
    setUp(() {
      PerformanceMonitor.clear();
    });

    test('start/end records a performance entry', () {
      final key = PerformanceMonitor.start('test-op');
      expect(key, 'test-op');
      // Simulate some work.
      final sum = List.generate(1000, (i) => i).reduce((a, b) => a + b);
      expect(sum, 499500);
      PerformanceMonitor.end('test-op');

      final records = PerformanceMonitor.records;
      expect(records, hasLength(1));
      expect(records.first.name, 'test-op');
      expect(records.first.elapsedMs, greaterThanOrEqualTo(0));
    });

    test('track wraps async operation with timing', () async {
      final result = await PerformanceMonitor.track('async-op', () async {
        await Future.delayed(const Duration(milliseconds: 10));
        return 42;
      });

      expect(result, 42);
      final records = PerformanceMonitor.records;
      expect(records, hasLength(1));
      expect(records.first.name, 'async-op');
      expect(records.first.elapsedMs, greaterThanOrEqualTo(8),
          reason: 'Should take at least 8ms (10ms delay - margin).');
    });

    test('trackSync wraps sync operation with timing', () {
      final result = PerformanceMonitor.trackSync('sync-op', () {
        return List.generate(1000, (i) => i * 2).reduce((a, b) => a + b);
      });

      expect(result, 999000);
      expect(PerformanceMonitor.records, hasLength(1));
      expect(PerformanceMonitor.records.first.name, 'sync-op');
    });

    test('track still returns result even if operation throws', () async {
      expect(
        () => PerformanceMonitor.track('failing-op', () async {
          throw Exception('test error');
        }),
        throwsException,
      );
    });

    test('getSlowestOperations returns sorted by elapsed time', () {
      for (var i = 0; i < 5; i++) {
        PerformanceMonitor.start('op-$i');
        PerformanceMonitor.end('op-$i');
      }

      final slowest = PerformanceMonitor.getSlowestOperations(count: 3);
      expect(slowest.length, lessThanOrEqualTo(3));
    });

    test('clear removes all records', () {
      PerformanceMonitor.start('a');
      PerformanceMonitor.end('a');
      expect(PerformanceMonitor.records, hasLength(1));

      PerformanceMonitor.clear();
      expect(PerformanceMonitor.records, isEmpty);
    });

    test('records list is unmodifiable', () {
      PerformanceMonitor.start('test');
      PerformanceMonitor.end('test');

      final records = PerformanceMonitor.records;
      expect(() => records.add(PerformanceRecord(name: 'x', elapsedMs: 0)),
          throwsUnsupportedError);
    });
  });

  group('PerformanceRecord', () {
    test('has name, elapsedMs, and timestamp', () {
      final record = PerformanceRecord(name: 'test', elapsedMs: 42);
      expect(record.name, 'test');
      expect(record.elapsedMs, 42);
      expect(record.timestamp, isNotNull);
    });

    test('toString includes name and elapsedMs', () {
      final record = PerformanceRecord(name: 'my-op', elapsedMs: 123);
      expect(record.toString(), contains('my-op'));
      expect(record.toString(), contains('123'));
    });
  });
}
