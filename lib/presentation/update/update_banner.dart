import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_view_model.dart';

/// Banner superior que aparece cuando hay una nueva versión desplegada.
/// Ocupa altura cero mientras no haya actualización disponible.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateAvailable = ref.watch(updateAvailableProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: updateAvailable
          ? const _BannerContent()
          : const SizedBox(width: double.infinity),
    );
  }
}

class _BannerContent extends ConsumerWidget {
  const _BannerContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.rocket_launch_rounded,
                  color: scheme.onPrimary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hay una nueva versión disponible.',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () =>
                    ref.read(updateAvailableProvider.notifier).applyUpdate(),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.onPrimary,
                  foregroundColor: scheme.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Actualizar ahora'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
