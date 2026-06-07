import 'package:sqflite_sqlcipher/sqflite.dart';
import 'migration_v2_to_v10.dart';
import 'migration_v11_to_v20.dart';
import 'migration_v21_to_v30.dart';
import 'migration_v31_to_v43.dart';
import 'migration_v44_to_v44.dart';
import 'migration_v44_to_v45.dart';
import 'migration_v46.dart';
import 'migration_v47.dart';
import 'migration_v48.dart';

class MigrationRunner {
  /// Runs all necessary migrations from oldVersion to the current version.
  /// The order of migrations must be preserved exactly as-is.
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2–v10
    if (oldVersion < 2) await MigrationV2ToV10.migrateV2(db);
    if (oldVersion < 3) await MigrationV2ToV10.migrateV3(db);
    if (oldVersion < 4) await MigrationV2ToV10.migrateV4(db);
    if (oldVersion < 5) await MigrationV2ToV10.migrateV5(db);
    if (oldVersion < 6) await MigrationV2ToV10.migrateV6(db);
    if (oldVersion < 7) await MigrationV2ToV10.migrateV7(db);
    if (oldVersion < 8) await MigrationV2ToV10.migrateV8(db);
    if (oldVersion < 9) await MigrationV2ToV10.migrateV9(db);
    if (oldVersion < 10) await MigrationV2ToV10.migrateV10(db);

    // v11–v20
    if (oldVersion < 11) await MigrationV11ToV20.migrateV11(db);
    if (oldVersion < 12) await MigrationV11ToV20.migrateV12(db);
    if (oldVersion < 13) await MigrationV11ToV20.migrateV13(db);
    if (oldVersion < 14) await MigrationV11ToV20.migrateV14(db);
    if (oldVersion < 15) await MigrationV11ToV20.migrateV15(db);
    if (oldVersion < 16) await MigrationV11ToV20.migrateV16(db);
    if (oldVersion < 17) await MigrationV11ToV20.migrateV17(db);
    if (oldVersion < 18) await MigrationV11ToV20.migrateV18(db);
    if (oldVersion < 19) await MigrationV11ToV20.migrateV19(db);
    if (oldVersion < 20) await MigrationV11ToV20.migrateV20(db);

    // v21–v30
    if (oldVersion < 21) await MigrationV21ToV30.migrateV21(db);
    if (oldVersion < 22) await MigrationV21ToV30.migrateV22(db);
    if (oldVersion < 23) await MigrationV21ToV30.migrateV23(db);
    if (oldVersion < 24) await MigrationV21ToV30.migrateV24(db);
    if (oldVersion < 25) await MigrationV21ToV30.migrateV25(db);
    if (oldVersion < 26) await MigrationV21ToV30.migrateV26(db);
    if (oldVersion < 27) await MigrationV21ToV30.migrateV27(db);
    if (oldVersion < 28) await MigrationV21ToV30.migrateV28(db);
    if (oldVersion < 29) await MigrationV21ToV30.migrateV29(db);
    if (oldVersion < 30) await MigrationV21ToV30.migrateV30(db);

    // v31–v43
    if (oldVersion < 31) await MigrationV31ToV43.migrateV31(db);
    if (oldVersion < 32) await MigrationV31ToV43.migrateV32(db);
    if (oldVersion < 33) await MigrationV31ToV43.migrateV33(db);
    if (oldVersion < 34) await MigrationV31ToV43.migrateV34(db);
    if (oldVersion < 35) await MigrationV31ToV43.migrateV35(db);
    if (oldVersion < 36) await MigrationV31ToV43.migrateV36(db);
    if (oldVersion < 37) await MigrationV31ToV43.migrateV37(db);
    if (oldVersion < 38) await MigrationV31ToV43.migrateV38(db);
    if (oldVersion < 39) await MigrationV31ToV43.migrateV39(db);
    if (oldVersion < 40) await MigrationV31ToV43.migrateV40(db);
    if (oldVersion < 41) await MigrationV31ToV43.migrateV41(db);
    if (oldVersion < 42) await MigrationV31ToV43.migrateV42(db);
    if (oldVersion < 43) await MigrationV31ToV43.migrateV43(db);

    // v44 — License system
    if (oldVersion < 44) await MigrationV44.migrate(db);

    // v45 — Expense sub-accounts
    if (oldVersion < 45) await MigrationV45.migrate(db);

    // v46 — Accounting integrity columns for transactions table
    if (oldVersion < 46) await MigrationV46.migrate(db);

    // v47 — Add employee_id column to vouchers table
    if (oldVersion < 47) await MigrationV47.migrate(db);

    // v48 — Ensure employee_id column exists in vouchers table (safety net for fresh v47 installs)
    if (oldVersion < 48) await MigrationV48.migrate(db);
  }
}
