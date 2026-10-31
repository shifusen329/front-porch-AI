// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The command line the Windows update runs its installer with.
///
/// [installDir] is the folder of the running build, so the update lands on
/// top of it (see `_launchWindowsInstaller`). [showLicense] shows the
/// license page (the GPL to AGPL step); otherwise it is fully silent.
/// [relaunch] asks installers/windows/setup.iss to open the app again once
/// the files are in: "Install now" does, an update on close does not.
List<String> windowsInstallerArgs({
  required String installDir,
  required bool showLicense,
  required bool relaunch,
}) {
  var dir = installDir;
  // A trailing backslash would escape the closing quote in the generated
  // command line.
  while (dir.endsWith('\\')) {
    dir = dir.substring(0, dir.length - 1);
  }
  return [
    showLicense ? '/SILENT' : '/VERYSILENT',
    '/DIR=$dir',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
    if (relaunch) '/RELAUNCH=1',
  ];
}
