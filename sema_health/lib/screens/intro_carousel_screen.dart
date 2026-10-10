import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../i18n/locale_scope.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';
import '../widgets/sema_button.dart';
import 'language_picker_screen.dart';

/// Three-step intro carousel — entry point of the app.
///
/// Pages reference i18n keys; the active language at carousel time
/// (English by default) controls the rendered copy. The CTA flips to
/// "Pick your language" on the final page.
class IntroCarouselScreen extends StatefulWidget {
  const IntroCarouselScreen({super.key});

  @override
  State<IntroCarouselScreen> createState() => _IntroCarouselScreenState();
}

class _IntroCarouselScreenState extends State<IntroCarouselScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pageKeys = <_IntroPageKey>[
    _IntroPageKey(
      asset: 'assets/illustrations/privacy.svg',
      eyebrow: 'intro.privacy.eyebrow',
      lead: 'intro.privacy.lead',
      emphasis: 'intro.privacy.emphasis',
      tail: '',
      body: 'intro.privacy.body',
    ),
    _IntroPageKey(
      asset: 'assets/illustrations/voice.svg',
      eyebrow: 'intro.voice.eyebrow',
      lead: 'intro.voice.lead',
      emphasis: 'intro.voice.emphasis',
      tail: 'intro.voice.tail',
      body: 'intro.voice.body',
    ),
    _IntroPageKey(
      asset: 'assets/illustrations/care.svg',
      eyebrow: 'intro.care.eyebrow',
      lead: 'intro.care.lead',
      emphasis: 'intro.care.emphasis',
      tail: 'intro.care.tail',
      body: 'intro.care.body',
    ),
  ];

  bool get _isLast => _index == _pageKeys.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LanguagePickerScreen()),
      );
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _skip() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LanguagePickerScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Spacer(),
                  if (!_isLast)
                    PressScale(
                      onTap: _skip,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8,
                        ),
                        child: Text(
                          s.t('common.skip'),
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: SemaColors.inkMid,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _pageKeys.length,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (_, i) => _IntroPageView(page: _pageKeys[i], strings: s),
              ),
            ),
            _DotIndicator(count: _pageKeys.length, active: _index),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: SemaButton(
                label: _isLast
                    ? s.t('intro.cta.pickLanguage')
                    : s.t('common.continue'),
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPageKey {
  const _IntroPageKey({
    required this.asset,
    required this.eyebrow,
    required this.lead,
    required this.emphasis,
    required this.tail,
    required this.body,
  });
  final String asset;
  final String eyebrow;
  final String lead;
  final String emphasis;
  final String tail;
  final String body;
}

class _IntroPageView extends StatelessWidget {
  const _IntroPageView({required this.page, required this.strings});
  final _IntroPageKey page;
  final SemaStrings strings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tail = page.tail.isEmpty ? '' : strings.t(page.tail);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: SvgPicture.asset(
                page.asset, width: 240, height: 240,
              ),
            ),
          ),
          Text(strings.t(page.eyebrow), style: t.labelMedium),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: t.displayMedium!.copyWith(
                fontSize: 32, height: 1.1, letterSpacing: -1.2,
              ),
              children: [
                TextSpan(text: strings.t(page.lead)),
                TextSpan(
                  text: strings.t(page.emphasis),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (tail.isNotEmpty) TextSpan(text: tail),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            strings.t(page.body),
            style: t.bodyMedium?.copyWith(fontSize: 14.5, height: 1.5),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 6,
          width: isActive ? 22 : 6,
          decoration: BoxDecoration(
            color: isActive ? SemaColors.ink : SemaColors.hairline,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
