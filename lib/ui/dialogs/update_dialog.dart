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

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart' show PlatformCaps;

/// Dialog shown when a new version is available.
/// Three stages: prompt → downloading → ready to install.
/// User can always dismiss — never forced.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: Provider.of<UpdateService>(context, listen: false),
        child: const UpdateDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateService>(
      builder: (context, service, _) {
        if (service.downloadComplete) {
          return _buildReadyToInstallDialog(context, service);
        }
        if (service.downloading) {
          return _buildDownloadingDialog(context, service);
        }
        return _buildPromptDialog(context, service);
      },
    );
  }

  /// Stage 1: "A new version is available, would you like to download?"
  Widget _buildPromptDialog(BuildContext context, UpdateService service) {
    return AlertDialog(
      // A phone on its side is too short for the notes; it scrolls.
      scrollable: PlatformCaps.current.usesMobileShell,
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            Icons.system_update,
            color: StatusColors.successOf(context),
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            'Update Available',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 14,
              ),
              children: [
                const TextSpan(
                  text: 'A new version of Front Porch AI is available.\n\n',
                ),
                TextSpan(
                  text: 'Current: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                TextSpan(text: '${service.displayCurrentVersion}\n'),
                TextSpan(
                  text: 'Latest: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: StatusColors.successOf(context),
                  ),
                ),
                TextSpan(text: '${service.displayLatestVersion}\n'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildChangelogSection(context, service),
          const SizedBox(height: 16),
          Text(
            'Would you like to download the update?',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 14,
            ),
          ),
          // A phone carries no community links (app_destinations.dart).
          if (!PlatformCaps.current.usesMobileShell) ..._kofi(context),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Not Now',
            style: TextStyle(color: AppColors.textTertiary(context)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            await service.downloadUpdate();
            final error = service.downloadError;
            if (error == null || !context.mounted) return;
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Download failed: $error'),
                backgroundColor: StatusColors.errorFill,
              ),
            );
          },
          icon: const Icon(Icons.download, size: 18),
          label: Text('Download'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StatusColors.successFillOf(context),
            foregroundColor: StatusColors.onFill,
          ),
        ),
      ],
    );
  }

  List<Widget> _kofi(BuildContext context) {
    return [
      const SizedBox(height: 16),
      Divider(color: AppColors.borderOf(context)),
      const SizedBox(height: 12),
      Text(
        '☕ Enjoying Front Porch AI?',
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'This project is free, open source, and built with love. If you enjoy this program please consider buying me a coffee. It helps keep development going!',
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 13,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () =>
              launchUrl(Uri.parse('https://ko-fi.com/sosukeaizen37411')),
          icon: const Icon(Icons.coffee_outlined, size: 18),
          label: Text('Support on Ko-fi'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AccentColors.kofiOf(context),
            side: BorderSide(color: AccentColors.kofiOf(context), width: 1),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    ];
  }

  /// Renders the non-technical "What's New" changelog from the update feed's
  /// notes. Uses flutter_markdown_plus inside a constrained scroll area so
  /// long release notes do not blow out the AlertDialog.
  Widget _buildChangelogSection(BuildContext context, UpdateService service) {
    final notes = service.releaseNotes.trim();
    if (notes.isEmpty) {
      return Text(
        'No release notes for this version.',
        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "What's New in ${service.displayLatestVersion}",
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: MarkdownBody(
              data: notes,
              selectable: true,
              onTapLink: (text, href, title) async {
                if (href != null) {
                  await launchUrl(
                    Uri.parse(href),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                  height: 1.35,
                ),
                h1: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                h2: TextStyle(
                  color: StatusColors.successOf(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                listBullet: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                ),
                a: TextStyle(
                  color: AppColors.porchAmberOf(context),
                  decoration: TextDecoration.underline,
                ),
                em: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontStyle: FontStyle.italic,
                ),
                strong: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Stage 2: Download in progress
  Widget _buildDownloadingDialog(BuildContext context, UpdateService service) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Downloading Update...',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: service.downloadProgress > 0
                ? service.downloadProgress
                : null,
            backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              StatusColors.successOf(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${(service.downloadProgress * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  /// Stage 3: Download complete — "Ready to install now?"
  Widget _buildReadyToInstallDialog(
    BuildContext context,
    UpdateService service,
  ) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: StatusColors.successOf(context),
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            'Ready to Install',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Platform.isAndroid
                ? 'The update has been downloaded. Android will ask you to '
                      'confirm installing it.'
                : 'The update has been downloaded. Would you like to install it now?',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            Platform.isAndroid
                ? 'If you choose "Later", you\'ll be asked again the next time '
                      'the app starts.'
                : Platform.isLinux
                ? 'If you choose "Later", the update will be applied when you close the app.'
                : 'If you choose "Later", the update will install automatically when you close the app.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Later',
            style: TextStyle(color: AppColors.textTertiary(context)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            // Installing quits the app, so unsaved edits are asked about
            // first, as on the window close.
            if (!await UnsavedChanges.instance.confirmLeave(context)) return;
            // The first time, Android must be told this app may install
            // apps; its settings page opens, and Install is tapped again.
            if (Platform.isAndroid && !await ApkInstaller.canInstall()) {
              await ApkInstaller.openInstallPermission();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Allow Front Porch AI to install apps, then tap '
                    'Install again.',
                  ),
                ),
              );
              return;
            }
            try {
              await service.installNow();
            } catch (e) {
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Update failed: $e'),
                    backgroundColor: StatusColors.errorFill,
                  ),
                );
              }
            }
          },
          icon: Icon(
            Platform.isAndroid ? Icons.install_mobile : Icons.install_desktop,
            size: 18,
          ),
          label: Text(Platform.isAndroid ? 'Install' : 'Install Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StatusColors.successFillOf(context),
            foregroundColor: StatusColors.onFill,
          ),
        ),
      ],
    );
  }
}
