import 'package:flutter/material.dart';

import 'data/artists.dart';
import 'pages/app_info.dart' show UpdateBanner;
import 'pages/artist_page.dart';
import 'pages/impostazioni_page.dart';
import 'pages/list_pages.dart';
import 'pages/novita_page.dart';
import 'theme.dart';

/// One page of the app, as listed in the bottom menu.
class CnsPage {
  const CnsPage(this.label, this.icon, this.selectedIcon, this.description);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String description;
}

/// The pages, in the same order as the menu of the web app.
const cnsPages = [
  CnsPage(
    'Controllare',
    Icons.notifications_outlined,
    Icons.notifications,
    'Gli artisti con cui sei in pari: ti avviso quando esce qualcosa di nuovo.',
  ),
  CnsPage(
    'Recuperando',
    Icons.library_music_outlined,
    Icons.library_music,
    'Gli artisti di cui stai ascoltando la discografia, con il segnalibro.',
  ),
  CnsPage(
    'Novità',
    Icons.new_releases_outlined,
    Icons.new_releases,
    'Le uscite nuove degli artisti che controlli, e quelle in arrivo.',
  ),
  CnsPage(
    'Impostazioni',
    Icons.settings_outlined,
    Icons.settings,
    'Account, notifiche, persone ammesse e copia di sicurezza.',
  ),
];

/// The position of Novità in the menu.
const novitaIndex = 2;

/// A tap on a home screen widget (cns://novita, cns://recuperando, cns://artista/{id}): kept
/// here until the app's pages are there (after the sign-in), then opened.
final widgetLink = ValueNotifier<Uri?>(null);

/// The app's frame: title bar, the pages side by side (swipe to move) and the bottom menu.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  final _pager = PageController();
  int _current = 0;

  @override
  void initState() {
    super.initState();
    widgetLink.addListener(_openLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLink());
  }

  @override
  void dispose() {
    widgetLink.removeListener(_openLink);
    _pager.dispose();
    super.dispose();
  }

  /// Opens what the tapped widget points to.
  void _openLink() {
    final uri = widgetLink.value;
    if (uri == null || !mounted) return;
    widgetLink.value = null;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    switch (uri.host) {
      case 'novita':
        _goTo(novitaIndex);
      case 'recuperando':
        _goTo(1);
      case 'artista' when uri.pathSegments.isNotEmpty:
        _goTo(1);
        if (ArtistsScope.of(context).byId(uri.pathSegments.first) != null) {
          navigator.push(MaterialPageRoute(builder: (_) => ArtistPage(artistId: uri.pathSegments.first)));
        }
    }
  }

  /// Opens one page of the menu (also from the home screen widget).
  void goTo(int index) => _goTo(index);

  void _goTo(int index) {
    setState(() => _current = index);
    _pager.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final artists = ArtistsScope.of(context);
    // How many artists in each list, on the menu (as the counters of the web menu)
    final news = NewsScope.of(context);
    final counts = [artists.count(Lists.controllare), artists.count(Lists.recuperando), news.unseen, 0];
    // With Novità open, the new ones count as seen (also the ones arriving meanwhile)
    if (_current == novitaIndex && news.unseen > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => news.markSeen());
    }
    return Scaffold(
      appBar: AppBar(title: const CnsTitle()),
      body: Column(
        children: [
          const UpdateBanner(),
          Expanded(
            child: PageView(
              controller: _pager,
              onPageChanged: (index) => setState(() => _current = index),
              children: [
                const ArtistListPage(lista: Lists.controllare),
                const ArtistListPage(lista: Lists.recuperando),
                const NovitaPage(),
                const ImpostazioniPage(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _current,
        onDestinationSelected: _goTo,
        destinations: [
          for (final (i, page) in cnsPages.indexed)
            NavigationDestination(
              icon: Badge(isLabelVisible: counts[i] > 0, label: Text('${counts[i]}'), child: Icon(page.icon)),
              selectedIcon: Badge(
                isLabelVisible: counts[i] > 0,
                label: Text('${counts[i]}'),
                child: Icon(page.selectedIcon),
              ),
              label: page.label,
            ),
        ],
      ),
    );
  }
}

/// "🎧 CNS Chi Ni Sentimu", as the logo of the web app.
class CnsTitle extends StatelessWidget {
  const CnsTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.headphones, color: CnsColors.green, size: 26),
        SizedBox(width: 8),
        Text(
          'CNS',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: CnsColors.text),
        ),
        SizedBox(width: 8),
        // On a narrow phone it shortens instead of overflowing
        Flexible(
          child: Text(
            'Chi Ni Sentimu',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: CnsColors.textMuted),
          ),
        ),
      ],
    );
  }
}
