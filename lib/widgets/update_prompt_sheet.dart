import 'package:flutter/material.dart';

import '../pages/update_page.dart';
import '../services/update/update_controller.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'release_notes_view.dart';

/// 发现新版本时的底部提示；负责「立即更新 / 以后再说 / 跳过此版本」。
Future<void> showUpdatePrompt(
  BuildContext context,
  UpdateController controller,
) {
  final release = controller.release;
  if (release == null) return Future<void>.value();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final palette = BeanPalette.of(sheetContext);
      return BeanSheet(
        title: '发现新版本',
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'v${release.version}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    release.sizeLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '来自 GitHub Releases',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              const SizedBox(height: 16),
              ReleaseNotesView(notes: release.notes),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('update-now'),
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    navigator.push(
                      MaterialPageRoute<void>(
                        builder: (_) => UpdatePage(controller: controller),
                      ),
                    );
                  },
                  child: const Text('立即更新'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('update-later'),
                      onPressed: () async {
                        await controller.dismiss();
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      child: const Text('以后再说'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('update-skip'),
                      onPressed: () async {
                        await controller.skipVersion();
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      child: const Text('跳过此版本'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
