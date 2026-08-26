import 'package:flutter/foundation.dart';
import 'package:firstpro/core/platform/capability_catalog.dart';
import 'package:firstpro/data/datasources/repositories/business_profile_repository.dart';
import 'package:firstpro/data/datasources/repositories/capability_repository.dart';
import 'package:firstpro/data/models/business_profile_model.dart';

class OnboardingViewModel extends ChangeNotifier {
  final BusinessProfileRepository profileRepository;
  final CapabilityRepository capabilityRepository;

  OnboardingViewModel({
    required this.profileRepository,
    required this.capabilityRepository,
  });

  BusinessProfile? _profile;
  final Set<String> _selectedCapabilities = <String>{};
  bool _isLoading = false;
  bool _isSaving = false;
  bool _needsOnboarding = false;
  String? _errorMessage;
  String _businessName = '';

  BusinessProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get needsOnboarding => _needsOnboarding;
  String? get errorMessage => _errorMessage;
  String get businessName => _businessName;
  String get countryCode => _profile?.countryCode ?? 'YE';
  String get baseCurrencyCode => _profile?.baseCurrencyCode ?? 'YER';
  Set<String> get selectedCapabilities => Set.unmodifiable(_selectedCapabilities);

  bool get canSave =>
      !_isLoading &&
      !_isSaving &&
      _businessName.trim().isNotEmpty &&
      _selectedCapabilities.isNotEmpty;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _profile = await profileRepository.getOrCreateProfile();
      _businessName = _profile?.businessName ?? '';
      _selectedCapabilities
        ..clear()
        ..addAll(await capabilityRepository.getEnabledCodes());
      _needsOnboarding = _profile?.source == 'migration' &&
          _profile?.setupStatus != 'completed';
    } catch (error) {
      _errorMessage = 'تعذر تحميل إعدادات البداية. حاول مرة أخرى.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setBusinessName(String value) {
    _businessName = value;
    notifyListeners();
  }

  void toggleCapability(String code, bool selected) {
    CapabilityCatalog.byCode(code);
    if (selected) {
      _selectedCapabilities.add(code);
    } else {
      _selectedCapabilities.remove(code);
    }
    notifyListeners();
  }

  Future<bool> save() async {
    if (!canSave) return false;

    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final current = _profile ?? const BusinessProfile(
        businessName: null,
        phone: null,
        email: null,
        address: null,
        logoPath: null,
        countryCode: 'YE',
        baseCurrencyCode: 'YER',
        locale: 'ar',
        timezone: 'Asia/Aden',
        taxMode: 'none',
        setupStatus: 'not_started',
        setupVersion: 1,
        source: 'onboarding',
      );
      final updated = current.copyWith(
        businessName: _businessName.trim(),
        setupStatus: 'completed',
        source: 'onboarding',
      );
      await profileRepository.saveProfile(updated);
      await capabilityRepository.replaceEnabledCodes(
        _selectedCapabilities,
        source: 'onboarding',
      );
      _profile = updated;
      _needsOnboarding = false;
      return true;
    } catch (error) {
      _errorMessage = 'تعذر حفظ إعدادات البداية. لم تُحذف بياناتك.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
