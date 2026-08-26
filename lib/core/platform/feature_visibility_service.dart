import 'package:flutter/foundation.dart';
import 'package:firstpro/core/platform/capability_catalog.dart';
import 'package:firstpro/core/platform/capability_visibility_policy.dart';
import 'package:firstpro/data/datasources/repositories/capability_repository.dart';

class FeatureVisibilityService extends ChangeNotifier {
  final CapabilityRepository repository;

  FeatureVisibilityService(this.repository);

  Set<String> _enabledCodes = <String>{};
  bool _isLoading = false;
  String? _errorMessage;

  Set<String> get enabledCodes => Set.unmodifiable(_enabledCodes);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _enabledCodes = await repository.getEnabledCodes();
    } catch (_) {
      _errorMessage = 'تعذر تحميل وظائف البرنامج. حاول مرة أخرى.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool isVisible(Set<String> requiredCapabilities, {required bool isCore}) {
    if (isCore || requiredCapabilities.isEmpty) return true;
    return requiredCapabilities.every(
      (code) => CapabilityVisibilityPolicy.isVisible(code, _enabledCodes),
    );
  }

  bool canDisable(String code) {
    final definition = CapabilityCatalog.byCode(code);
    if (definition.isCore) return false;
    if (!_enabledCodes.contains(code)) return true;

    return !CapabilityCatalog.definitions.any(
      (candidate) =>
          candidate.code != code &&
          _enabledCodes.contains(candidate.code) &&
          candidate.dependencies.contains(code),
    );
  }

  Future<void> setEnabled(String code, bool enabled) async {
    CapabilityCatalog.byCode(code);
    if (!enabled && !canDisable(code)) {
      throw StateError('لا يمكن تعطيل وظيفة تعتمد عليها وظيفة مفعلة');
    }
    await repository.setEnabled(code, enabled, source: 'settings');
    _enabledCodes = await repository.getEnabledCodes();
    notifyListeners();
  }
}
