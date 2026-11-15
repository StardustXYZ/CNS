import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/discography_store.dart';
import '../theme.dart';
import 'account_pages.dart' show say;

/// Gives the pages the discographies (and rebuilds them when one arrives).
class DiscographyScope extends InheritedNotifier<DiscographyStore> {
  const DiscographyScope({super.key, required DiscographyStore store, required super.child}) : super(notifier: store);

  static DiscographyStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiscographyScope>()!.notifier!;
}

/// Opens a link in its app (Spotify, Deezer) or in the browser.
Future<void> openLink(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) say(context, 'Non riesco ad aprire il link.');
}

/// The cover of a release, square with round corners; a disc while it loads or without one.
class ReleaseCover extends StatelessWidget {
  const ReleaseCover({super.key, required this.url, this.size = 56});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: CnsColors.surface2,
      child: Icon(Icons.album, size: size * 0.5, color: CnsColors.textMuted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
            ),
    );
  }
}

/// A heading of the artist page, as the h2 of the web app.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );
}

/// "15/11/2026 alle 16:05".
String dateTimeLabel(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = d.toLocal();
  return '${two(l.day)}/${two(l.month)}/${l.year} alle ${two(l.hour)}:${two(l.minute)}';
}
