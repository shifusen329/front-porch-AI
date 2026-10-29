// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Publishes an app update: builds the Windows installer and the Android APK
// at VERSION, uploads both beside the update feed (latest.json) installed
// copies read (kUpdateFeedUrl in lib/services/update_service.dart), and
// writes the feed last, so no one is offered a file that is not all there.
//
//   dart run tools/publish_update.dart 1.0.1 [--notes notes.md] [--dry-run]
//
// Run on Windows from the repository root. --dry-run builds and writes
// build/update/latest.json without uploading. The server comes from
// tools/publish_update.env (gitignored; KEY=value lines) or the environment:
//
//   FPAI_UPDATE_SSH  user@host the files are copied to
//   FPAI_UPDATE_KEY  ssh key file (optional)
//   FPAI_UPDATE_DIR  the server folder published as FPAI_UPDATE_URL
//   FPAI_UPDATE_URL  that folder's public URL
//
// lib/app_version.dart is left stamped with VERSION, to be committed.
// pubspec.yaml is not touched: the builds get --build-name/--build-number.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
// Not the update/ barrel: it carries a Flutter platform channel, and this
// runs under plain `dart run`.
import 'package:front_porch_ai/services/update/update_feed.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const _appVersionFile = 'lib/app_version.dart';
const _setupScript = 'installers/windows/setup.iss';
const _setupOutput = 'installers/windows/Front_Porch_AI_Setup.exe';
const _windowsBuild = 'build/windows/x64/runner/Release';
const _vcRedist = 'build/windows/x64/runner/vc_redist.x64.exe';
const _apkOutput = 'build/app/outputs/flutter-apk/app-debug.apk';
const _gradleApk = 'build/app/outputs/apk/debug/app-debug.apk';
final _ours = RegExp(
  r'^Front_Porch_AI_(?:Setup_)?(\d+\.\d+\.\d+)\.(?:exe|apk)$',
);

Future<void> main(List<String> args) async {
  try {
    await _publish(args);
  } on _Stop catch (e) {
    stderr.writeln('publish_update: ${e.message}');
    exitCode = 1;
  }
}

