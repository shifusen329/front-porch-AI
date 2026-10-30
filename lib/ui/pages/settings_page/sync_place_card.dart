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
import 'package:front_porch_ai/utils/utils.dart' show PlatformCaps;

/// Where this device syncs: a WebDAV server (Nextcloud and the like) or, on
/// a desktop, a folder (a NAS share, or one a sync program keeps).
class SyncPlaceCard extends StatefulWidget {
  const SyncPlaceCard({super.key, required this.sync});

  final LibrarySyncService sync;

  @override
  State<SyncPlaceCard> createState() => _SyncPlaceCardState();
}

class _SyncPlaceCardState extends State<SyncPlaceCard> {
  late SyncPlaceKind _kind;
  late final TextEditingController _url;
  late final TextEditingController _user;
  final _password = TextEditingController();
  late final TextEditingController _folderName;
  late final TextEditingController _folderPath;
  bool _passwordSaved = false;
  bool _working = false;
  String? _result;
  bool _resultOk = false;

  SyncSettings get _settings => widget.sync.settings;

  @override
  void initState() {
    super.initState();
    final folders = PlatformCaps.current.canPickDirectories;
    _kind =
        _settings.kind == SyncPlaceKind.none ||
            (_settings.kind == SyncPlaceKind.folder && !folders)
        ? SyncPlaceKind.webdav
        : _settings.kind;
    _url = TextEditingController(text: _settings.serverUrl);
    _user = TextEditingController(text: _settings.username);
    _folderName = TextEditingController(text: _settings.folderName);
    _folderPath = TextEditingController(text: _settings.folderPath);
    widget.sync.passwords.read().then(
      (p) {
        if (mounted) setState(() => _passwordSaved = p != null);
      },
      onError: (Object e) {
        if (mounted) setState(() => _result = '$e');
      },
    );
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    _folderName.dispose();
    _folderPath.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    try {
      if (_password.text.isNotEmpty) {
        await widget.sync.passwords.save(_password.text);
        _password.clear();
        _passwordSaved = true;
      }
      await _settings.setPlace(
        kind: _kind,
        serverUrl: _url.text,
        username: _user.text,
        folderPath: _folderPath.text,
        folderName: _folderName.text,
      );
      return true;
    } on SyncPasswordStoreException catch (e) {
      setState(() {
        _result = e.message;
        _resultOk = false;
      });
      return false;
    }
  }

  Future<void> _saveAndTest() async {
    if (_working) return;
    setState(() {
      _working = true;
      _result = null;
    });
    final saved = await _save();
    final error = saved ? await widget.sync.testConnection() : _result;
    if (!mounted) return;
    setState(() {
      _working = false;
      _resultOk = error == null;
      _result = error ?? 'Connected. This place can hold your library.';
    });
    if (error == null) await widget.sync.refresh();
  }

  Future<void> _browse() async {
    final path = await GuardedPicker.getDirectoryPath(
      context,
      category: 'sync_folder',
      dialogTitle: 'Choose the sync folder',
    );
    if (path != null && mounted) setState(() => _folderPath.text = path);
  }

  InputDecoration _field(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) {
    final folders = PlatformCaps.current.canPickDirectories;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sync place',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (folders)
            Wrap(
              spacing: 8,
              children: [
                for (final kind in const [
                  SyncPlaceKind.webdav,
                  SyncPlaceKind.folder,
                ])
                  ChoiceChip(
                    label: Text(
                      kind == SyncPlaceKind.webdav
                          ? 'WebDAV server'
                          : 'A folder',
                    ),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          if (_kind == SyncPlaceKind.webdav) ...[
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: _field(
                'Server address',
                hint: 'https://cloud.example.com/remote.php/dav/files/you/',
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: _user, decoration: _field('Username')),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: _field(
                'App password',
                hint: _passwordSaved ? 'Saved on this device' : null,
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _folderPath,
                    decoration: _field('Folder'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _browse, child: const Text('Browse')),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _folderName,
            decoration: _field('Folder the app creates there'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: _working ? null : _saveAndTest,
                child: Text(
                  _working ? 'Checking…' : 'Save and test connection',
                ),
              ),
            ],
          ),
          if (_result != null) ...[
            const SizedBox(height: 8),
            Text(
              _result!,
              style: TextStyle(
                color: _resultOk
                    ? StatusColors.successOf(context)
                    : StatusColors.dangerOf(context),
              ),
            ),
          ],
          if (_kind == SyncPlaceKind.webdav) ...[
            const SizedBox(height: 8),
            Text(
              'For Nextcloud, make an app password under Settings → '
              'Security. The password stays in this device\'s key store.',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ],
        ],
      ),
    );
  }
}
