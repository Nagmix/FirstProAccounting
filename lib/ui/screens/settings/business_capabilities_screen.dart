import 'package:flutter/material.dart';
import 'package:firstpro/core/platform/capability_catalog.dart';
import 'package:firstpro/core/platform/feature_visibility_service.dart';

class BusinessCapabilitiesScreen extends StatefulWidget {
  final FeatureVisibilityService service;
  final bool loadOnInit;

  const BusinessCapabilitiesScreen({
    super.key,
    required this.service,
    this.loadOnInit = true,
  });

  @override
  State<BusinessCapabilitiesScreen> createState() =>
      _BusinessCapabilitiesScreenState();
}

class _BusinessCapabilitiesScreenState
    extends State<BusinessCapabilitiesScreen> {
  String? _actionError;

  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.service.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final service = widget.service;
        if (service.isLoading && service.enabledCodes.isEmpty) {
          return _buildLoading(context);
        }
        if (service.errorMessage != null && service.enabledCodes.isEmpty) {
          return _buildError(context);
        }
        return _buildContent(context);
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الوظائف')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('نجهز وظائف البرنامج...'),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final service = widget.service;
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الوظائف')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(
                service.errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: service.isLoading ? null : service.load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final optionalDefinitions = CapabilityCatalog.definitions
        .where((definition) => !definition.isCore)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الوظائف')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'الوظائف التي تديرها',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'اختر الوظائف التي تحتاجها في عملك الآن. يمكنك تغييرها لاحقاً دون فقدان أي بيانات.',
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'إخفاء الوظيفة لا يحذف بياناتها أو مستنداتها السابقة.',
              ),
            ),
          ),
          if (_actionError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _actionError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          ...optionalDefinitions.map(_buildCapabilityTile),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('وظائف الحماية والإعدادات والتدقيق متاحة دائماً'),
            subtitle: Text('لا يمكن تعطيل الوظائف الأساسية للنظام.'),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityTile(CapabilityDefinition definition) {
    final service = widget.service;
    final enabled = service.enabledCodes.contains(definition.code);
    final canDisable = service.canDisable(definition.code);
    return SwitchListTile(
      value: enabled,
      onChanged: (value) async {
        setState(() => _actionError = null);
        try {
          await service.setEnabled(definition.code, value);
        } catch (error) {
          if (mounted) {
            setState(() => _actionError = error.toString().replaceFirst('Bad state: ', ''));
          }
        }
      },
      title: Text(definition.labelAr),
      subtitle: Text(
        canDisable || !enabled
            ? definition.descriptionAr
            : '${definition.descriptionAr} هذه الوظيفة مطلوبة لوظيفة مفعلة أخرى.',
      ),
      secondary: Icon(_iconFor(definition.code)),
    );
  }

  IconData _iconFor(String code) {
    switch (code) {
      case 'sell':
        return Icons.point_of_sale;
      case 'buy':
        return Icons.shopping_cart;
      case 'stock':
        return Icons.inventory_2;
      case 'service':
        return Icons.build;
      case 'schedule':
        return Icons.event;
      case 'settle':
        return Icons.payments;
      case 'transform':
        return Icons.factory_outlined;
      case 'reporting':
        return Icons.assessment;
      default:
        return Icons.extension;
    }
  }
}
