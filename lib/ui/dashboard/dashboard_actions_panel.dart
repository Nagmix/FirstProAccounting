import 'package:flutter/material.dart';
import 'package:firstpro/ui/dashboard/action_definition.dart';

class DashboardActionsPanel extends StatelessWidget {
  final List<ActionDefinition> actions;
  final ValueChanged<String> onAction;

  const DashboardActionsPanel({
    super.key,
    required this.actions,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('لا توجد وظائف مفعلة بعد.')),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560
            ? 3
            : constraints.maxWidth >= 340
                ? 2
                : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: columns == 1 ? 4.6 : 1.55,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];
            return _ActionTile(
              action: action,
              onTap: () => onAction(action.route),
            );
          },
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  final ActionDefinition action;
  final VoidCallback onTap;

  const _ActionTile({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: action.labelAr,
      child: Material(
        color: action.backgroundColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: action.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(action.icon, color: action.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    action.labelAr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                Icon(Icons.arrow_back_ios_new, size: 14, color: action.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
