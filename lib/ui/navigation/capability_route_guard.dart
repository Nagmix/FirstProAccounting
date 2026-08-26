import 'package:flutter/material.dart';
import 'package:firstpro/core/platform/feature_visibility_service.dart';
import 'package:firstpro/ui/navigation/navigation_definition.dart';

class CapabilityRouteGuardScreen extends StatefulWidget {
  final NavigationDefinition definition;
  final FeatureVisibilityService service;

  const CapabilityRouteGuardScreen({
    super.key,
    required this.definition,
    required this.service,
  });

  @override
  State<CapabilityRouteGuardScreen> createState() =>
      _CapabilityRouteGuardScreenState();
}

class _CapabilityRouteGuardScreenState
    extends State<CapabilityRouteGuardScreen> {
  bool _isSaving = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الوظيفة غير مفعلة')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'هذه الوظيفة مخفية حالياً',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'يمكنك إظهار «${widget.definition.labelAr}» من هنا أو تفعيلها لاحقاً من الإعدادات.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'إظهار الوظيفة لا ينشئ مستندات مالية ولا يحذف بياناتك السابقة.',
                textAlign: TextAlign.center,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSaving ? null : _enableFeature,
                icon: _isSaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.visibility),
                label: const Text('إظهار الوظيفة'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                child: const Text('رجوع'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _enableFeature() async {
    final required = widget.definition.requiredCapabilities;
    if (required.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.service.setEnabled(required.first, true);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'تعذر إظهار الوظيفة. حاول مرة أخرى.';
        });
      }
    }
  }
}
