import 'dart:async';

import 'package:flutter/material.dart';

import '../ml/model_downloader.dart';
import '../theme/tokens.dart';
import 'sema_button.dart';

/// Modal bottom sheet that runs a [ModelDownloader.ensureLanguage] stream
/// and shows aggregate + per-file progress. Returns `true` when every
/// file in the bundle is on disk, `false` if the user cancelled or an
/// error was acknowledged.
///
/// Dismissable: tapping the backdrop only works once the download is
/// done — mid-stream we keep the sheet up so progress isn't lost. The
/// user can still cancel via the in-sheet button.
Future<bool> showModelDownloadSheet({
  required BuildContext context,
  required ModelDownloader downloader,
  required String langCode,
  required String langDisplayName,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: SemaColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(SemaRadii.xl)),
    ),
    builder: (_) => _ModelDownloadSheet(
      downloader: downloader,
      langCode: langCode,
      langDisplayName: langDisplayName,
    ),
  );
  return ok ?? false;
}

class _ModelDownloadSheet extends StatefulWidget {
  const _ModelDownloadSheet({
    required this.downloader,
    required this.langCode,
    required this.langDisplayName,
  });

  final ModelDownloader downloader;
  final String langCode;
  final String langDisplayName;

  @override
  State<_ModelDownloadSheet> createState() => _ModelDownloadSheetState();
}

class _ModelDownloadSheetState extends State<_ModelDownloadSheet> {
  StreamSubscription<BundleProgress>? _sub;
  BundleProgress? _progress;
  Object? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _sub?.cancel();
    setState(() {
      _error = null;
      _done = false;
    });
    _sub = widget.downloader
        .ensureLanguage(widget.langCode)
        .listen(
      (p) => setState(() => _progress = p),
      onError: (Object e) => setState(() => _error = e),
      onDone: () => setState(() => _done = _progress?.isComplete ?? false),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = _progress;
    final bundleMB =
        p == null ? '–' : (p.bytesTotal / (1024 * 1024)).toStringAsFixed(0);
    final gotMB =
        p == null ? '0' : (p.bytesReceived / (1024 * 1024)).toStringAsFixed(0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: SemaColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Downloading models', style: t.labelMedium),
            const SizedBox(height: 6),
            Text(
              widget.langDisplayName,
              style: t.displayMedium!
                  .copyWith(fontSize: 26, height: 1.1, letterSpacing: -1.0),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(SemaRadii.pill),
              child: LinearProgressIndicator(
                value: p?.fraction,
                minHeight: 8,
                backgroundColor: SemaColors.card,
                color: SemaColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$gotMB / $bundleMB MB',
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12.5,
                color: SemaColors.inkMuted,
              ),
            ),
            const SizedBox(height: 14),
            if (p != null)
              ...p.files.map((fp) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _FileRow(progress: fp),
                  )),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SemaColors.card,
                  borderRadius: BorderRadius.circular(SemaRadii.l),
                ),
                child: Text(
                  'Download failed: $_error',
                  style: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 12.5,
                    color: SemaColors.ink,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (!_done && _error == null)
                  Expanded(
                    child: SemaButton(
                      label: 'Cancel',
                      variant: SemaButtonVariant.secondary,
                      onPressed: () {
                        _sub?.cancel();
                        Navigator.of(context).pop(false);
                      },
                    ),
                  ),
                if (_error != null) ...[
                  Expanded(
                    child: SemaButton(
                      label: 'Cancel',
                      variant: SemaButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SemaButton(
                      label: 'Retry',
                      onPressed: _start,
                    ),
                  ),
                ],
                if (_done)
                  Expanded(
                    child: SemaButton(
                      label: 'Continue',
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.progress});
  final FileProgress progress;

  @override
  Widget build(BuildContext context) {
    final mb = (progress.total / (1024 * 1024)).toStringAsFixed(0);
    final got = (progress.received / (1024 * 1024)).toStringAsFixed(0);
    final label = progress.file.kind.toUpperCase();
    final status = switch (progress.state) {
      FileState.alreadyPresent => 'already on device',
      FileState.done => 'done',
      FileState.downloading => '$got / $mb MB',
      FileState.verifying => 'verifying…',
      FileState.failed => 'failed',
      FileState.pending => 'queued',
    };
    return Row(
      children: [
        Container(
          width: 38,
          padding: const EdgeInsets.symmetric(vertical: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SemaColors.card,
            borderRadius: BorderRadius.circular(SemaRadii.pill),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: SemaColors.ink,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            progress.file.path,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 12.5,
              color: SemaColors.ink,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          status,
          style: const TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 11.5,
            color: SemaColors.inkMuted,
          ),
        ),
      ],
    );
  }
}
