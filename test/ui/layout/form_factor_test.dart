// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Which layout a screen gets inside the phone shell. A phone on its side is
// still a phone (it gets the rail for its short height, not tablet panes).

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';

void main() {
  test('form factor by screen size', () {
    const cases = [
      (Size(360, 740), FormFactor.phone),
      (Size(412, 915), FormFactor.phone),
      (Size(915, 412), FormFactor.phone), // a phone in landscape
      (Size(800, 1280), FormFactor.tablet),
      (Size(1280, 800), FormFactor.desktop),
      (Size(1440, 900), FormFactor.desktop),
    ];
    for (final (size, expected) in cases) {
      expect(formFactorFor(size), expected, reason: '$size');
    }
  });
}
