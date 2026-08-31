import 'package:flutter/material.dart';
import '../models/feature_availability.dart';

/// Consistent affordance for features that are disabled, need setup, need
/// data, or are temporarily offline. A disabled tile never fires its action.
class FeatureAvailabilityTile extends StatelessWidget {
  const FeatureAvailabilityTile({
    super.key,
    required this.icon,
    required this.title,
    required this.availability,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final FeatureAvailability availability;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = availability.enabled && onTap != null;
    final color = enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: '$title. ${availability.reason}',
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(
          subtitle == null
              ? availability.reason
              : '$subtitle · ${availability.reason}',
        ),
        trailing: enabled
            ? const Icon(Icons.chevron_right_rounded)
            : const Icon(Icons.lock_outline_rounded),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
