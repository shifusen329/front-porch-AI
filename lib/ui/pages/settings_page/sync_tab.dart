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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/utils.dart' show PlatformCaps;

import 'sync_flows.dart';
import 'sync_place_card.dart';

/// Settings → Sync: send this device's whole library to a sync place, or get
/// the one there. Nothing is merged; a Get replaces this library and keeps
/// it for an Undo.
class SyncTab extends StatefulWidget {
  const SyncTab({super.key});

  @override
  State<SyncTab> createState() => _SyncTabState();
}

class _SyncTabState extends State<SyncTab> {
  late final TextEditingController _deviceName;
  bool _showVersions = false;

  @override
  void initState() {
    super.initState();
    final sync = context.read<LibrarySyncService>();
    _deviceName = TextEditingController(text: sync.settings.deviceName);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await sync.refresh();
      if (sync.state.lastSync != null) await sync.checkHere();
    });
  }

  @override
  void dispose() {
    _deviceName.dispose();
    super.dispose();
  }

  // Material, not a coloured Container: the switches' ink paints on the
  // nearest Material and a coloured box between would hide it.
  Widget _card(BuildContext context, List<Widget> children) => Material(
    color: AppColors.cardOf(context),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Text _dim(BuildContext context, String text) =>
      Text(text, style: TextStyle(color: AppColors.textSecondary(context)));

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<LibrarySyncService>();
    if (sync.disabled) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [_dim(context, kSyncDisabledReason)],
      );
    }
    final ready = sync.settings.isConfigured && !sync.busy;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader('Sync'),
        const SizedBox(height: 8),
        _dim(
          context,
          'Send this device\'s whole library to a place you own, and get it '
          'on your other devices. Characters, chats, personas, groups, worlds, '
          'lorebooks, the Data Bank, journals, presets and backgrounds travel. '
          'Models, backends and keys, voices and appearance stay on each '
          'device. Your chats are uploaded as they are to the place you choose.',
        ),
        const SizedBox(height: 16),
        SyncPlaceCard(sync: sync),
        const SizedBox(height: 12),
        _card(context, [
          const Text(
            'This device',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Focus(
            canRequestFocus: false,
            onFocusChange: (focused) {
              if (!focused) sync.settings.setDeviceName(_deviceName.text);
            },
            child: TextField(
              controller: _deviceName,
              decoration: InputDecoration(
                labelText: 'Name on the sync place',
                hintText: sync.deviceName,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: sync.settings.setDeviceName,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _card(context, [
          const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._status(context, sync),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: ready ? () => runSyncSend(context, sync) : null,
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text('Send my library'),
              ),
              OutlinedButton.icon(
                onPressed: ready ? () => runSyncGet(context, sync) : null,
                icon: const Icon(Icons.cloud_download_rounded, size: 18),
                label: const Text('Get the library'),
              ),
              if (sync.undoRecord != null)
                TextButton.icon(
                  onPressed: ready ? () => runSyncUndo(context, sync) : null,
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: Text(
                    'Undo the Get from ${syncWhen(sync.undoRecord!.at)}',
                  ),
                ),
            ],
          ),
          if (sync.busy) ...[
            const SizedBox(height: 12),
            _progress(context, sync),
          ],
        ]),
        const SizedBox(height: 12),
        ..._versions(context, sync, ready),
        _card(context, [
          const Text(
            'Automatic',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: AppColors.porchAmberOf(context),
            title: Text(
              PlatformCaps.current.usesMobileShell
                  ? 'Send my library when I leave the app'
                  : 'Send my library when I close the app',
            ),
            subtitle: const Text(
              'Skipped when another device sent a newer library.',
            ),
            value: sync.settings.sendOnClose,
            onChanged: sync.settings.setSendOnClose,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: AppColors.porchAmberOf(context),
            title: const Text('Check for a newer library when the app starts'),
            subtitle: const Text('It asks first; it never replaces anything.'),
            value: sync.settings.checkOnStart,
            onChanged: sync.settings.setCheckOnStart,
          ),
        ]),
      ],
    );
  }

  List<Widget> _status(BuildContext context, LibrarySyncService sync) {
    final remote = sync.remote;
    final last = sync.state.lastSync;
    final here = sync.here;
    return [
      if (sync.remoteError != null)
        Text(
          sync.remoteError!,
          style: TextStyle(color: StatusColors.dangerOf(context)),
        )
      else if (!sync.settings.isConfigured)
        _dim(context, 'Set up a sync place above.')
      else if (remote == null)
        _dim(context, 'Nothing has been sent to the sync place yet.')
      else
        Text(
          'On the sync place: ${remote.head.headEntry?.device ?? 'a device'}\'s '
          'library, ${syncWhen(remote.head.headEntry?.sentAt ?? DateTime.now())}'
          '${remote.manifest == null ? '' : ' · ${syncSummary(remote.manifest!)}'}'
          '${remote.newer ? ' · newer than this device\'s' : ''}',
        ),
      const SizedBox(height: 4),
      _dim(
        context,
        last == null
            ? 'This device hasn\'t synced yet.'
            : '${last.sent ? 'Sent' : 'Got'} ${syncWhen(last.at)}'
                  '${last.sent ? '' : ' from ${last.device}'}.',
      ),
      if (sync.phase == SyncPhase.checking)
        _dim(context, 'Checking this device for changes…')
      else if (here != null && last != null)
        _dim(
          context,
          describeLocalChanges(
            neverSynced: here.neverSynced,
            unknown: here.unknown,
            changes: here.changes,
            chatNames: here.titles,
          ),
        ),
      if (sync.needsRestart != null) ...[
        const SizedBox(height: 4),
        Text(
          sync.needsRestart!,
          style: TextStyle(color: StatusColors.dangerOf(context)),
        ),
      ],
    ];
  }

  Widget _progress(BuildContext context, LibrarySyncService sync) {
    final label = switch (sync.phase) {
      SyncPhase.packing => 'Packing this device\'s library…',
      SyncPhase.sending => 'Sending',
      SyncPhase.fetching => 'Getting the library',
      SyncPhase.replacing => 'Replacing this device\'s library…',
      SyncPhase.checking => 'Checking…',
      SyncPhase.idle => '',
    };
    final total = sync.progressTotal;
    final amount = total > 0
        ? ' · ${syncSize(sync.progressDone)} of ${syncSize(total)}'
        : '';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: total > 0 ? sync.progressDone / total : null,
                color: AppColors.porchAmberOf(context),
              ),
              const SizedBox(height: 4),
              _dim(context, '$label$amount'),
            ],
          ),
        ),
        if (!sync.replacing && sync.phase != SyncPhase.checking)
          TextButton(onPressed: sync.cancel, child: const Text('Cancel')),
      ],
    );
  }

  List<Widget> _versions(
    BuildContext context,
    LibrarySyncService sync,
    bool ready,
  ) {
    final head = sync.remote?.head;
    final earlier = [
      for (final s in head?.snapshots ?? const <SnapshotEntry>[])
        if (s.id != head?.head) s,
    ];
    if (earlier.isEmpty) return const [];
    return [
      _card(context, [
        InkWell(
          onTap: () => setState(() => _showVersions = !_showVersions),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Earlier versions on the sync place',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Icon(_showVersions ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
        if (_showVersions)
          for (final s in earlier)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${s.device} · ${syncWhen(s.sentAt)}'),
              subtitle: s.pinned
                  ? const Text('Kept because a newer one replaced it')
                  : null,
              trailing: TextButton(
                onPressed: ready
                    ? () => runSyncGet(context, sync, snapshotId: s.id)
                    : null,
                child: const Text('Get this one'),
              ),
            ),
      ]),
      const SizedBox(height: 12),
    ];
  }
}
