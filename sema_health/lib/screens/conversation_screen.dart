import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/agent_provider.dart';
import '../ai/chat_agent.dart';
import '../ai/llm.dart';
import '../ai/sema_reply.dart';
import '../data/conversation/chat_message.dart';
import '../data/conversation/conversation_store.dart';
import '../data/profile/bio_profile_store.dart';
import '../data/seed/first_aid_repo_provider.dart';
import '../domain/triage/triage_input.dart';
import '../i18n/locale_scope.dart';
import '../services/voice_input.dart';
import '../services/voice_output.dart';
import '../theme/tokens.dart';
import '../util/text_clean.dart';
import '../widgets/bio_profile_sheet.dart';
import '../widgets/first_aid_detail_sheet.dart';
import '../widgets/press_scale.dart';
import '../widgets/sema_reply_bubble.dart';
import 'nearby_screen.dart';

const String _defaultEmergencyNumber = '112';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _scroll = ScrollController();

  ChatAgent? _agent;
  ConversationStore? _store;
  int? _conversationId;
  Stream<List<ChatMessage>>? _stream;
  bool _thinking = false;
  bool _greeted = false;
  Object? _bootstrapError;

  /// Shared Gemma handle for the camera/vision flow. Null when the model
  /// file isn't on the device — the composer hides its camera button.
  Llm? _llm;
  bool _describingPhoto = false;

  /// Mic + STT pipeline. Null when the active locale has no on-device
  /// ASR model (en/fr/yo/ga); the composer's mic icon is hidden then.
  VoiceInput? _voiceInput;

  /// TTS + speaker pipeline. Same locale gating as [_voiceInput] —
  /// null hides the play button on Sema bubbles.
  VoiceOutput? _voiceOutput;

  @override
  void initState() {
    super.initState();
    BioProfileStore.instance.listenable.addListener(_onProfileChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    BioProfileStore.instance.listenable.removeListener(_onProfileChanged);
    _scroll.dispose();
    // Voice controllers hold native handles (mic recorder, ORT sessions,
    // audio player). Tear them down so leaving the chat actually frees
    // the mic and the ASR/TTS model memory.
    _voiceInput?.dispose();
    _voiceOutput?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // Resolve the agent for the locale active at chat-open time.
      // Switching language mid-session won't hot-swap the agent — the
      // user reopens the chat to pick up MT (or its absence). Acceptable
      // for v1; the alternative is rebuilding the wrapper on every
      // notifier tick, which would tear down a half-streamed turn.
      final localeCode = LocaleScope.read(context).language.code;
      final results = await Future.wait([
        symptomAgentFuture(localeCode: localeCode),
        ConversationStore.open(),
        gemmaLlmFuture(),
      ]);
      if (!mounted) return;
      final agent = results[0] as ChatAgent;
      final store = results[1] as ConversationStore;
      final llm = results[2] as Llm?;
      final convId = await store.getOrCreateActive(
        profileLabel: BioProfileStore.instance.current?.displayName,
      );
      // Voice is only wired for locales with on-device STT/TTS bundles
      // (currently sw / tw). For everything else the controllers stay
      // null and the mic + play affordances simply don't render.
      final voiceCode = VoiceInput.voiceCodeFor(localeCode);
      final voiceIn =
          voiceCode == null ? null : VoiceInput(langCode: voiceCode);
      final voiceOut =
          voiceCode == null ? null : VoiceOutput(langCode: voiceCode);
      if (!mounted) return;
      setState(() {
        _agent = agent;
        _store = store;
        _conversationId = convId;
        _stream = store.watch(convId);
        _voiceInput = voiceIn;
        _voiceOutput = voiceOut;
        _llm = llm;
      });
      if (!BioProfileStore.instance.hasProfile) {
        await BioProfileSheet.show(context);
      }
      if (!mounted) return;
      await _ensureGreeting();
    } on Object catch (e, st) {
      // Surface the failure instead of stranding the user on the
      // booting spinner forever. Most common cause: a YAML asset wasn't
      // declared in pubspec.yaml so `rootBundle.loadString` throws.
      // ignore: avoid_print
      print('ConversationScreen bootstrap failed: $e\n$st');
      if (!mounted) return;
      setState(() => _bootstrapError = e);
    }
  }

  void _onProfileChanged() {
    if (!mounted) return;
    if (BioProfileStore.instance.hasProfile && !_greeted) {
      _ensureGreeting();
    }
  }

  Future<void> _ensureGreeting() async {
    if (_agent == null || _store == null || _conversationId == null) return;
    if (_greeted) return;
    final existing = await _store!.read(_conversationId!);
    if (existing.isNotEmpty) {
      _greeted = true;
      return;
    }
    final greet = _agent!.greeting(BioProfileStore.instance.current);
    await _store!.appendSemaReply(
      conversationId: _conversationId!,
      reply: greet,
    );
    _greeted = true;
    _scrollToBottomSoon();
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    final agent = _agent;
    final store = _store;
    final convId = _conversationId;
    if (agent == null || store == null || convId == null) return;

    await store.appendUserMessage(conversationId: convId, text: text);
    setState(() => _thinking = true);
    _scrollToBottomSoon();

    int? replyId;
    try {
      await for (final turn in agent.respondStream(
        userText: text,
        profile: BioProfileStore.instance.current,
      )) {
        if (!mounted) return;
        if (replyId == null) {
          replyId = await store.appendSemaReply(
            conversationId: convId,
            reply: turn.reply,
          );
          // Intentionally do NOT clear `_thinking` here. For the
          // translating agent, the first event is a localized
          // placeholder — the real reply is still 15-30s away while
          // Gemma translates. Keeping the typing dots visible under
          // the placeholder bubble communicates "still working" until
          // the stream actually ends (handled in the finally block).
        } else {
          await store.updateSemaReply(
            conversationId: convId,
            messageId: replyId,
            reply: turn.reply,
          );
        }
        _scrollToBottomSoon();
      }
    } catch (_) {
      // Stream errored — leave whatever was last persisted in place.
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Take a photo with the system camera, run Gemma 3n's vision encoder
  /// on it on-device, and feed the resulting factual description into the
  /// normal `_send` pipeline. The description is shown verbatim as a
  /// user-side bubble — there's no clinical text on the photo itself, the
  /// triage engine works off what Gemma saw.
  ///
  /// Gemma is constrained to describe *what is in the frame* in short,
  /// neutral prose. It does NOT diagnose, prescribe, or speculate about
  /// severity — that's still the deterministic triage engine's job.
  Future<void> _captureAndDescribePhoto() async {
    final llm = _llm;
    if (llm == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Camera needs Gemma on this device. Finish model setup first.",
            ),
          ),
        );
      }
      return;
    }
    if (_describingPhoto || _thinking) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        // Cap dimensions so the vision encoder doesn't choke on a 12 MP
        // jpeg. MediaPipe downsamples internally but oversized inputs
        // burn CPU on the pre-process pass.
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera unavailable: $e')),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _describingPhoto = true);
    try {
      if (!llm.isLoaded) await llm.load();
      final bytes = await picked.readAsBytes();

      const visionPrompt = '''
You are looking at a photo a person took to ask a health-related question. In ONE short sentence (max 25 words), describe what you see in the frame, factually and concretely. If you can identify a wound, rash, injury, body part, medication label, or first-aid item, name it directly. If you cannot tell, say "I can't tell clearly from this photo." Do NOT diagnose. Do NOT speculate about cause or severity. Do NOT use the word "appears". Output only the sentence — no preamble.
''';

      final description = await llm.describeImage(
        imageBytes: bytes,
        prompt: visionPrompt,
      );
      if (!mounted) return;
      setState(() => _describingPhoto = false);

      final trimmed = description.trim();
      if (trimmed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Sema couldn't read the photo. Try again in better light."),
          ),
        );
        return;
      }
      // Feed it into the normal turn pipeline — the bubble shows the
      // description as the "user message", then triage + verbalize +
      // (optional) out-translate run as usual.
      await _send('I took a photo. $trimmed');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _describingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't describe the photo: $e")),
      );
    }
  }

  Future<void> _onCta(ReplyCta cta) async {
    switch (cta.kind) {
      case ReplyCtaKind.callEmergency:
        await _dialEmergency();
      case ReplyCtaKind.findHospital:
      case ReplyCtaKind.findClinic:
        await _openNearby();
      case ReplyCtaKind.openFirstAidEntry:
        if (cta.entryRef != null) await _onOpenEntry(cta.entryRef!);
      case ReplyCtaKind.none:
        break;
    }
  }

  Future<void> _dialEmergency() async {
    final uri = Uri(scheme: 'tel', path: _defaultEmergencyNumber);
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't open the dialer. Please call $_defaultEmergencyNumber manually.",
          ),
        ),
      );
    }
  }

  Future<void> _openNearby() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NearbyScreen()),
    );
  }

  /// Speak the reply's body via on-device TTS. We only voice the body
  /// (not headline / steps / donts / cta) — playing the structured
  /// list aloud sounded jarring in usability testing on the debug
  /// screen, and clinical steps are easier to read than to hear.
  Future<void> _playReply(SemaReply reply) async {
    final voice = _voiceOutput;
    if (voice == null) return;
    final text = reply.body.trim();
    if (text.isEmpty) return;
    await voice.speak(text);
  }

  /// Start a fresh conversation. The current one is preserved in the
  /// journal — `startNew` just creates a new row and flips the active
  /// id, it doesn't delete anything. We also stop any in-flight TTS
  /// and cancel a recording in progress so the previous chat's audio
  /// state doesn't leak into the new one.
  Future<void> _startNewChat() async {
    final store = _store;
    if (store == null) return;
    if (_thinking) return;

    await _voiceOutput?.stop();
    await _voiceInput?.cancel();

    final newId = await store.startNew(
      profileLabel: BioProfileStore.instance.current?.displayName,
    );
    if (!mounted) return;
    setState(() {
      _conversationId = newId;
      _stream = store.watch(newId);
      _greeted = false;
    });
    await _ensureGreeting();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Started a new chat. The previous one is in your journal.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onOpenEntry(String entryRef) async {
    final repo = await firstAidRepoFuture();
    final entry = repo.getById(entryRef);
    if (!mounted) return;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('First-aid entry "$entryRef" not found.')),
      );
      return;
    }
    await FirstAidDetailSheet.show(context, entry: entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _RoundIcon(
                  icon: PhosphorIconsRegular.caretLeft,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Sema',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: SemaColors.ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      _OnlineDot(),
                    ],
                  ),
                ),
                _RoundIcon(
                  icon: PhosphorIconsRegular.notePencil,
                  // Disabled while a turn is in flight — starting a new
                  // chat mid-stream would orphan the persisted reply
                  // updates from the agent's stream loop.
                  onTap: (_store != null && !_thinking) ? _startNewChat : null,
                ),
                const SizedBox(width: 8),
                _ProfilePill(
                  onTap: () => BioProfileSheet.show(
                    context,
                    initial: BioProfileStore.instance.current,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _bootstrapError != null
                ? _BootError(error: _bootstrapError!)
                : (_agent == null || _stream == null)
                    ? const _BootingView()
                    : StreamBuilder<List<ChatMessage>>(
                        stream: _stream,
                        builder: (context, snap) {
                          final msgs = snap.data ?? const [];
                          return _Transcript(
                            msgs: msgs,
                            thinking: _thinking,
                            scroll: _scroll,
                            onCta: _onCta,
                            onOpenEntry: _onOpenEntry,
                            onPlay: _voiceOutput == null ? null : _playReply,
                          );
                        },
                      ),
          ),
          _Composer(
            onSend: _send,
            enabled: _agent != null && _stream != null && !_thinking,
            voice: _voiceInput,
            // Camera affordance is only meaningful when we have Gemma
            // loaded on this device. Null hides the button entirely.
            onCamera: _llm == null ? null : _captureAndDescribePhoto,
            describingPhoto: _describingPhoto,
          ),
        ],
      ),
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsRegular.warning,
              size: 36, color: SemaColors.danger,
            ),
            const SizedBox(height: 12),
            const Text(
              "Couldn't start the chat",
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 16, fontWeight: FontWeight.w700,
                color: SemaColors.ink, letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12.5,
                color: SemaColors.inkMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootingView extends StatelessWidget {
  const _BootingView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator.adaptive(),
          SizedBox(height: 12),
          Text(
            'Loading first-aid library...',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: SemaColors.inkMid,
            ),
          ),
        ],
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.msgs,
    required this.thinking,
    required this.scroll,
    required this.onCta,
    required this.onOpenEntry,
    this.onPlay,
  });

  final List<ChatMessage> msgs;
  final bool thinking;
  final ScrollController scroll;
  final void Function(ReplyCta) onCta;
  final void Function(String) onOpenEntry;

  /// Optional play-aloud handler. Non-null only for locales with TTS
  /// support; the bubble shows a speaker affordance when present.
  final void Function(SemaReply reply)? onPlay;

  @override
  Widget build(BuildContext context) {
    if (msgs.isEmpty && !thinking) {
      return const _EmptyState();
    }
    final itemCount = msgs.length + (thinking ? 1 : 0);
    return ListView.separated(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      physics: const BouncingScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        if (thinking && i == msgs.length) {
          return const _TypingIndicator();
        }
        final m = msgs[i];
        return switch (m) {
          UserChatMessage() => _PlainBubble(
              text: m.text, fromMe: true, time: _hhmm(m.createdAt),
            ),
          SemaTextChatMessage() => _PlainBubble(
              text: m.text, fromMe: false, time: _hhmm(m.createdAt),
            ),
          SemaReplyChatMessage() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SemaReplyBubble(
                  reply: m.reply,
                  onCtaTap: onCta,
                  onOpenEntry: onOpenEntry,
                  onPlayAudio: onPlay,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _hhmm(m.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: SemaColors.inkSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
        };
      },
    );
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final hasProfile = BioProfileStore.instance.hasProfile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsRegular.handHeart,
              size: 36, color: SemaColors.inkMid,
            ),
            const SizedBox(height: 12),
            Text(
              hasProfile
                  ? 'Tell Sema what is going on'
                  : 'Save your profile to start',
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SemaColors.ink,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Sema works fully offline. Nothing leaves this phone.',
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: SemaColors.inkMid,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
      constraints: const BoxConstraints(maxWidth: 90),
      decoration: const BoxDecoration(
        color: SemaColors.card,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(0),
          SizedBox(width: 4),
          _Dot(150),
          SizedBox(width: 4),
          _Dot(300),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot(this.delayMs);
  final int delayMs;
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
      child: Container(
        width: 6, height: 6,
        decoration: const BoxDecoration(
          color: SemaColors.inkMid, shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;

  /// Null disables the button (greyed-out icon, taps are no-ops).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return PressScale(
      onTap: onTap ?? () {},
      child: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(
          color: SemaColors.card, shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 17,
          color: enabled ? SemaColors.ink : SemaColors.inkSoft,
        ),
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BioProfile?>(
      valueListenable: BioProfileStore.instance.listenable,
      builder: (context, profile, _) {
        if (profile == null) {
          return PressScale(
            onTap: onTap,
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(
                color: SemaColors.card, shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                PhosphorIconsRegular.userPlus,
                size: 17, color: SemaColors.ink,
              ),
            ),
          );
        }
        final label = profile.displayName?.isNotEmpty == true
            ? profile.displayName!
            : 'Profile';
        return PressScale(
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: SemaColors.card,
              borderRadius: BorderRadius.circular(SemaRadii.pill),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  PhosphorIconsRegular.user,
                  size: 14, color: SemaColors.ink,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: SemaColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6, height: 6,
          decoration: const BoxDecoration(
            color: SemaColors.online, shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          s.t('chat.online'),
          style: const TextStyle(
            fontSize: 11.5,
            color: SemaColors.online,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PlainBubble extends StatelessWidget {
  const _PlainBubble({
    required this.text,
    required this.fromMe,
    required this.time,
  });
  final String text;
  final bool fromMe;
  final String time;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.78;
    final cleaned = stripEmDashes(text);
    // Sema-side messages render flush against the page background so the
    // chat reads as a conversation, not a stack of bubbles. User
    // messages keep the dark pill so authorship is unambiguous.
    return Column(
      crossAxisAlignment:
          fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: fromMe
              ? const EdgeInsets.fromLTRB(15, 11, 15, 12)
              : EdgeInsets.zero,
          decoration: fromMe
              ? const BoxDecoration(
                  color: SemaColors.ink,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(6),
                  ),
                )
              : null,
          child: Text(
            cleaned,
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: fromMe ? Colors.white : SemaColors.ink,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            time,
            style: const TextStyle(
              fontSize: 11,
              color: SemaColors.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.onSend,
    required this.enabled,
    this.voice,
    this.onCamera,
    this.describingPhoto = false,
  });

  final ValueChanged<String> onSend;
  final bool enabled;

  /// Mic + STT controller. Null when the active locale lacks an
  /// on-device ASR model — the composer then renders the morphing
  /// mic/send circle as send-only.
  final VoiceInput? voice;

  /// Called when the user taps the camera button. Null hides the
  /// button (e.g. when Gemma vision isn't available on this device).
  final VoidCallback? onCamera;

  /// When true, the camera button shows a spinner and is disabled.
  /// Drives the user-visible "Sema is looking at the photo…" state.
  final bool describingPhoto;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _controller = TextEditingController();
  bool _hasText = false;
  bool _recording = false;
  bool _transcribing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    // If the user backs out mid-record, drop the captured audio so the
    // mic doesn't keep streaming after the screen is gone.
    if (_recording) widget.voice?.cancel();
    super.dispose();
  }

  void _send() {
    if (!_hasText || !widget.enabled) return;
    final text = _controller.text;
    _controller.clear();
    widget.onSend(text);
  }

  Future<void> _toggleRecord() async {
    final voice = widget.voice;
    if (voice == null) return;
    if (_recording) {
      // Stop → run ASR → fill the text field. We don't auto-send: the
      // user reviews the transcript first (a misheard "fever"/"liver"
      // shouldn't reach triage without a glance).
      setState(() {
        _recording = false;
        _transcribing = true;
      });
      final text = await voice.stop();
      if (!mounted) return;
      setState(() => _transcribing = false);
      if (text.isNotEmpty) {
        _controller.text = text;
        _controller.selection = TextSelection.collapsed(offset: text.length);
      } else if (voice.lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(voice.lastError.toString())),
        );
      }
      return;
    }
    final ok = await voice.start();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            voice.lastError?.toString() ?? "Couldn't start the mic.",
          ),
        ),
      );
      return;
    }
    setState(() => _recording = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleScope.of(context).strings;
    final canSend = _hasText && widget.enabled && !_recording;
    final voice = widget.voice;
    final canRecord = voice != null && widget.enabled && !_transcribing;
    // The right circle has three modes:
    //  - send  : there's text to send
    //  - mic   : empty + voice supported (tap to record)
    //  - mic-stop : currently recording (tap to stop+transcribe)
    // We branch on _hasText first so an in-progress draft always wins
    // over the mic affordance, even mid-record (very edge-case).
    final IconData rightIcon;
    final Color rightBg;
    final VoidCallback? rightTap;
    if (_hasText) {
      rightIcon = PhosphorIconsFill.paperPlaneRight;
      rightBg = canSend ? SemaColors.ink : SemaColors.inkSoft;
      rightTap = canSend ? _send : null;
    } else if (_recording) {
      rightIcon = PhosphorIconsFill.stop;
      rightBg = SemaColors.danger;
      rightTap = canRecord ? _toggleRecord : null;
    } else {
      rightIcon = PhosphorIconsBold.microphone;
      rightBg = canRecord ? SemaColors.ink : SemaColors.inkSoft;
      rightTap = canRecord ? _toggleRecord : null;
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.fromLTRB(18, 4, 8, 4),
                decoration: BoxDecoration(
                  color: SemaColors.card,
                  borderRadius: BorderRadius.circular(SemaRadii.pill),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        // Lock the field while recording / running ASR
                        // so a stray keystroke can't race against the
                        // transcript being injected.
                        enabled: widget.enabled &&
                            !_recording &&
                            !_transcribing,
                        decoration: InputDecoration(
                          hintText: _recording
                              ? 'Listening…'
                              : (_transcribing
                                  ? 'Transcribing…'
                                  : s.t('chat.typeMessage')),
                          border: InputBorder.none,
                          isDense: true,
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: _recording
                                ? SemaColors.danger
                                : SemaColors.inkMuted,
                            letterSpacing: -0.1,
                            fontWeight: _recording
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          color: SemaColors.ink,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    if (widget.onCamera != null)
                      IconButton(
                        onPressed: (widget.enabled && !widget.describingPhoto)
                            ? widget.onCamera
                            : null,
                        icon: widget.describingPhoto
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    SemaColors.inkMid,
                                  ),
                                ),
                              )
                            : const Icon(
                                PhosphorIconsRegular.camera,
                                color: SemaColors.inkMid, size: 20,
                              ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 36, height: 36,
                        ),
                        tooltip: 'Take a photo',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // The right circle stays put; AnimatedSwitcher cross-fades
            // between send / mic / stop. Recording state turns the
            // bubble red so the user can't miss that the mic is hot.
            PressScale(
              onTap: rightTap ?? () {},
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: rightBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Icon(
                    rightIcon,
                    key: ValueKey(rightIcon),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