Future<void> _publish(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final notesAt = args.indexOf('--notes');
  final notesPath = notesAt >= 0 && notesAt + 1 < args.length
      ? args[notesAt + 1]
      : null;
  final rest = [
    for (var i = 0; i < args.length; i++)
      if (!args[i].startsWith('--') && (notesAt < 0 || i != notesAt + 1))
        args[i],
  ];
  if (rest.length != 1) {
    throw _Stop(
      'usage: dart run tools/publish_update.dart VERSION '
      '[--notes notes.md] [--dry-run]',
    );
  }
  final version = rest.single;
  final parts = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
  if (parts == null) {
    throw _Stop('VERSION must be MAJOR.MINOR.PATCH (one stable channel)');
  }
  final minor = int.parse(parts[2]!), patch = int.parse(parts[3]!);
  if (minor > 99 || patch > 99) throw _Stop('minor and patch must be < 100');
  // Android only installs a higher versionCode over the installed app.
  final versionCode =
      int.parse(parts[1]!) * 1000000 + minor * 10000 + patch * 100;
  if (!Platform.isWindows) {
    throw _Stop('the Windows installer builds on Windows');
  }
  if (!File(_setupScript).existsSync()) {
    throw _Stop('run from the repository root');
  }
  final notes = notesPath == null ? '' : await File(notesPath).readAsString();

  final env = {..._readEnvFile(), ...Platform.environment};
  String need(String key) => env[key]?.trim().isNotEmpty == true
      ? env[key]!.trim()
      : throw _Stop('$key is not set');
  final folder = need('FPAI_UPDATE_URL');
  final feedUrl = Uri.parse(
    folder.endsWith('/') ? folder : '$folder/',
  ).resolve('latest.json');
  final ssh = _Ssh(
    dryRun ? '' : need('FPAI_UPDATE_SSH'),
    env['FPAI_UPDATE_KEY'],
    dryRun ? '' : need('FPAI_UPDATE_DIR'),
  );

  final live = await _liveFeed(feedUrl);
  if (live != null && !isNewerVersion(version, live.version)) {
    throw _Stop('the server already has ${live.version}; publish a newer one');
  }
  stdout.writeln(
    'Publishing $version (versionCode $versionCode) over '
    '${live?.version ?? 'nothing'}',
  );

  final stamp = File(_appVersionFile);
  final unstamped = await stamp.readAsString();
  // No line end in the pattern: the file's own (CRLF here) is kept.
  final line = RegExp(r"^const String appVersion = '[^']*';", multiLine: true);
  if (!line.hasMatch(unstamped)) {
    throw _Stop('no appVersion line in $_appVersionFile');
  }
  await stamp.writeAsString(
    unstamped.replaceFirst(line, "const String appVersion = '$version';"),
  );
  final buildArgs = ['--build-name=$version', '--build-number=$versionCode'];
  try {
    await _run(_flutter(), ['build', 'windows', '--release', ...buildArgs]);
    await _vcRedistOnce();
    await _run(_iscc(), [
      '/DMyAppVersion=$version',
      '/DMyAppBuildDir=${p.absolute(_windowsBuild)}',
      '/DMyAppLicenseFile=${p.absolute('LICENSE')}',
      '/DMyAppIconFile=${p.absolute('windows/runner/resources/app_icon.ico')}',
      _setupScript,
    ]);
    // Debug packaging rewrites the last APK in place and leaves the old
    // kernel's bytes behind as dead space (about 54 MB every phone would
    // download); starting from no APK packages only what is in it.
    for (final old in [_gradleApk, _apkOutput]) {
      final apk = File(old);
      if (apk.existsSync()) apk.deleteSync();
    }
    // Debug-signed, like the phone builds already installed: Android only
    // updates an app signed with the same key.
    await _run(_flutter(), ['build', 'apk', '--debug', ...buildArgs]);
  } catch (_) {
    await stamp.writeAsString(unstamped);
    rethrow;
  }

  final windows = await _Upload.of(
    _setupOutput,
    'Front_Porch_AI_Setup_$version.exe',
  );
  final android = await _Upload.of(_apkOutput, 'Front_Porch_AI_$version.apk');
  final feed = const JsonEncoder.withIndent('  ').convert({
    'version': version,
    'published': DateTime.now().toUtc().toIso8601String(),
    if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    'windows': windows.entry,
    'android': {...android.entry, 'versionCode': versionCode},
  });
  final local = File('build/update/latest.json');
  await local.parent.create(recursive: true);
  await local.writeAsString('$feed\n');
  if (dryRun) {
    stdout.writeln('Dry run: wrote ${local.path}; nothing uploaded.');
    return;
  }

  await ssh.copy(windows.path, windows.name);
  await ssh.copy(android.path, android.name);
  await ssh.copy(local.path, 'latest.json.tmp');
  // One rename on the server: the old feed until the new one is whole.
  await ssh.run("mv -f '${ssh.dir}/latest.json.tmp' '${ssh.dir}/latest.json'");

  // Keep this version and the one before it (someone may be mid-download).
  final keep = {version, ?live?.version};
  final listing = await ssh.run("ls -1 '${ssh.dir}'");
  final stale = [
    for (final name in LineSplitter.split(listing))
      if (_ours.firstMatch(name.trim()) case final m? when !keep.contains(m[1]))
        name.trim(),
  ];
  if (stale.isNotEmpty) {
    await ssh.run(
      "cd '${ssh.dir}' && rm -f ${stale.map((n) => "'$n'").join(' ')}",
    );
    stdout.writeln('Removed ${stale.join(', ')}');
  }

  await _verify(feedUrl, version, [windows, android]);
  stdout.writeln('Published $version: $feedUrl');
}

Map<String, String> _readEnvFile() {
  final file = File('tools/publish_update.env');
  if (!file.existsSync()) return const {};
  return {
    for (final line in file.readAsLinesSync())
      if (line.contains('=') && !line.trimLeft().startsWith('#'))
        line.substring(0, line.indexOf('=')).trim(): line
            .substring(line.indexOf('=') + 1)
            .trim(),
  };
}

/// The feed on the server now, or null before the first publish.
Future<UpdateFeed?> _liveFeed(Uri feedUrl) async {
  final response = await http.get(feedUrl);
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) {
    throw _Stop('$feedUrl answered HTTP ${response.statusCode}');
  }
  try {
    return UpdateFeed.parse(
      jsonDecode(utf8.decode(response.bodyBytes)),
      feedUrl,
    );
  } on FormatException catch (e) {
    throw _Stop('the live feed is not readable ($e); fix or remove it first');
  }
}

