class ServiceOrderStatusPolicy {
  ServiceOrderStatusPolicy._();

  static const Map<String, Set<String>> _allowedTransitions = {
    'draft': {'received', 'cancelled'},
    'received': {'diagnosing', 'cancelled'},
    'diagnosing': {'in_progress', 'cancelled'},
    'in_progress': {'ready', 'cancelled'},
    'ready': {'delivered', 'cancelled'},
  };

  static bool canTransition(String from, String to) {
    if (from == to) return false;
    return _allowedTransitions[from]?.contains(to) ?? false;
  }

  static bool canPost(String status) {
    return status == 'ready' || status == 'delivered';
  }

  static bool isTerminal(String status) {
    return status == 'delivered' || status == 'cancelled';
  }
}
