// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Escape is the app's back key: what is open on top closes first, a text
// box lets go of the cursor, a page goes back (asking about unsaved edits),
// and the main screen steps back through Home and the sidebar's pages.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/pages/home_page.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../pages/home/home_page_harness.dart';

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

/// The app's Escape over [home], which can open [page].
Future<AppState> _pump(
  WidgetTester tester, {
  Widget? page,
  Widget? home,
}) async {
  final state = AppState();
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) =>
            EscapeGoesBack(navigatorKey: navigator, child: child!),
        home:
            home ??
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => page!)),
                  child: const Text('open'),
                ),
              ),
            ),
      ),
    ),
  );
  if (page != null) {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
  return state;
}

/// Up scope by scope to the app's root, where nothing in the pages has it.
Future<void> _focusOutOfThePages(WidgetTester tester) async {
  final root = FocusManager.instance.rootScope;
  for (var i = 0; i < 10 && FocusManager.instance.primaryFocus != root; i++) {
    FocusManager.instance.primaryFocus!.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    await tester.pump();
  }
  expect(FocusManager.instance.primaryFocus, root);
}

bool _typing() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>() !=
    null;

/// Shows the selected sidebar page's number.
Widget _sidebarPages({bool dirty = false}) => UnsavedChangesGuard(
  isDirty: () => dirty,
  child: Consumer<AppState>(
    builder: (_, s, _) => Scaffold(body: Text('page ${s.selectedIndex}')),
  ),
);