/// The installer bundles Microsoft's VC++ runtime, as release.yml does.
Future<void> _vcRedistOnce() async {
  final file = File(_vcRedist);
  if (file.existsSync()) return;
  stdout.writeln('Downloading vc_redist.x64.exe');
  final response = await http.get(
    Uri.parse('https://aka.ms/vs/17/release/vc_redist.x64.exe'),
  );
  if (response.statusCode != 200) {
    throw _Stop('vc_redist.x64.exe download: HTTP ${response.statusCode}');
  }
  await file.writeAsBytes(response.bodyBytes);
}

/// The flutter.bat of the SDK running this (bin/cache/dart-sdk/bin/dart.exe),
/// so it works without flutter on PATH.
String _flutter() {
  final sdkBin = p.dirname(
    p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable))),
  );
  final bat = p.join(sdkBin, 'flutter.bat');
  return File(bat).existsSync() ? bat : 'flutter';
}

String _iscc() {
  final candidates = [
    if (Platform.environment['LOCALAPPDATA'] case final local?)
      p.join(local, 'Programs', 'Inno Setup 6', 'ISCC.exe'),
    r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    r'C:\Program Files\Inno Setup 6\ISCC.exe',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw _Stop('Inno Setup 6 (ISCC.exe) is not installed');
}

Future<void> _run(String exe, List<String> args) async {
  stdout.writeln('> ${p.basename(exe)} ${args.join(' ')}');
  final process = await Process.start(
    exe,
    args,
    // flutter is a .bat; ISCC's path has spaces and must not go through cmd.
    runInShell: exe.endsWith('.bat') || exe == 'flutter',
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) throw _Stop('${p.basename(exe)} exited with $code');
}

Future<void> _verify(Uri feedUrl, String version, List<_Upload> files) async {
  final response = await http.get(
    feedUrl.replace(
      queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
    ),
  );
  final feed = UpdateFeed.parse(
    jsonDecode(utf8.decode(response.bodyBytes)),
    feedUrl,
  );
  if (feed.version != version) {
    throw _Stop('$feedUrl still says ${feed.version}');
  }
  for (final file in files) {
    final url = feedUrl.resolve(file.name);
    final head = await http.head(url);
    final length = int.tryParse(head.headers['content-length'] ?? '');
    if (head.statusCode != 200 || length != file.size) {
      throw _Stop(
        '$url: HTTP ${head.statusCode}, $length bytes, not ${file.size}',
      );
    }
  }
}

class _Upload {
  _Upload(this.path, this.name, this.size, this.sha256Hex);

  final String path;
  final String name;
  final int size;
  final String sha256Hex;

  Map<String, Object> get entry => {
    'file': name,
    'size': size,
    'sha256': sha256Hex,
  };

  static Future<_Upload> of(String path, String name) async {
    final file = File(path);
    if (!file.existsSync()) throw _Stop('$path was not built');
    final digest = await sha256.bind(file.openRead()).first;
    return _Upload(path, name, await file.length(), digest.toString());
  }
}

class _Ssh {
  _Ssh(this.target, String? key, this.dir)
    : _key = key == null || key.trim().isEmpty
          ? const []
          : ['-i', _home(key.trim())];

  final String target;
  final String dir;
  final List<String> _key;

  static String _home(String path) => path.startsWith('~')
      ? p.join(
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']!,
          path.substring(path.startsWith('~/') ? 2 : 1),
        )
      : path;

  Future<void> copy(String local, String remoteName) async {
    stdout.writeln('Uploading $remoteName');
    final result = await Process.run('scp', [
      ..._key,
      '-o',
      'BatchMode=yes',
      local,
      '$target:$dir/$remoteName',
    ]);
    if (result.exitCode != 0) throw _Stop('scp $remoteName: ${result.stderr}');
  }

  Future<String> run(String command) async {
    final result = await Process.run('ssh', [
      ..._key,
      '-o',
      'BatchMode=yes',
      target,
      command,
    ]);
    if (result.exitCode != 0) throw _Stop('ssh: ${result.stderr}');
    return result.stdout as String;
  }
}

class _Stop implements Exception {
  _Stop(this.message);
  final String message;
}
