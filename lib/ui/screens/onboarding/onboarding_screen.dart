import 'package:flutter/material.dart';
import 'package:firstpro/core/platform/capability_catalog.dart';
import 'package:firstpro/core/platform/onboarding_viewmodel.dart';

class OnboardingScreen extends StatefulWidget {
  final OnboardingViewModel viewModel;
  final VoidCallback? onCompleted;
  final bool loadOnInit;

  const OnboardingScreen({
    super.key,
    required this.viewModel,
    this.onCompleted,
    this.loadOnInit = true,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _businessNameController;
  late final FocusNode _businessNameFocusNode;
  int _currentStep = 0;

  OnboardingViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _businessNameController = TextEditingController();
    _businessNameFocusNode = FocusNode();
    if (widget.loadOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => viewModel.load());
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessNameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: viewModel,
        builder: (context, _) {
          if (viewModel.isLoading && viewModel.profile == null) {
            return _buildLoading(context);
          }
          if (viewModel.errorMessage != null && viewModel.profile == null) {
            return _buildError(context);
          }
          if (_businessNameController.text != viewModel.businessName &&
              !_businessNameFocusNode.hasFocus) {
            _businessNameController.text = viewModel.businessName;
          }
          return _buildContent(context);
        },
      ),
    );
  }

  Widget _baseScaffold({required Widget child}) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return _baseScaffold(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 120),
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'نجهز برنامجك...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return _baseScaffold(
      child: Column(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.cloud_off, size: 52, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(
            viewModel.errorMessage!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: viewModel.isLoading ? null : viewModel.load,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    return _baseScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.storefront, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'إعداد سريع يناسب نشاطك',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'سنجهز الأساسيات الآن، ويمكنك تعديلها لاحقاً من الإعدادات.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _buildStepIndicator(context),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey<int>(_currentStep),
              child: _buildCurrentStep(context),
            ),
          ),
          if (viewModel.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                viewModel.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          _buildNavigation(context),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الخطوة ${_currentStep + 1} من 4',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (_currentStep + 1) / 4),
      ],
    );
  }

  Widget _buildCurrentStep(BuildContext context) {
    switch (_currentStep) {
      case 0:
        return _buildBusinessStep(context);
      case 1:
        return _buildCountryCurrencyStep(context);
      case 2:
        return _buildTaxStep(context);
      case 3:
        return _buildReviewStep(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBusinessStep(BuildContext context) {
    final optionalDefinitions = CapabilityCatalog.definitions
        .where((definition) => !definition.isCore)
        .toList(growable: false);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'لنبدأ بإعداد برنامجك',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'اختر ما تريد إدارته الآن. يمكنك إضافة أي خيار لاحقاً.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _businessNameController,
          focusNode: _businessNameFocusNode,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'اسم النشاط',
            hintText: 'مثال: متجر البداية',
            prefixIcon: Icon(Icons.business),
          ),
          onChanged: viewModel.setBusinessName,
        ),
        const SizedBox(height: 24),
        Text(
          'ما الذي تريد إدارته؟',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text('يمكنك اختيار أكثر من خيار.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        ...optionalDefinitions.map(
          (definition) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: CheckboxListTile(
              value: viewModel.selectedCapabilities.contains(definition.code),
              onChanged: (value) => viewModel.toggleCapability(
                definition.code,
                value ?? false,
              ),
              title: Text(definition.labelAr),
              subtitle: Text(definition.descriptionAr),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountryCurrencyStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'البلد والعملة',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('اختر الإعداد المحلي الذي سيظهر في الفواتير والتقارير.'),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: viewModel.countryCode,
          decoration: const InputDecoration(
            labelText: 'الدولة',
            prefixIcon: Icon(Icons.public),
          ),
          items: const [
            DropdownMenuItem(value: 'YE', child: Text('اليمن')),
          ],
          onChanged: (value) {
            if (value != null) viewModel.setCountryCode(value);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: viewModel.baseCurrencyCode,
          decoration: const InputDecoration(
            labelText: 'العملة الأساسية',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
          items: const [
            DropdownMenuItem(value: 'YER', child: Text('الريال اليمني')),
          ],
          onChanged: (value) {
            if (value != null) viewModel.setBaseCurrencyCode(value);
          },
        ),
      ],
    );
  }

  Widget _buildTaxStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'طريقة الضريبة',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('حدد طريقة التعامل مع الضريبة. لن نضيف نسبة تلقائية.'),
        const SizedBox(height: 16),
        RadioListTile<String>(
          value: 'none',
          groupValue: viewModel.taxMode,
          onChanged: (value) {
            if (value != null) viewModel.setTaxMode(value);
          },
          title: const Text('بدون ضريبة'),
          subtitle: const Text('مناسب للنشاط غير المسجل ضريبياً حالياً.'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        RadioListTile<String>(
          value: 'standard',
          groupValue: viewModel.taxMode,
          onChanged: (value) {
            if (value != null) viewModel.setTaxMode(value);
          },
          title: const Text('ضريبة قياسية'),
          subtitle: const Text('يمكن ضبط السياسة والنسبة المؤرخة لاحقاً.'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'مراجعة الإعدادات',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('تأكد من الاختيارات قبل بدء استخدام البرنامج.'),
        const SizedBox(height: 16),
        _reviewRow(context, 'اسم النشاط', viewModel.businessName),
        _reviewRow(context, 'الدولة', viewModel.countryCode == 'YE' ? 'اليمن' : viewModel.countryCode),
        _reviewRow(
          context,
          'العملة الأساسية',
          viewModel.baseCurrencyCode == 'YER'
              ? 'الريال اليمني (YER)'
              : viewModel.baseCurrencyCode,
        ),
        _reviewRow(
          context,
          'طريقة الضريبة',
          viewModel.taxMode == 'standard' ? 'ضريبة قياسية' : 'بدون ضريبة',
        ),
        _reviewRow(
          context,
          'المميزات المختارة',
          '${viewModel.selectedCapabilities.length} مميزات',
        ),
      ],
    );
  }

  Widget _reviewRow(BuildContext context, String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }

  Widget _buildNavigation(BuildContext context) {
    final canContinue = _currentStep < 3 && _canContinue;
    return Row(
      children: [
        if (_currentStep > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: viewModel.isSaving ? null : _previousStep,
              child: const Text('رجوع'),
            ),
          ),
        if (_currentStep > 0) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _currentStep == 3
                ? (viewModel.canSave && !viewModel.isSaving ? _save : null)
                : (canContinue ? _nextStep : null),
            child: viewModel.isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_currentStep == 3 ? 'حفظ وبدء الاستخدام' : 'التالي'),
          ),
        ),
      ],
    );
  }

  bool get _canContinue {
    switch (_currentStep) {
      case 0:
        return viewModel.canSave;
      case 1:
        return viewModel.countryCode.isNotEmpty && viewModel.baseCurrencyCode.isNotEmpty;
      case 2:
        return viewModel.taxMode.isNotEmpty;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (_currentStep < 3) setState(() => _currentStep++);
  }

  void _previousStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Future<void> _save() async {
    final saved = await viewModel.save();
    if (saved && mounted) widget.onCompleted?.call();
  }
}
