// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

void _report(BuildContext context, SyncOutcome outcome) {
  final text = switch (outcome) {
    SyncDone(:final message) => message,
    SyncFailed(:final message) => message,
    _ => null,
  };
  if (text == null || !context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(text)));
}

/// Send my library, asking first when the place holds a library this
/// device hasn't got.
Future<void> runSyncSend(BuildContext context, LibrarySyncService sync) async {
  var outcome = await sync.send();
  if (outcome is SendNeedsChoice) {
    if (!context.mounted) return;
    final conflict = outcome.conflict;
    final theirs = conflict.theirs;
    final who = theirs == null
        ? 'Another device'
        : '${theirs.device} (${syncWhen(theirs.sentAt)})';
    final other = conflict.kind == SendConflictKind.otherLibrary;
    final choice = await showWarmDialog<String>(
      context,
      title: other
          ? 'A different library is there'
          : 'A newer library is there',
      icon: Icons.sync_problem_rounded,
      width: 420,
      content: WarmDialogText(
        other
            ? 'The sync place holds a library this device never synced with, '
                  'last sent by $who. Sending makes yours the newest; theirs '
                  'stays on the sync place under Earlier versions.'
            : '$who sent a library that this device hasn\'t got. Get theirs '
                  'first, or send yours anyway: theirs stays on the sync '
                  'place under Earlier versions.',
      ),
      actions: [
        warmDialogCancel(context),
        TextButton(
          onPressed: () => Navigator.of(context).pop('send'),
          child: Text(
            'Send mine anyway',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        if (!other)
          warmDialogConfirm(
            context,
            label: 'Get theirs first',
            onPressed: () => Navigator.of(context).pop('get'),
          ),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'get') return runSyncGet(context, sync);
    if (choice != 'send') return;
    outcome = await sync.send(overwriteTheirs: true);
  }
  if (context.mounted) _report(context, outcome);
}

/// Get the library: fetch and check it, then one confirm, or Keep mine /
/// Take theirs when this device changed since its last sync.
Future<void> runSyncGet(
  BuildContext context,
  LibrarySyncService sync, {
  String? snapshotId,
}) async {
  final outcome = await sync.prepareGet(snapshotId: snapshotId);
  if (outcome is! GetReady) {
    if (context.mounted) _report(context, outcome);
    return;
  }
  if (!context.mounted) {
    await sync.discardGet();
    return;
  }
  final theirs = outcome.theirs;
  final summary =
      '${theirs.device}\'s library from ${syncWhen(theirs.sentAt)}: '
      '${syncSummary(theirs)}.';
  final take = outcome.conflicts
      ? await showWarmDialog<bool>(
          context,
          title: 'Keep mine or take theirs?',
          icon: Icons.compare_arrows_rounded,
          width: 440,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WarmDialogText(summary),
              const SizedBox(height: 12),
              WarmDialogText(
                describeLocalChanges(
                  neverSynced: outcome.neverSynced,
                  unknown: outcome.unknownChanges,
                  changes: outcome.changes,
                  chatNames: outcome.changedChats,
                ),
              ),
              const SizedBox(height: 12),
              const WarmDialogText(
                'Take theirs replaces this device\'s library and sets it '
                'aside; Undo puts it back for 7 days. Keep mine changes '
                'nothing here.',
              ),
            ],
          ),
          actions: [
            warmDialogCancel(context, label: 'Keep mine', value: false),
            warmDialogConfirm(
              context,
              label: 'Take theirs',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        )
      : await showWarmDialog<bool>(
          context,
          title: 'Get the library?',
          icon: Icons.cloud_download_rounded,
          width: 420,
          content: WarmDialogText(
            'Replace this device\'s library with $summary This device\'s '
            'library is set aside; Undo puts it back for 7 days.',
          ),
          actions: [
            warmDialogCancel(context),
            warmDialogConfirm(
              context,
              label: 'Get it',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
  if (take != true) {
    await sync.discardGet();
    return;
  }
  final applied = await sync.applyGet();
  if (context.mounted) _report(context, applied);
}

/// Puts back what the last Get set aside, after one confirm.
Future<void> runSyncUndo(BuildContext context, LibrarySyncService sync) async {
  final record = sync.undoRecord;
  if (record == null) return;
  final ok = await showWarmDialog<bool>(
    context,
    title: 'Undo the last Get?',
    icon: Icons.undo_rounded,
    width: 420,
    content: WarmDialogText(
      'Put back this device\'s library from before ${syncWhen(record.at)}, '
      'when ${record.device}\'s replaced it. Work done here since then is '
      'set aside.',
    ),
    actions: [
      warmDialogCancel(context),
      warmDialogConfirm(
        context,
        label: 'Put it back',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  if (ok != true) return;
  final outcome = await sync.undo();
  if (context.mounted) _report(context, outcome);
}

/// At start, when the switch is on: offer a newer library, never take it.
Future<void> offerNewerLibrary(
  BuildContext context,
  LibrarySyncService sync,
) async {
  final entry = sync.remote?.head.headEntry;
  if (entry == null) return;
  final get = await showWarmDialog<bool>(
    context,
    title: 'A newer library is on your sync place',
    icon: Icons.cloud_sync_rounded,
    width: 400,
    content: WarmDialogText(
      '${entry.device} sent a library at ${syncWhen(entry.sentAt)}.',
    ),
    actions: [
      warmDialogCancel(context, label: 'Not now'),
      warmDialogConfirm(
        context,
        label: 'Get it',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  if (get == true && context.mounted) await runSyncGet(context, sync);
}
