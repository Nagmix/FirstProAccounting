import 'package:flutter/material.dart';
import 'package:firstpro/core/platform/capability_catalog.dart';
import 'package:firstpro/core/platform/onboarding_viewmodel.dart';

class OnboardingScreen extends StatefulWidget {
  final OnboardingViewModel viewModel;
  final VoidCallback? onCompleted;

  const OnboardingScreen({
    super.key,
    required this.viewModel,
    this.onCompleted,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _businessNameController;

  OnboardingViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _businessNameController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => viewModel.load());
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) {
        if (viewModel.isLoading && viewModel.profile == null) {
          return _buildLoading(context);
        }
        if (viewModel.errorMessage != null && viewModel.profile == null) {
          return _buildError(context);
        }
        if (_businessNameController.text != viewModel.businessName &&
            !_businessNameController.hasFocus) {
          _businessNameController.text = viewModel.businessName;
        }
        return _buildContent(context);
      },
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
    final optionalDefinitions = CapabilityCatalog.definitions
        .where((definition) => !definition.isCore)
        .toList(growable: false);

    return _baseScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.storefront, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'لنبدأ بإعداد برنامجك',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'اختر ما تريد إدارته الآن. يمكنك إضافة أي خيار لاحقاً من الإعدادات.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _businessNameController,
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
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'يمكنك اختيار أكثر من خيار.',
            style: theme.textTheme.bodySmall,
          ),
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
          const SizedBox(height: 16),
          if (viewModel.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                viewModel.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ElevatedButton(
            onPressed: viewModel.canSave
                ? () async {
                    final saved = await viewModel.save();
                    if (saved && mounted) widget.onCompleted?.call();
                  }
                : null,
            child: viewModel.isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('متابعة'),
          ),
        ],
      ),
    );
  }
}
