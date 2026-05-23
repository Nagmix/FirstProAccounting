// Compatibility layer for Flutter 3.44+ where IconData is final.

import 'package:flutter/widgets.dart';

/// PhosphorIconData is now just an alias for IconData.
// Note: We can't use typedef for non-function types in library-mode Dart.
// Instead, we just use IconData directly everywhere.
