// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Escape is the app's back key; this goes around the app's navigator.
///
/// Escape bindings nearer the focus answer first: the app's own, those of
/// drawers and dropdowns, and a menu or dialog with the focus in it. Then:
///
/// * a text box with the cursor lets go of it, so a stray Escape never
///   throws away what was being typed, even in a dialog;
/// * a menu or dialog the focus is not in closes if it can be dismissed,
///   and one that cannot stays up;
/// * a page over the main screen goes back through `maybePop`, so unsaved
///   edits are asked about as with the back button;
/// * the main screen takes one step back: the open page's own step, then
///   the page the sidebar showed before.
///
/// The steps after the text box run once nothing else took the key, so they
/// work wherever the focus is, even when it fell out of the pages after the
/// widget holding it went away.
class EscapeGoesBack extends StatefulWidget {
  const EscapeGoesBack({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<EscapeGoesBack> createState() => _EscapeGoesBackState();
}

bool _isEscape(KeyEvent event) =>
    event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape;

class _EscapeGoesBackState extends State<EscapeGoesBack> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addLateKeyEventHandler(_onUnhandledKey);
  }

  @override
  void dispose() {
    FocusManager.instance.removeLateKeyEventHandler(_onUnhandledKey);
    super.dispose();
  }

  // A text box's own dismiss only hides its copy/paste menu and swallows the
  // key either way, so this is caught on the way up; letting go of the cursor
  // hides that menu too.
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!_isEscape(event)) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    final at = focus?.context;
    if (focus == null ||
        at == null ||
        at.findAncestorStateOfType<EditableTextState>() == null) {
      return KeyEventResult.ignored;
    }
    focus.unfocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _onUnhandledKey(KeyEvent event) {
    final navigator = widget.navigatorKey.currentState;
    if (!_isEscape(event) || navigator == null || !navigator.mounted) {
      return KeyEventResult.ignored;
    }
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final shown = top;
    if (shown is PopupRoute) {
      if (shown.barrierDismissible) navigator.maybePop();
      return KeyEventResult.handled;
    }
    if (shown is! PageRoute) return KeyEventResult.ignored;
    if (navigator.canPop()) {
      navigator.maybePop();
    } else {
      _backOnMainScreen(navigator.context);
    }
    return KeyEventResult.handled;
  }

  Future<void> _backOnMainScreen(BuildContext at) async {
    final app = Provider.of<AppState>(at, listen: false);
    if (app.backWithinPage() || !app.canGoBack) return;
    // Leaving a sidebar page throws it away, so unsaved edits are asked
    // about first, as a sidebar tap does.
    if (!await UnsavedChanges.instance.confirmLeave(at)) return;
    app.goBack();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: widget.child,
  );
}
