import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/date_formatter.dart';
import 'package:firstpro/core/utils/movement_sorter.dart';

/// ══════════════════════════════════════════════════════════════════
/// B-1 — اختبارات الفرز الزمني الموحد (A-1 / A-5)
///
/// السيناريو الأصلي المُبلغ من المالك: قيد افتتاحي (timestamp كامل)
/// ثم سند قبض لاحق (يوم-فقط) في نفس اليوم — كان السند يظهر فوق
/// القيد الافتتاحي والرصيد التراكمي يُحسب خطأً.
/// ══════════════════════════════════════════════════════════════════

Map<String, dynamic> mv(String id, String date, String createdAt,
        {double debit = 0, double credit = 0}) =>
    {
      'id': id,
      'date': date,
      'created_at': createdAt,
      'debit': debit,
      'credit': credit,
    };

void main() {
  group('MovementSorter.dayOf', () {
    test('extracts day from full timestamp', () {
      expect(MovementSorter.dayOf('2026-06-10T08:30:45.123456'), '2026-06-10');
    });
    test('passes through day-only values', () {
      expect(MovementSorter.dayOf('2026-06-10'), '2026-06-10');
    });
    test('handles null and empty safely', () {
      expect(MovementSorter.dayOf(null), '');
      expect(MovementSorter.dayOf(''), '');
    });
  });

  group('MovementSorter — the reported bug scenario', () {
    test(
        'opening balance (full timestamp) stays BEFORE a later day-only voucher '
        'on the same day', () {
      // القيد الافتتاحي أُنشئ 08:30 بصيغة كاملة
      final opening = mv(
        'ob_1',
        '2026-06-10T08:30:45.123456',
        '2026-06-10T08:30:45.123456',
        credit: 1000,
      );
      // سند القبض أُنشئ لاحقاً 10:15 لكن date خُزن يوم-فقط (البيانات القديمة)
      final voucher = mv(
        'v_1',
        '2026-06-10',
        '2026-06-10T10:15:00.000000',
        credit: 500,
      );

      // قبل الإصلاح: المقارنة النصية كانت تضع 'v_1' قبل 'ob_1'
      final movements = [voucher, opening];
      MovementSorter.sortChronologically(movements);

      expect(movements.first['id'], 'ob_1',
          reason: 'القيد الافتتاحي (08:30) يجب أن يسبق السند (10:15) '
              'رغم اختلاف صيغتي التاريخ');
      expect(movements.last['id'], 'v_1');
    });

    test('running balance is computed in true chronological order', () {
      final movements = [
        mv('v_1', '2026-06-10', '2026-06-10T10:15:00', debit: 300),
        mv('ob_1', '2026-06-10T08:30:45', '2026-06-10T08:30:45', credit: 1000),
        mv('v_2', '2026-06-10', '2026-06-10T14:00:00', credit: 200),
      ];
      MovementSorter.sortChronologically(movements);

      double running = 0;
      final balances = <String, double>{};
      for (final m in movements) {
        running += (m['credit'] as double) - (m['debit'] as double);
        balances[m['id'] as String] = running;
      }

      // الترتيب الصحيح: ob_1 (08:30) → v_1 (10:15) → v_2 (14:00)
      expect(movements.map((m) => m['id']).toList(), ['ob_1', 'v_1', 'v_2']);
      expect(balances['ob_1'], 1000);
      expect(balances['v_1'], 700);
      expect(balances['v_2'], 900);
    });
  });

  group('MovementSorter — general ordering', () {
    test('different days sort by day regardless of format mix', () {
      final movements = [
        mv('c', '2026-06-12T01:00:00', '2026-06-12T01:00:00'),
        mv('a', '2026-06-10', '2026-06-10T23:59:00'),
        mv('b', '2026-06-11T05:00:00', '2026-06-11T05:00:00'),
      ];
      MovementSorter.sortChronologically(movements);
      expect(movements.map((m) => m['id']).toList(), ['a', 'b', 'c']);
    });

    test('same day + same format orders by created_at', () {
      final movements = [
        mv('late', '2026-06-10', '2026-06-10T16:00:00'),
        mv('early', '2026-06-10', '2026-06-10T09:00:00'),
        mv('mid', '2026-06-10', '2026-06-10T12:00:00'),
      ];
      MovementSorter.sortChronologically(movements);
      expect(movements.map((m) => m['id']).toList(), ['early', 'mid', 'late']);
    });

    test('descending view = reversed ascending (screen behavior)', () {
      final movements = [
        mv('ob', '2026-06-10T08:00:00', '2026-06-10T08:00:00'),
        mv('v1', '2026-06-10', '2026-06-10T11:00:00'),
      ];
      MovementSorter.sortChronologically(movements);
      final descending = movements.reversed.toList();
      expect(descending.first['id'], 'v1',
          reason: 'في الفرز التنازلي الأحدث يظهر أولاً');
    });

    test('custom dateKey (expense_date) with created_at fallback', () {
      final expenses = [
        {
          'id': 'e2',
          'expense_date': '2026-06-11',
          'created_at': '2026-06-11T10:00:00',
        },
        {
          'id': 'e1',
          'expense_date': null, // يسقط على created_at
          'created_at': '2026-06-10T09:00:00',
        },
      ];
      MovementSorter.sortChronologically(expenses, dateKey: 'expense_date');
      expect(expenses.map((m) => m['id']).toList(), ['e1', 'e2']);
    });

    test('legacy mixed data needs no migration to sort correctly', () {
      // خليط: فواتير (كاملة) + سندات قديمة (يوم-فقط) + سندات جديدة (كاملة)
      final movements = [
        mv('new_voucher', '2026-06-10T15:30:00', '2026-06-10T15:30:00'),
        mv('old_voucher', '2026-06-10', '2026-06-10T11:00:00'),
        mv('invoice', '2026-06-10T09:45:00.500', '2026-06-10T09:45:00.500'),
      ];
      MovementSorter.sortChronologically(movements);
      expect(movements.map((m) => m['id']).toList(),
          ['invoice', 'old_voucher', 'new_voucher']);
    });
  });

  group('DateFormatter.storageTimestamp (A-5 root fix)', () {
    test('combines selected day with current time', () {
      final selected = DateTime(2026, 6, 8); // يوم ماضٍ اختاره المستخدم
      final fakeNow = DateTime(2026, 6, 10, 14, 25, 30, 123, 456);
      final result = DateFormatter.storageTimestamp(selected, now: fakeNow);
      final parsed = DateTime.parse(result);

      expect(parsed.year, 2026);
      expect(parsed.month, 6);
      expect(parsed.day, 8, reason: 'اليوم المحاسبي = اختيار المستخدم');
      expect(parsed.hour, 14, reason: 'الوقت = لحظة الحفظ الفعلية');
      expect(parsed.minute, 25);
      expect(parsed.second, 30);
    });

    test('produces a full timestamp (not day-only)', () {
      final result = DateFormatter.storageTimestamp(DateTime(2026, 6, 10));
      expect(result.contains('T'), isTrue);
      expect(MovementSorter.dayOf(result), '2026-06-10');
    });

    test('two vouchers saved same day keep insertion order when sorted', () {
      final day = DateTime(2026, 6, 10);
      final first = DateFormatter.storageTimestamp(day,
          now: DateTime(2026, 6, 10, 9, 0, 0));
      final second = DateFormatter.storageTimestamp(day,
          now: DateTime(2026, 6, 10, 9, 5, 0));

      final movements = [
        mv('second', second, second),
        mv('first', first, first),
      ];
      MovementSorter.sortChronologically(movements);
      expect(movements.map((m) => m['id']).toList(), ['first', 'second']);
    });
  });
}
