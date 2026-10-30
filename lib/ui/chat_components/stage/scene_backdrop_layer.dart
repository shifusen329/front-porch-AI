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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The scene picture behind the chat, over the chat's normal background.
/// A new place cross-fades in once its picture is decoded (so a fade never
/// starts from a blank frame), and fading out to nothing shows the normal
/// background again. With the system's reduce-motion on it swaps at once.
class SceneBackdropLayer extends StatefulWidget {
  const SceneBackdropLayer({super.key, required this.backdrop});

  final SceneBackdrop backdrop;

  static const fade = Duration(milliseconds: 600);

  @override
  State<SceneBackdropLayer> createState() => _SceneBackdropLayerState();
}

class _SceneBackdropLayerState extends State<SceneBackdropLayer> {
  /// The picture on screen, and the shot it shows.
  ImageProvider? _image;
  String? _key;

  @override
  void initState() {
    super.initState();
    widget.backdrop.addListener(_follow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  @override
  void didUpdateWidget(SceneBackdropLayer old) {
    super.didUpdateWidget(old);
    if (old.backdrop != widget.backdrop) {
      old.backdrop.removeListener(_follow);
      widget.backdrop.addListener(_follow);
      _follow();
    }
  }

  @override
  void dispose() {
    widget.backdrop.removeListener(_follow);
    super.dispose();
  }

  Future<void> _follow() async {
    final shot = widget.backdrop.current;
    if (!mounted || shot?.key == _key) return;
    if (shot == null) {
      setState(() {
        _image = null;
        _key = null;
      });
      return;
    }
    // Decoded at the window's width: a phone never holds a 4K picture.
    final media = MediaQuery.of(context);
    final width = (media.size.width * media.devicePixelRatio).round();
    final image = ResizeImage.resizeIfNeeded(
      width > 0 ? width : null,
      null,
      FileImage(shot.scene.file),
    );
    // A picture that won't decode still swaps in; the Image shows nothing.
    await precacheImage(
      image,
      context,
      onError: (e, _) =>
          debugPrint('[SceneBackdrop] ${shot.key} did not decode: $e'),
    );
    // A newer shot may have arrived while this one decoded.
    if (!mounted || widget.backdrop.current?.key != shot.key) return;
    setState(() {
      _image = image;
      _key = shot.key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final image = _image;
    return IgnorePointer(
      child: AnimatedSwitcher(
        // A picture keeps the fade it was shown with; turning reduce motion
        // on starts over without one.
        key: ValueKey(still),
        duration: still ? Duration.zero : SceneBackdropLayer.fade,
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: image == null
            ? const SizedBox.shrink(key: ValueKey('scene-none'))
            : Stack(
                key: ValueKey('scene:$_key'),
                fit: StackFit.expand,
                children: [
                  Image(
                    image: image,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  ColoredBox(color: InkColors.dim(0.45)),
                ],
              ),
      ),
    );
  }
}
