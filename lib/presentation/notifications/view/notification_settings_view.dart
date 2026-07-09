import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/notifications/notification_event_type.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../viewmodel/notification_settings_view_model.dart';

/// Per-business notification preferences. The owner picks which events to
/// receive (push + in-app) for each of their businesses.
class NotificationSettingsView extends ConsumerWidget {
  const NotificationSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authGateViewModelProvider).profile;
    final state = ref.watch(notificationSettingsViewModelProvider);
    final vm = ref.read(notificationSettingsViewModelProvider.notifier);

    final businesses = (profile?.memberships ?? const [])
        .where((m) => m.allowed)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : businesses.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No tienes negocios con notificaciones.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
                      child: Text(
                        'Elige qué notificaciones quieres recibir en cada negocio.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (state.error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    for (final m in businesses)
                      _BusinessSection(
                        businessId: m.businessId,
                        title: (m.businessName?.trim().isNotEmpty ?? false)
                            ? m.businessName!.trim()
                            : 'Negocio',
                        subtitle: (m.branchName?.trim().isNotEmpty ?? false)
                            ? m.branchName!.trim()
                            : null,
                        state: state,
                        onToggle: (eventKey, enabled) => vm.toggle(
                          businessId: m.businessId,
                          eventKey: eventKey,
                          enabled: enabled,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _BusinessSection extends StatelessWidget {
  const _BusinessSection({
    required this.businessId,
    required this.title,
    required this.state,
    required this.onToggle,
    this.subtitle,
  });

  final String businessId;
  final String title;
  final String? subtitle;
  final NotificationSettingsState state;
  final void Function(String eventKey, bool enabled) onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final event in NotificationEventType.values)
            SwitchListTile(
              value: state.isEnabled(businessId, event.key),
              onChanged: (v) => onToggle(event.key, v),
              title: Text(event.label),
              subtitle: Text(event.description),
            ),
        ],
      ),
    );
  }
}
