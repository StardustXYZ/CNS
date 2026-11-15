import 'package:flutter/material.dart';

import '../home.dart';
import '../theme.dart';

/// A page not built yet: what it will show, until its phase arrives.
class PagePlaceholder extends StatelessWidget {
  const PagePlaceholder({super.key, required this.page});

  final CnsPage page;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(page.selectedIcon, size: 56, color: CnsColors.accent),
                  const SizedBox(height: 16),
                  Text(page.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    page.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: CnsColors.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: CnsColors.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: CnsColors.border),
                    ),
                    child: const Text(
                      'In arrivo nelle prossime versioni',
                      style: TextStyle(fontSize: 12, color: CnsColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
