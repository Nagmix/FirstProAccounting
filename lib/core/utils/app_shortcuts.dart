import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// U-04 Phase 2: Centralized keyboard shortcuts and focus traversal
/// helpers for the app.
///
/// Provides:
///   - [AppShortcuts.wrap]: wraps a widget with common keyboard shortcuts
///     (save, search, refresh, escape) that map to callbacks.
///   - [FocusTraversalGroup]: wraps form sections for logical Tab/Shift+Tab
///     navigation order.
///
/// Usage in a screen:
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   return AppShortcuts.wrap(
///     onSave: _save,
///     onSearch: _focusSearch,
///     onRefresh: _loadData,
///     child: Scaffold(...),
///   );
/// }
/// ```
class AppShortcuts {
  AppShortcuts._();

  /// Wrap a child widget with common keyboard shortcuts.
  ///
  /// All callbacks are optional — only the ones provided will be active.
  /// Shortcuts are active when the wrapped widget or any descendant has
  /// focus.
  ///
  /// Shortcuts:
  ///   - Ctrl+S → onSave (حفظ)
  ///   - Ctrl+F → onSearch (بحث)
  ///   - Ctrl+R → onRefresh (تحديث)
  ///   - Escape → onEscape (إغلاق/رجوع)
  ///   - Ctrl+P → onPrint (طباعة)
  static Widget wrap({
    VoidCallback? onSave,
    VoidCallback? onSearch,
    VoidCallback? onRefresh,
    VoidCallback? onEscape,
    VoidCallback? onPrint,
    required Widget child,
  }) {
    final shortcuts = <ShortcutActivator, Intent>{};

    if (onSave != null) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyS, control: true)] =
          const SaveIntent();
    }
    if (onSearch != null) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyF, control: true)] =
          const SearchIntent();
    }
    if (onRefresh != null) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyR, control: true)] =
          const RefreshIntent();
    }
    if (onEscape != null) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.escape)] =
          const EscapeIntent();
    }
    if (onPrint != null) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyP, control: true)] =
          const PrintIntent();
    }

    if (shortcuts.isEmpty) return child;

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          if (onSave != null)
            SaveIntent: CallbackAction<SaveIntent>(onInvoke: (_) => onSave!()),
          if (onSearch != null)
            SearchIntent:
                CallbackAction<SearchIntent>(onInvoke: (_) => onSearch!()),
          if (onRefresh != null)
            RefreshIntent:
                CallbackAction<RefreshIntent>(onInvoke: (_) => onRefresh!()),
          if (onEscape != null)
            EscapeIntent:
                CallbackAction<EscapeIntent>(onInvoke: (_) => onEscape!()),
          if (onPrint != null)
            PrintIntent:
                CallbackAction<PrintIntent>(onInvoke: (_) => onPrint!()),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }

  /// Wrap a form section with OrderedTraversalPolicy for logical Tab order.
  ///
  /// Use this around groups of form fields (e.g., basic info section,
  /// pricing section) so Tab/Shift+Tab navigates within the section
  /// before moving to the next.
  static Widget formSection({required Widget child}) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: child,
    );
  }
}

// ── Custom Intents ──────────────────────────────────────────────────

class SaveIntent extends Intent {
  const SaveIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class RefreshIntent extends Intent {
  const RefreshIntent();
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}

class PrintIntent extends Intent {
  const PrintIntent();
}
