import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../i18n/locale_scope.dart';
import '../theme/tokens.dart';
import 'first_aid_screen.dart';
import 'home_screen.dart';
import 'journal_screen.dart';
import 'nearby_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  // The Family tab was retired in favour of Journal — every past
  // conversation has an audit drawer (rule, severity, citation), which
  // serves the Safety & Trust pillar and the user's "what did Sema tell
  // me last week?" use-case in one surface.
  static const _pages = <Widget>[
    HomeScreen(),
    NearbyScreen(),
    FirstAidScreen(),
    JournalScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: _NavBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    final items = <_NavItem>[
      _NavItem(s.t('nav.home'),     PhosphorIconsRegular.house,       PhosphorIconsFill.house),
      _NavItem(s.t('nav.care'),     PhosphorIconsRegular.mapPin,      PhosphorIconsFill.mapPin),
      _NavItem(s.t('nav.firstAid'), PhosphorIconsRegular.firstAidKit, PhosphorIconsFill.firstAidKit),
      _NavItem(s.t('nav.journal'),  PhosphorIconsRegular.notebook,    PhosphorIconsFill.notebook),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: SemaColors.bg,
        border: Border(top: BorderSide(color: SemaColors.hairlineSoft)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = i == index;
              final item = items[i];
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? item.activeIcon : item.icon,
                        size: 24,
                        color: selected ? SemaColors.ink : SemaColors.inkSoft,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          letterSpacing: 0.0,
                          color: selected
                              ? SemaColors.ink
                              : SemaColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}
