class UnitConversionEdge {
  final int fromUnitId;
  final int toUnitId;
  final double factor;

  const UnitConversionEdge({
    required this.fromUnitId,
    required this.toUnitId,
    required this.factor,
  });
}

class UnitConversionPolicy {
  static const double maxFactor = 1000000;
  static const double maxQuantity = 1000000000000;

  static void validateFactor(double factor) {
    if (!factor.isFinite || factor <= 0 || factor > maxFactor) {
      throw ArgumentError.value(factor, 'factor', 'Conversion factor must be finite and positive.');
    }
  }

  static void validateQuantity(double quantity) {
    if (!quantity.isFinite || quantity <= 0 || quantity > maxQuantity) {
      throw ArgumentError.value(quantity, 'quantity', 'Quantity must be finite and positive.');
    }
  }

  static double toBaseQuantity({
    required double quantity,
    required double factor,
  }) {
    validateQuantity(quantity);
    validateFactor(factor);
    final baseQuantity = quantity * factor;
    if (!baseQuantity.isFinite || baseQuantity > maxQuantity) {
      throw ArgumentError('Converted quantity exceeds the supported inventory range.');
    }
    return baseQuantity;
  }

  static void validateEdge({
    required int fromUnitId,
    required int toUnitId,
    required double factor,
  }) {
    if (fromUnitId <= 0 || toUnitId <= 0 || fromUnitId == toUnitId) {
      throw ArgumentError('A unit conversion must connect two different valid units.');
    }
    validateFactor(factor);
  }

  static void validateNoCycles(Iterable<UnitConversionEdge> edges) {
    final graph = <int, List<int>>{};
    for (final edge in edges) {
      validateEdge(
        fromUnitId: edge.fromUnitId,
        toUnitId: edge.toUnitId,
        factor: edge.factor,
      );
      graph.putIfAbsent(edge.fromUnitId, () => []).add(edge.toUnitId);
    }

    final visiting = <int>{};
    final visited = <int>{};
    void visit(int node) {
      if (visiting.contains(node)) {
        throw ArgumentError('Unit conversion graph contains a cycle.');
      }
      if (visited.contains(node)) return;
      visiting.add(node);
      for (final next in graph[node] ?? const <int>[]) {
        visit(next);
      }
      visiting.remove(node);
      visited.add(node);
    }

    for (final node in graph.keys) {
      visit(node);
    }
  }
}
