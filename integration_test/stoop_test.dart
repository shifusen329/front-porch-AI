// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: The Stoop against a fake backporch server (BackporchApi's
// overrideBaseUrl seam — the desktop UI constructs bare BackporchApi()
// everywhere, so without the seam this journey would hit the LIVE hub).
// The whole gated path is driven through the real UI:
//   sign-in form → the 18+ Acceptable Use Policy gate (checkbox + Agree) →
//   browse grid renders the fake's card → detail panel → Download to
//   library actually imports the V2 card into CharacterRepository →
//   the @you tab's Share wizard (pick → details → standards ack → submit)
//   posts the upload and reports "Submitted for review."
//
// Run it with:
//   flutter test integration_test/stoop_test.dart -d macos
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart' show RepositoryPage;
import 'package:front_porch_ai/ui/pages/repository/repository_auth_view.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_pick_step.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';
import 'support/fake_stoop.dart';

const _kReplyPieces = ['The fake backend replies ', 'about the stoop.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign-in, the AUP gate, browse, download-to-library, and the '
      'share wizard against a fake backporch server — sandboxed', (
    tester,
  ) async {
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail(
        'Something is listening on 127.0.0.1:5001 (a real KoboldCpp?). '
        'Close it before running the E2E suite.',
      );
    } on SocketException {
      // Nothing there — safe to proceed.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_stoop_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    final stoop = await FakeStoopServer.start();
    BackporchApi.overrideBaseUrl = stoop.baseUrl;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    // ── Boot ────────────────────────────────────────────────────────────
    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.blur();
    } catch (e) {
      debugPrint('[e2e] window_manager placement skipped: $e');
    }
    await tester.pump(const Duration(seconds: 2));

    final ctx = tester.element(find.byType(MainLayout));
    final repo = Provider.of<CharacterRepository>(ctx, listen: false);
    final d = ChatDriver(
      tester,
      Provider.of<ChatService>(ctx, listen: false),
      backend,
    );

    // ── Open The Stoop ──────────────────────────────────────────────────
    // The desktop sidebar has no Stoop button; a phone opens this page from
    // Characters → New, by pushing it as here.
    Navigator.of(
      ctx,
    ).push(MaterialPageRoute<void>(builder: (_) => const RepositoryPage()));
    await pumpUntilFound(
      tester,
      find.text('Pull up a chair — sign in to browse and share.'),
    );
    // Every tap below is delivery-confirmed: this page is panels and dialogs
    // inside scrollables, where a plain tap lands on a barrier or a stale
    // position and fails SILENTLY (round 3 died four minutes later at the
    // download snackbar, with a hit-test warning as the only clue).

    // ── Sign in through the REAL form ───────────────────────────────────
    // The labels are standalone Texts above bare TextFields (the lorebook
    // dialog lesson) — address the fields positionally inside the view:
    // sign-in mode renders exactly Email then Password.
    final authFields = find.descendant(
      of: find.byType(RepositoryAuthView),
      matching: find.byType(TextField),
    );
    await pumpUntilFound(
      tester,
      authFields,
      timeout: const Duration(seconds: 45),
    );
    await tester.enterText(authFields.at(0), 'porch@example.com');
    await tester.enterText(authFields.at(1), 'porchporch');
    await tester.pump(const Duration(milliseconds: 200));

    // ── The 18+ AUP gate: checkbox required, Agree routes the accept ────
    await d.tapUntil(
      [find.widgetWithText(StoopAmberButton, 'Sign in')],
      find.text('Welcome to The Stoop'),
      timeout: const Duration(seconds: 60),
    );
    // Agree stays DISABLED until the box is ticked, so the two taps are ONE
    // retry unit — and the confirmation is the server actually recording the
    // acceptance, not either tap landing.
    await d.tapUntilTrue(
      [
        find.textContaining('I am 18 or older'),
        find.widgetWithText(StoopAmberButton, 'Agree & continue'),
      ],
      () => stoop.policyAccepted,
      () => 'the accept-policy POST to reach the fake server',
    );

    // ── Browse renders the fake's card ──────────────────────────────────
    await pumpUntilFound(
      tester,
      find.text('Misty'),
      timeout: const Duration(seconds: 45),
    );
    expect(stoop.browseRequests, greaterThanOrEqualTo(1));

    // ── Detail panel → Download to library → real import ────────────────
    await d.tapUntil([find.text('Misty')], find.text('Download to library'));
    expect(stoop.detailRequests, greaterThanOrEqualTo(1));
    // The download button sits low in a right-side panel — the exact tap
    // that missed in round 3, costing a four-minute silent wait.
    await d.tapUntil(
      [find.text('Download to library')],
      find.text('“Misty” added to your library.'),
      timeout: const Duration(seconds: 60),
    );
    expect(stoop.downloadRequests, 1);
    await pumpUntilTrue(
      tester,
      () => repo.characters.any((c) => c.name == 'Misty'),
      describe: () =>
          'the downloaded card to land in the repository '
          '(have: ${repo.characters.map((c) => c.name).toList()})',
    );

    // Close the detail panel so later taps aren't over its barrier.
    //
    // BOTH button labels, or this confirmation is true for the wrong reason
    // (Windows 3/5 flake, run 31865341572). The panel's download button reads
    // 'Download to library' at rest and 'Adding…' while _downloading — and
    // _downloading is only cleared in _download's `finally`, AFTER the
    // "added to your library" snackbar the previous step waits on. So on a
    // machine where that setState has not been pumped yet, checking the
    // rest-label alone reports "already closed" while the panel is still
    // fully open: tapUntilTrue's loop is `attempt < 8 && !done()`, so it
    // never taps close at all, and the @PorchFriend tap below then lands on
    // the dialog's modal barrier and is swallowed eight times over. The
    // suite died two minutes later at the share button — a symptom three
    // steps from the cause. The button renders exactly one of these two
    // strings whenever the panel is up, so "neither present" is the honest
    // test for "the panel is gone". Both are mirrored from
    // stoop_card_detail_page.dart's download button — rename one there and
    // this predicate silently goes back to lying, so change both together.
    await d.tapUntilTrue(
      [find.byIcon(Icons.close)],
      () =>
          find.text('Download to library').evaluate().isEmpty &&
          find.text('Adding…').evaluate().isEmpty,
      () => 'the detail panel to close',
    );

    // ── Share wizard: pick → details → standards ack → submit ───────────
    await d.tapUntil([
      find.text('@PorchFriend'),
    ], find.widgetWithText(StoopAmberButton, 'Share to The Stoop'));
    // Step 0 — pick the just-downloaded Misty (scoped to the pick step:
    // the browse grid beneath this route also renders a 'Misty' text).
    final pickMisty = find.descendant(
      of: find.byType(StoopPickStep),
      matching: find.text('Misty'),
    );
    await d.tapUntil(
      [find.widgetWithText(StoopAmberButton, 'Share to The Stoop')],
      pickMisty,
      timeout: const Duration(seconds: 60),
    );
    // Step 1 — selecting the card only ENABLES Next; the pick and the
    // advance are one retry unit.
    await d.tapUntil([
      pickMisty,
      find.widgetWithText(StoopAmberButton, 'Next'),
    ], find.text('Display name on The Stoop'));
    // The wizard is ONE Scaffold wrapping a 250ms AnimatedSwitcher, so the
    // outgoing step stays mounted while the incoming one fades in — and
    // tapUntil returns the instant its target text appears, which is the START
    // of that window. StoopPickStep owns a search TextField, so during those
    // 250ms `find.byType(TextField)` under the Scaffold yields five fields,
    // not four, and every index is off by one: the display name went into the
    // pick step's search box and the summary into the name box. _summary
    // stayed empty, Next stayed disabled, and the NEXT step's wait timed out
    // two minutes later pointing at the standards text — nowhere near the
    // actual mistake. Whether the poll landed inside the window was pure
    // timing, which is why this passed on Linux and Windows and failed on
    // macOS.
    //
    // Waiting for the outgoing step to leave removes the race; addressing the
    // fields by their hint text removes the index arithmetic that made the
    // race harmful. Either alone would fix it; together the step cannot come
    // back in a different shape and quietly type into the wrong box again.
    // The wizard is ONE Scaffold wrapping a 250ms AnimatedSwitcher, so the
    // outgoing step stays mounted while the incoming one fades in — and
    // tapUntil returns the instant its target text appears, which is the START
    // of that window. StoopPickStep owns a search TextField, so the field set
    // under that Scaffold is 5 widgets mid-transition and 4 once it settles
    // (measured, both values observed on the same machine). Addressing fields
    // by index across that boundary is a coin flip: step 1's Next is gated on
    // `_name` AND `_summary` both being non-empty, so landing one index off
    // leaves _summary blank, Next disabled, and the failure surfaces two
    // minutes later at the NEXT step's wait for the standards text — nowhere
    // near the actual mistake.
    //
    // This is hardening, NOT the macOS fix — an earlier version of this
    // comment claimed it was, and that was wrong. The macOS failure had a
    // different cause entirely (see the scroll below), proven by reproducing
    // it here. This block stays because index arithmetic across a live
    // animation is fragile on its own merits, and the assertion below turns a
    // future recurrence into an immediate, accurate failure.
    //
    // Waiting for the outgoing step to leave removes the race; addressing the
    // fields by their hint text removes the index arithmetic that made the
    // race harmful.
    await d.waitFor(
      () => find.byType(StoopPickStep).evaluate().isEmpty,
      () => 'the pick step to finish animating out of the wizard',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Name shown on The Stoop'),
      'Misty of the Porch',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'A one-line hook shown on the card'),
      'A gentle porch spirit, shared by the E2E suite.',
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Fail HERE, on the real cause, if either box was missed again. Without
    // this the only symptom is a two-minute timeout pointing at the standards
    // text on the following step, which is what made the macOS failure so
    // slow to read.
    final nextButton = tester.widget<StoopAmberButton>(
      find.widgetWithText(StoopAmberButton, 'Next'),
    );
    expect(
      nextButton.onPressed,
      isNotNull,
      reason:
          'Next is still disabled, so the name/summary boxes did not both '
          'receive text — check the wizard field hints before blaming the '
          'standards step below.',
    );
    // Step 2 — name+summary are filled, so Next alone advances. Confirm on
    // the step's own ValueKey, NOT on anything inside it: the key is on the
    // ListView itself and therefore exists the moment the step is built,
    // whatever is or is not scrolled into view.
    await d.tapUntil([
      find.widgetWithText(StoopAmberButton, 'Next'),
    ], find.byKey(const ValueKey('content')));

    // THIS is what turned macOS red, and it is a class of bug, not a one-off.
    //
    // _contentStep() is a ListView, and the standards row sits well down it,
    // behind a conditional completeness banner that renders only for some
    // cards. A ListView builds only what is visible (plus cache extent), so
    // when the usable window is shorter than the content, that row is NEVER
    // IN THE WIDGET TREE and find.text legitimately returns zero — the step
    // is open and correct, the test just cannot see the row. The suite asks
    // for 1200x800, but a runner is free to give less, and macOS evidently
    // does. Reproduced exactly on Linux by asking for 1200x480: same message,
    // same line, every run.
    //
    // scrollUntilVisible is the fix rather than a longer timeout, because
    // waiting cannot build a widget that is off-screen. This is the same trap
    // climate_editor_test hit; if a third suite hits it, the scroll belongs in
    // ChatDriver rather than copied a third time.
    final standardsRow = find.text(
      'This card meets the Stoop content standards',
    );
    await tester.scrollUntilVisible(
      standardsRow,
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('content')),
        matching: find.byType(Scrollable),
      ),
    );
    // Step 3 — the standards acknowledgement gates Next, so again one unit.
    await d.tapUntil([
      standardsRow,
      find.widgetWithText(StoopAmberButton, 'Next'),
    ], find.widgetWithText(StoopAmberButton, 'Submit for review'));
    // Submit → the fake accepts the multipart POST.
    await d.tapUntilTrue(
      [find.widgetWithText(StoopAmberButton, 'Submit for review')],
      () => stoop.uploadRequests >= 1,
      () => 'the multipart upload to reach the fake server',
      timeout: const Duration(seconds: 60),
    );
    await d.waitForWidget(find.text('Submitted for review.'));
    expect(stoop.uploadRequests, 1);

    expect(stoop.unexpectedPaths, isEmpty);
    expect(
      stoop.handlerErrors,
      isEmpty,
      reason: 'a crashed fake handler answers nothing and reads as a timeout',
    );
    expect(backend.unexpectedPaths, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await backend.close();
    await stoop.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }
  });
}
