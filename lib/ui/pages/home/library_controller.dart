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

import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/pages/home/library_selection.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// What the character library is showing: the search, the folder it stands
/// in, the sort, the grid size, the picks, and each card's last activity.
/// A shell draws it; the view choices persist through [UiSettings].
class LibraryController extends ChangeNotifier {
  LibraryController(this._prefs) {
    _readViewPrefs();
    _selection.addListener(notifyListeners);
  }

  final UiSettings _prefs;
  bool _disposed = false;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  /// Null is the top level.
  String? _activeFolderId;
  String? get activeFolderId => _activeFolderId;

  // The top level and folders remember separate search scopes (#346): they
  // offer different choices, and the top level defaults to Everywhere.
  SearchScope _topSearchScope = SearchScope.allCharacters;
  SearchScope _folderSearchScope = SearchScope.currentFolder;
  SearchScope get searchScope =>
      _activeFolderId == null ? _topSearchScope : _folderSearchScope;

  String _sortMode = 'name'; // 'name', 'recent', 'importDate', 'messages'
  String get sortMode => _sortMode;

  double _gridScale = 300.0;
  double get gridScale => _gridScale;

  /// Multi-select / Organize into folders: mode, picks, Shift anchor, drag.
  final LibrarySelection _selection = LibrarySelection();
  LibrarySelection get selection => _selection;

  final Map<String, DateTime> _lastActivity = {};
  final Map<String, int> _messageCounts = {};
  Map<String, DateTime> get lastActivity => UnmodifiableMapView(_lastActivity);
  Map<String, int> get messageCounts => UnmodifiableMapView(_messageCounts);

  void _readViewPrefs() {
    final scopes = SearchScope.values.asNameMap();
    _sortMode = _prefs.sortMode;
    _gridScale = _prefs.gridScale;
    _topSearchScope =
        scopes[_prefs.topSearchScope] ?? SearchScope.allCharacters;
    _folderSearchScope =
        scopes[_prefs.folderSearchScope] ?? SearchScope.currentFolder;
  }

  /// Settings load after the first frame; call once they have.
  void reloadViewPrefs() {
    _readViewPrefs();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Stand in [folderId] (null: the top level).
  void openFolder(String? folderId) {
    _activeFolderId = folderId;
    notifyListeners();
  }

  /// Up one level. Subfolder cards only render inside their parent, so the
  /// parent chain IS the navigation history — no stack needed (and the
  /// breadcrumb trail can jump to any ancestor directly).
  void goUp(Iterable<CharacterFolder> folders) {
    final current = folders.where((f) => f.id == _activeFolderId).firstOrNull;
    openFolder(current?.parentId);
  }

  /// If the user is standing inside the folder being deleted, step back out
  /// to its parent (top level when the folder was top-level).
  void leaveDeletedFolder(CharacterFolder folder) {
    if (_activeFolderId != folder.id) return;
    openFolder(folder.parentId);
  }

  void setSortMode(String mode) {
    _sortMode = mode;
    notifyListeners();
    _prefs.setSortMode(mode);
  }

  /// Remembered per level, like the sort: the top level offers Everywhere
  /// and Top level only, a folder its three choices.
  void setSearchScope(SearchScope scope) {
    if (_activeFolderId == null) {
      _topSearchScope = scope;
      _prefs.setTopSearchScope(scope.name);
    } else {
      _folderSearchScope = scope;
      _prefs.setFolderSearchScope(scope.name);
    }
    notifyListeners();
  }

  /// While the slider moves; [commitGridScale] saves where it stops.
  void previewGridScale(double scale) {
    _gridScale = scale;
    notifyListeners();
  }

  void commitGridScale(double scale) => _prefs.setGridScale(scale);

  /// Re-reads each card's last chat and message count for the badges and
  /// the 'recent' / 'messages' sorts.
  Future<void> refreshActivity(CharacterRepository repo) async {
    try {
      final db = await AppDatabase.instance();
      final activity = await loadHomeLibraryActivity(db, repo);
      if (_disposed) return;
      _lastActivity
        ..clear()
        ..addAll(activity.lastActivity);
      _messageCounts
        ..clear()
        ..addAll(activity.messageCounts);
    } catch (e) {
      debugPrint('Error refreshing activity cache: $e');
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _selection
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