void main() {
  testWidgets('a page over the main screen goes back', (tester) async {
    await _pump(tester, page: const Scaffold(body: Text('editor')));
    expect(find.text('editor'), findsOneWidget);

    await _escape(tester);
    expect(find.text('editor'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a page with unsaved edits asks before going back', (
    tester,
  ) async {
    await _pump(
      tester,
      page: UnsavedChangesGuard(
        isDirty: () => true,
        child: const Scaffold(body: Text('editor')),
      ),
    );

    await _escape(tester);
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);
  });

  testWidgets('a text box lets go of the cursor before the page goes back', (
    tester,
  ) async {
    await _pump(
      tester,
      page: Scaffold(
        body: TextField(
          autofocus: true,
          controller: TextEditingController(text: 'half a line'),
        ),
      ),
    );
    expect(_typing(), isTrue);

    await _escape(tester);
    expect(find.text('half a line'), findsOneWidget);
    expect(_typing(), isFalse);

    await _escape(tester);
    expect(find.text('half a line'), findsNothing);
  });

  testWidgets('a text box in a dialog lets go before the dialog closes', (
    tester,
  ) async {
    await _pump(
      tester,
      page: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showWarmDialog<void>(
              context,
              title: 'Rename',
              content: const TextField(autofocus: true),
            ),
            child: const Text('rename'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('rename'));
    await tester.pumpAndSettle();
    expect(_typing(), isTrue);

    await _escape(tester);
    expect(find.text('Rename'), findsOneWidget);
    expect(_typing(), isFalse);

    await _escape(tester);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('rename'), findsOneWidget);
  });

  testWidgets('a menu closes before the page does', (tester) async {
    await _pump(
      tester,
      page: Scaffold(
        body: PopupMenuButton<int>(
          itemBuilder: (_) => const [
            PopupMenuItem(value: 1, child: Text('Rename')),
          ],
          child: const Text('menu'),
        ),
      ),
    );
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);

    await _escape(tester);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('menu'), findsOneWidget);

    await _escape(tester);
    expect(find.text('menu'), findsNothing);
  });

  // The Narration panel's "Starting at" picker is this kind of menu.
  testWidgets('a dropdown menu closes before the page does', (tester) async {
    await _pump(
      tester,
      page: const Scaffold(
        body: Column(
          children: [
            Text('narration'),
            DropdownMenu<int>(
              key: Key('from'),
              enableFilter: true,
              requestFocusOnTap: true,
              dropdownMenuEntries: [
                DropdownMenuEntry(value: 12, label: 'Message 12'),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('from')));
    await tester.pumpAndSettle();
    expect(find.text('Message 12'), findsWidgets);

    await _escape(tester);
    expect(find.text('Message 12').hitTestable(), findsNothing);
    expect(find.text('narration'), findsOneWidget);
  });

  testWidgets('a drawer closes before the page does', (tester) async {
    final scaffold = GlobalKey<ScaffoldState>();
    await _pump(
      tester,
      page: Scaffold(
        key: scaffold,
        endDrawer: const Drawer(child: Text('contents')),
        body: const Text('reader'),
      ),
    );
    scaffold.currentState!.openEndDrawer();
    await tester.pumpAndSettle();
    expect(find.text('contents'), findsOneWidget);

    await _escape(tester);
    expect(find.text('contents'), findsNothing);
    expect(find.text('reader'), findsOneWidget);
  });

  testWidgets('a dialog that cannot be dismissed stays up', (tester) async {
    await _pump(
      tester,
      page: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showWarmDialog<void>(
              context,
              title: 'Saving',
              barrierDismissible: false,
              content: const WarmDialogText('Hold on.'),
            ),
            child: const Text('save'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    await _escape(tester);
    expect(find.text('Hold on.'), findsOneWidget);
    expect(find.text('save'), findsOneWidget);
  });

  testWidgets('the main screen goes back through the sidebar pages', (
    tester,
  ) async {
    final state = await _pump(tester, home: _sidebarPages());
    state
      ..setIndex(3)
      ..setIndex(2);
    await tester.pump();

    await _escape(tester);
    expect(find.text('page 3'), findsOneWidget);
    await _escape(tester);
    expect(find.text('page 0'), findsOneWidget);
    await _escape(tester);
    expect(find.text('page 0'), findsOneWidget);
  });

  // Where Flutter leaves the focus when nothing in the pages holds it.
  testWidgets('back works with the focus out of the pages', (tester) async {
    final state = await _pump(tester, home: _sidebarPages());
    state.setIndex(3);
    await tester.pump();
    await _focusOutOfThePages(tester);

    await _escape(tester);
    expect(find.text('page 0'), findsOneWidget);
  });

  testWidgets('a dialog the focus is not in still closes', (tester) async {
    await _pump(
      tester,
      page: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showWarmDialog<void>(
              context,
              title: 'Saved',
              content: const WarmDialogText('All set.'),
            ),
            child: const Text('save'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    await _focusOutOfThePages(tester);

    await _escape(tester);
    expect(find.text('All set.'), findsNothing);
    expect(find.text('save'), findsOneWidget);
  });

  testWidgets('the open page takes its own step before the sidebar', (
    tester,
  ) async {
    final state = await _pump(tester, home: _sidebarPages());
    state.setIndex(3);
    var steps = 1;
    state.pageBack = () => steps-- > 0;
    await tester.pump();

    await _escape(tester);
    expect(find.text('page 3'), findsOneWidget);
    await _escape(tester);
    expect(find.text('page 0'), findsOneWidget);
  });

  testWidgets('leaving a sidebar page with unsaved edits asks first', (
    tester,
  ) async {
    final state = await _pump(tester, home: _sidebarPages(dirty: true));
    state.setIndex(3);
    await tester.pump();

    await _escape(tester);
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('page 3'), findsOneWidget);

    await _escape(tester);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('page 0'), findsOneWidget);
  });

  testWidgets('Home goes up out of a folder, then has nowhere to go', (
    tester,
  ) async {
    final rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    await tester.runAsync(() => rig.folders.createFolder('Porch'));
    await rig.pump(tester);
    await tester.tap(find.text('Porch').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ada'), findsNothing);

    final app = Provider.of<AppState>(
      tester.element(find.byType(HomePage)),
      listen: false,
    );
    expect(app.backWithinPage(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ada'), findsWidgets);
    expect(app.backWithinPage(), isFalse);
  });
}
