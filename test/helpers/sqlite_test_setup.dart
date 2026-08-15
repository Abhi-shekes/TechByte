import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

/// Points the sqlite3 FFI loader at the system library for host-VM tests.
///
/// On device, `sqlite3_flutter_libs` bundles the native library. Dart unit
/// tests run on the host instead, where the loader looks for a bare
/// `libsqlite3.so` — a symlink that only ships in the `-dev` package. Most
/// Linux machines and CI images have the versioned `libsqlite3.so.0` but not
/// the symlink, so tests fail on a missing file rather than anything real.
///
/// Call from `setUpAll` in any test that opens a database.
void configureSqliteForTests() {
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, _openLinux);
  } else if (Platform.isMacOS) {
    open.overrideFor(OperatingSystem.macOS, _openMacOs);
  }
}

DynamicLibrary _openLinux() {
  for (final candidate in ['libsqlite3.so', 'libsqlite3.so.0']) {
    try {
      return DynamicLibrary.open(candidate);
    } on ArgumentError {
      continue;
    }
  }
  throw StateError(
    'Could not load sqlite3. Install it with: sudo apt-get install libsqlite3-0',
  );
}

DynamicLibrary _openMacOs() => DynamicLibrary.open('/usr/lib/libsqlite3.dylib');
