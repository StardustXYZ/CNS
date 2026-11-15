import 'package:flutter/material.dart';

import 'pages/page_placeholder.dart';
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

/// The app's frame: title bar, the pages side by side (swipe to move) and the bottom menu.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _pager = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    setState(() => _current = index);
    _pager.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const CnsTitle()),
      body: PageView(
        controller: _pager,
        onPageChanged: (index) => setState(() => _current = index),
        children: [for (final page in cnsPages) PagePlaceholder(page: page)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _current,
        onDestinationSelected: _goTo,
        destinations: [
          for (final page in cnsPages)
            NavigationDestination(icon: Icon(page.icon), selectedIcon: Icon(page.selectedIcon), label: page.label),
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
        Text('CNS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: CnsColors.text)),
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
