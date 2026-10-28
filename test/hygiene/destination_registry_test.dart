// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Every desktop sidebar destination has exactly one decision about where it
// lives on a phone (lib/ui/layout/app_destinations.dart), and every place the
// phone offers actually opens something. A new sidebar entry fails here until
// someone decides its phone placement.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/mobile/mobile.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

void main() {
  test('each sidebar label has exactly one destination row', () {
    for (final label in Sidebar.labels) {
      final rows = appDestinations.where((d) => d.desktopLabel == label);
      expect(rows, hasLength(1), reason: '"$label" needs one registry row');
    }
    final unknown = appDestinations
        .map((d) => d.desktopLabel)
        .whereType<String>()
        .where((l) => !Sidebar.labels.contains(l));
    expect(unknown, isEmpty, reason: 'rows name sidebar labels that are gone');
  });

  test('a hidden destination says why; others do not pretend to be', () {
    for (final d in appDestinations) {
      if (d.phone == PhonePlacement.hidden) {
        expect(d.hiddenBecause, isNotEmpty, reason: '${d.id} hides silently');
      } else {
        expect(d.hiddenBecause, isNull, reason: '${d.id} is not hidden');
      }
    }
  });

  test('every tab has a first screen and every other row opens something', () {
    final ids = appDestinations.map((d) => d.id).toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'ids must be unique');
    for (final d in destinationsPlaced(PhonePlacement.tab)) {
      expect(phoneTabRoots, contains(d.id), reason: 'tab ${d.id}');
    }
    for (final placement in [
      PhonePlacement.createSheet,
      PhonePlacement.more,
      PhonePlacement.community,
    ]) {
      for (final d in destinationsPlaced(placement)) {
        expect(phoneDestinationActions, contains(d.id), reason: d.id);
      }
    }
    expect(destinationsPlaced(PhonePlacement.tab), hasLength(5));
  });
}
