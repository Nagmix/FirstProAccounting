import 'capability_definition.dart';

class CapabilityCatalog {
  CapabilityCatalog._();

  static const List<CapabilityDefinition> definitions = <CapabilityDefinition>[
    CapabilityDefinition(
      code: 'sell',
      labelAr: 'البيع',
      descriptionAr: 'إنشاء مبيعات وفواتير ومرتجعات.',
      dependencies: <String>{'settle'},
      priority: 10,
    ),
    CapabilityDefinition(
      code: 'buy',
      labelAr: 'الشراء',
      descriptionAr: 'إدارة المشتريات والموردين ومرتجعات الشراء.',
      dependencies: <String>{'settle'},
      priority: 20,
    ),
    CapabilityDefinition(
      code: 'stock',
      labelAr: 'المخزون',
      descriptionAr: 'متابعة الكميات والوحدات والمستودعات والجرد.',
      priority: 30,
    ),
    CapabilityDefinition(
      code: 'service',
      labelAr: 'الخدمات أو الطلبات',
      descriptionAr: 'استقبال الطلبات ومتابعتها وتسليمها.',
      dependencies: <String>{'settle'},
      priority: 40,
    ),
    CapabilityDefinition(
      code: 'schedule',
      labelAr: 'المواعيد والمتابعة',
      descriptionAr: 'تحديد مواعيد أو تواريخ متابعة للعملاء والطلبات.',
      dependencies: <String>{'service'},
      priority: 50,
    ),
    CapabilityDefinition(
      code: 'settle',
      labelAr: 'التحصيل والدفع',
      descriptionAr: 'إدارة الدفعات والصناديق والديون.',
      priority: 60,
    ),
    CapabilityDefinition(
      code: 'transform',
      labelAr: 'التحويل أو الإنتاج',
      descriptionAr: 'تحويل مواد أو مكونات إلى منتج آخر.',
      dependencies: <String>{'stock'},
      priority: 70,
    ),
    CapabilityDefinition(
      code: 'reporting',
      labelAr: 'التقارير',
      descriptionAr: 'عرض التقارير الأساسية والتشغيلية.',
      dependencies: <String>{'settle'},
      priority: 80,
    ),
    CapabilityDefinition(
      code: 'backup',
      labelAr: 'النسخ الاحتياطي',
      descriptionAr: 'حماية نسخة البيانات واستعادتها.',
      isCore: true,
      priority: 1,
    ),
    CapabilityDefinition(
      code: 'settings',
      labelAr: 'الإعدادات',
      descriptionAr: 'إعدادات التطبيق والملف التجاري.',
      isCore: true,
      priority: 2,
    ),
    CapabilityDefinition(
      code: 'audit',
      labelAr: 'سجل التدقيق',
      descriptionAr: 'حفظ ومراجعة أثر العمليات.',
      isCore: true,
      priority: 3,
    ),
  ];

  static final Map<String, CapabilityDefinition> _byCode = {
    for (final definition in definitions) definition.code: definition,
  };

  static CapabilityDefinition byCode(String code) {
    final definition = _byCode[code];
    if (definition == null) {
      throw ArgumentError.value(code, 'code', 'Unknown capability code');
    }
    return definition;
  }

  static Set<String> resolveDependencies(Iterable<String> requested) {
    final resolved = <String>{};

    void visit(String code, Set<String> visiting) {
      final definition = byCode(code);
      if (resolved.contains(code)) return;
      if (!visiting.add(code)) {
        throw StateError('Capability dependency cycle at $code');
      }
      for (final dependency in definition.dependencies) {
        visit(dependency, visiting);
      }
      visiting.remove(code);
      resolved.add(code);
    }

    for (final code in requested) {
      visit(code, <String>{});
    }
    return resolved;
  }

  static void validateNoCycles() {
    for (final definition in definitions) {
      resolveDependencies(<String>{definition.code});
    }
  }
}
