// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The update feed (`latest.json`) that tools/publish_update.dart writes next
// to the files it uploads:
//
//   {"version": "1.0.1", "notes": "markdown",
//    "windows": {"file": "Front_Porch_AI_Setup_1.0.1.exe",
//                "size": 123, "sha256": "…"},
//    "android": {"file": "Front_Porch_AI_1.0.1.apk", "size": 456,
//                "sha256": "…", "versionCode": 1000100}}
//
// Plain Dart (no Flutter) so the publish tool parses and compares versions
// with the same code the app does.

import 'dart:io' show Platform;
import 'dart:math' show min;

/// One platform's download in the feed.
class UpdateFile {
  const UpdateFile({
    required this.url,
    required this.size,
    required this.sha256,
  });

  final Uri url;

  /// Bytes, checked against what arrives.
  final int size;

  /// Lowercase hex, checked against what arrives.
  final String sha256;

  /// The file's own name; its extension picks the install path.
  String get name => url.pathSegments.last;
}

class UpdateFeed {
  const UpdateFeed({
    required this.version,
    required this.notes,
    required this.files,
  });

  final String version;
  final String notes;

  /// Keyed by [platformKey] values.
  final Map<String, UpdateFile> files;

  static const platforms = ['windows', 'android', 'linux', 'macos'];

  /// This build's key in the feed.
  static String get platformKey => Platform.isAndroid
      ? 'android'
      : Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : 'windows';

  UpdateFile? get forThisPlatform => files[platformKey];

  /// [base] is the feed's own URL; a relative `file` resolves against it.
  /// Throws [FormatException] for anything that is not a whole feed, so a
  /// garbled reply is a failed check rather than "nothing newer".
  static UpdateFeed parse(Object? json, Uri base) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('the update feed is not a JSON object');
    }
    final version = json['version'];
    if (version is! String || version.trim().isEmpty) {
      throw const FormatException('the update feed has no version');
    }
    final notes = json['notes'];
    final files = <String, UpdateFile>{};
    for (final key in platforms) {
      final entry = json[key];
      if (entry == null) continue;
      final file = entry is Map<String, dynamic> ? entry['file'] : null;
      final size = entry is Map<String, dynamic> ? entry['size'] : null;
      final hash = entry is Map<String, dynamic> ? entry['sha256'] : null;
      if (file is! String ||
          file.isEmpty ||
          size is! int ||
          size <= 0 ||
          hash is! String ||
          !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
        throw FormatException('the update feed\'s $key entry is incomplete');
      }
      final url = base.resolve(file);
      // The name becomes the downloaded file's name, so a decoded `/`, `\`
      // or `..` must not climb out of the download folder.
      final name = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(name)) {
        throw FormatException('the update feed\'s $key file name is not plain');
      }
      files[key] = UpdateFile(url: url, size: size, sha256: hash.toLowerCase());
    }
    return UpdateFeed(
      version: normalizeVersion(version.trim()),
      notes: notes is String ? notes : '',
      files: files,
    );
  }
}

/// Strips a leading v/V and the "nightly-" wrapper Rawhide tags carry, so
/// "nightly-rawhide.20250519.abc" matches the baked "rawhide.20250519.abc".
String normalizeVersion(String v) {
  v = v.toLowerCase().replaceFirst(RegExp(r'^v'), '');
  if (v.startsWith('nightly-')) v = v.substring(8);
  return v;
}

/// True when [remote] is newer than [local] ("0.9.8-beta6" > "0.9.8-beta5",
/// "1.0.10" > "1.0.9", a stable release > its betas, later Rawhide days).
bool isNewerVersion(String remote, String local) {
  final rClean = normalizeVersion(remote);
  final lClean = normalizeVersion(local);

  if (rClean == lClean) return false;

  // Rawhide is "rawhide.YYYYMMDD.SHA": the date orders days, and any other
  // build on the same day is offered (the SHA has no order).
  if (rClean.startsWith('rawhide.') && lClean.startsWith('rawhide.')) {
    final rParts = rClean.split('.');
    final lParts = lClean.split('.');
    if (rParts.length >= 2 && lParts.length >= 2) {
      final rDate = int.tryParse(rParts[1]) ?? 0;
      final lDate = int.tryParse(lParts[1]) ?? 0;
      if (rDate != lDate) return rDate > lDate;
      return true;
    }
  }

  // Split at the first hyphen: "0.9.8-beta6" -> ["0.9.8", "beta6"].
  final rSplit = rClean.split('-');
  final lSplit = lClean.split('-');
  final rBase = rSplit[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final lBase = lSplit[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();
  while (rBase.length < lBase.length) {
    rBase.add(0);
  }
  while (lBase.length < rBase.length) {
    lBase.add(0);
  }
  for (int i = 0; i < rBase.length; i++) {
    if (rBase[i] != lBase[i]) return rBase[i] > lBase[i];
  }

  final rSuffix = rSplit.length > 1 ? rSplit[1] : '';
  final lSuffix = lSplit.length > 1 ? lSplit[1] : '';
  if (rSuffix.isEmpty && lSuffix.isNotEmpty) return true; // stable > beta
  if (rSuffix.isNotEmpty && lSuffix.isEmpty) return false;
  return _compareAlphanumeric(rSuffix, lSuffix) > 0;
}

/// Natural order, so "beta10" > "beta9".
int _compareAlphanumeric(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final aMatches = re.allMatches(a).toList();
  final bMatches = re.allMatches(b).toList();
  for (int i = 0; i < min(aMatches.length, bMatches.length); i++) {
    final aVal = aMatches[i].group(0)!;
    final bVal = bMatches[i].group(0)!;
    final aNum = int.tryParse(aVal);
    final bNum = int.tryParse(bVal);
    if (aNum != null && bNum != null) {
      if (aNum != bNum) return aNum.compareTo(bNum);
    } else if (aVal != bVal) {
      return aVal.compareTo(bVal);
    }
  }
  return aMatches.length.compareTo(bMatches.length);
}
