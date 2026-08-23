import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release workflow must fail when APK or AAB signing cannot be verified', () {
    final workflow = File('.github/workflows/android-release.yml').readAsStringSync();

    expect(workflow, contains('verify --verbose --print-certs'));
    expect(workflow, contains('jarsigner -verify -verbose -certs'));
    expect(workflow, isNot(contains('WARNING: Could not verify APK signing')));
    expect(workflow, isNot(contains('Could not extract fingerprints')));
    expect(workflow, contains('actions/checkout@v7'));
    expect(workflow, contains('actions/setup-java@v5'));
    expect(workflow, contains('actions/upload-artifact@v7'));
  });
}
