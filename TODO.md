# TODO — ordered by value for the effort

**Released:** 1.1.5 on 2026-11-01: The Stoop button gone from the desktop sidebar, and CLAUDE.md's fork rules and dev server notes. Earlier that day, 1.1.4: the model names the place for scene backgrounds. On 2026-10-31, 1.1.3: the image generator's reasons and the reForge reload fix, Esc closes the Image Studio, About links open this fork, no Discord or Buy Me a Coffee in the sidebar; 1.1.2: the debug log, Expression Images → Display → None, Esc goes back, markdown formatting, and Install reopens the app on Windows. All on `dev`, pushed to `origin/dev` on 2026-11-01.

**Before that:** 1.1.1 on 2026-10-30, published through the updater: embeddings in the Image Studio, Prompt format on the phone web app, and the scene painting setup path fixed. Earlier that day, 1.1.0: missing scene places painted with the image generator; 1.0.4: chat backgrounds that follow the scene (each character's Scenes), and 1.0.3: library sync between devices (Settings → Sync), and Select, Clear, Replace and Undo in the Avatar Gallery. Before that, 1.0.2 on 2026-10-29: import from any file app on Android, 40 expressions with alternates, the new Android icon. All on `dev`, pushed to `origin/dev`.

**Next:** move builds and test runs to a dev server (see "Dev server" below), so they stop interrupting the desktop.

| # | Item | Value | Effort | Why this position |
|---|------|-------|--------|-------------------|
| 1 | ~~Clear and bulk-delete in the Avatar Gallery~~ | Medium | Small | **Released in 1.0.3.** Select, Clear, Replace on ZIP import and Undo, on desktop, Android and the phone web app. |
| 2 | Automatic updates | Medium | Small | The updater shipped in 1.0.1 and has published up to 1.1.5; Install now reopens the app on Windows since 1.1.2 (`3d57684c`). What's left is a few settings and one Android API. |
| 3 | Your own voice from a clip | Medium | Small–medium | Recording, Whisper and voice lists already exist. It needs one upload endpoint on OmniVoice. |
| 4 | Backgrounds that follow the scene | High | Medium–large | **Phase 1 released in 1.0.4** (character Scenes, matching by words, crossfade, phone web app). **Phase 2a released in 1.1.0:** missing places painted with the image generator (tags from the side lane, a day and a night picture per place). **Phase 2c released in 1.1.4:** the model names the place from each reply, so any place the story reaches is painted and switched to. Phase 2b: worlds, exports. |
| 5 | Library sync across devices | High | Large | **Phase 1 released in 1.0.3** (whole-library Send / Get, Undo). Phase 2 (merging chats) needs its own schema plan. |

---

## 1. [x] Clear and bulk-delete in the Avatar Gallery — released in 1.0.3 (`01b33ea5`)

**Done:** the plan below, with two changes. The new routes live in `character_sprite_pack_routes.dart` without renaming it (an existing test constructs its class by name), and the Undo banner sits inside the gallery (a snackbar from the dialog lands under its barrier). The browser suite (160 tests, the Clear-and-Undo journey included) and the layout sweep passed on Windows. Still to do: a look on the emulator at phone width. The double-tap guards on Delete can't be proven red in the widget test (the framework already swallows the second tap during the dialog's route change); they stay as cheap insurance.

**Today:** each image has its own ✕ and its own confirm, so clearing a character's expressions, or swapping one sprite pack for another, means removing every image one at a time. Desktop, Android (the same gallery code) and the phone web app all work this way.

**What one delete already does** (`AvatarGalleryController.remove`): removes the row and the file; points the ★ default back at the portrait if it was this image; clears this chat's face if it was showing it; moves the default expression (prime) to the first one left. The phone web app's facade (`CharacterAuthoringFacade.removeAvatar`) repeats the same steps in its own code.

**Plan**
1. **One removal for many images**, shared by the desktop gallery and the phone web app's facade: `removeAvatars(characterId, ids)` in `CharacterMediaStore`.
   - It deletes the rows in one database transaction first, then the files. Today's single delete removes the file first, so a failure can leave a row with no picture.
   - The ★ default and the prime index are fixed **once** after the whole batch, not after each image.
   - The facade's copy of those steps goes away; both surfaces call the one function. The single ✕ becomes a one-item batch.
2. **Gallery, Expression images section** (desktop and Android):
   - **Select:** a toggle that turns tiles into checkboxes, the way the library's Multi-select works. It comes with **Select all**, **Select this emotion** (every `joy` alternate at once) and **Delete N**. One confirm shows the count and a strip of thumbnails.
   - **Clear expressions:** in the section's ⋮ menu. One confirm, worded with the count: "Delete all 42 expression images? The portrait and the gallery looks stay."
   - **Looks** get the same Select and Clear. The portrait is never part of a clear; removing it stays the existing swap.
3. **Replace on ZIP import:** Import ZIP sprite pack asks *Add to these* / *Replace them*. Replace clears the expressions only after the pack decodes and has at least one recognized image, so a bad ZIP never empties the gallery.
4. **Undo:** for 10 seconds after a bulk delete or a replace, a snackbar offers **Undo**. The files wait in a holding folder inside the character's folder and are deleted when the snackbar expires or the gallery closes. Undo puts the rows back with their labels, order, prime and ★.
5. **Phone web app** (`AvatarManager.tsx`): the same Select, Select all, Delete N, Clear expressions and Replace, plus Undo.
   - New route `POST /api/characters/<id>/avatars/delete` with `{ids: [...]}` or `{clear: "expressions" | "looks"}`, behind the existing login check.
   - It goes in `character_sprite_pack_routes.dart`, since `character_routes.dart` is at 485 lines; rename that file to cover avatar batches.
   - The ZIP route takes `?replace=1`.
6. **Other chats:** a chat whose saved face was a deleted image falls back to the ★ default or the portrait; the face resolver already treats a missing id that way. Clear only this chat's choice, as today.

**Tests**
- **Desktop:** a real library on disk. A bulk delete that includes the ★ default, the prime and this chat's face leaves all three pointing at what's left, and no rows or files remain for the deleted ids.
- **Replace on ZIP import:** a ZIP with no recognized images leaves the gallery untouched.
- **Undo:** restores labels, order, prime and ★.
- **Delete N** tapped twice in one frame (`doubleTapNoFrame`) deletes once.
- **Phone width:** the Select bar fits at 400 px.
- **Web:** the facade and route over real HTTP; a vitest for select, delete and the result line; a journey in `journeys.spec.ts` that imports a pack, clears it and finds it empty.
- **Red proofs:** drop the prime fix and the pointer test fails; drop the decode check on Replace and the bad-ZIP test fails.

---

## 2. [ ] Automatic updates

**Today (1.1.1):** checks the update server once at startup and asks; Download → Install Now / Later. Windows can already install on close (`installOnClose`). `tools/publish_update.dart` builds, uploads and swaps the feed; it now packages each APK from scratch (a reused one carried 54 MB of dead space).
- **Since `3d57684c` (unreleased):** Install now passes `/RELAUNCH=1` and `installers/windows/setup.iss` reopens the app as the user who started Setup. An update on close leaves it closed. 1.1.1 doesn't pass the flag, so the first update from 1.1.1 still stays closed; the one after reopens.
- **The published APK is a debug build** (`flutter build apk --debug`, debug-signed, about 297 MB) because the installed phones carry the debug key. Google Play would need a release build, which means one reinstall on those phones (see Distribution below).

**Plan**
1. **Check while running:** besides the startup check, check every 6 hours while the app is open (a `Timer` in `UpdateService`). Never interrupt a streaming reply; queue the prompt until the turn settles.
2. **Setting "When an update is found":** *Ask me* (today) / *Download it, ask before installing* / *Install it automatically*. Store it next to `update_auto_check`; show it in Settings → General on desktop and Android.
3. **Windows, automatic:** download in the background, then install silently on close (the existing `installOnClose` path, `/VERYSILENT`). A small "Update ready, installs when you close" chip in Settings.
4. **Android, automatic:** switch the installer from `ACTION_VIEW` to Android's `PackageInstaller` session API in `MainActivity.kt`. On Android 12+ an app can update *itself* without a prompt (`USER_ACTION_NOT_REQUIRED`) once it is the installer of its own current version, so the first update still asks and later ones don't. Older Android keeps asking.
5. **Safety:** keep the sha256 and size checks. Never auto-install over a newer version, and never during a chat turn.
6. **First, confirm 1.0.2 end to end:** the phone and the PC on 1.0.1 are offered 1.0.2 at startup, download it and install it.

**Tests:** the setting's three choices through a real loopback feed (the existing `update_check_failure_test` server); the periodic timer with an injectable clock; `eye-only:` Android's silent update on the emulator.

---

## 3. [ ] Your own voice from a recorded or uploaded clip ("RVC")

**What fits the app:** OmniVoice (192.168.0.100:8006) already makes **clone voices** from a sample clip plus its transcript (`voice_type: "clone"`). That gives the same result as RVC without training a model. True RVC needs Python training, which the app's engine rule (no Python, no helper processes) keeps out; it could only ever be a remote server.

**Gap:** OmniVoice's API has no upload endpoint. It lists voices (`GET /v1/audio/voices`) but can't add one.

**Decision needed before any code:** where OmniVoice's server code lives, and whether it can take an upload endpoint.

**Plan**
1. **Server (OmniVoice):** add `POST /v1/audio/voices` (multipart: `name`, `audio`, `transcript`) that saves the clip as a clone voice, plus `DELETE /v1/audio/voices/{id}`. This is outside this repo. Decide where OmniVoice's code lives first.
2. **App, Settings → Voice & Media → "Make a voice":**
   - *Record* (the `record` package the speech-to-text feature already uses; show a script to read, 10–20 s) or *Upload* a clip (wav, mp3, m4a).
   - The transcript is filled in by your Whisper server (the existing `SttService`), and stays editable.
   - Play the clip back, name it, then **Create voice** uploads it and refreshes the voice list. The new voice can be picked for a character, Your voice or the Narrator.
3. **ElevenLabs too:** ElevenLabs' API can already clone (`POST /v1/voices/add`), so the same screen works when the engine is ElevenLabs.
4. **Phone web app:** the same screen, recording in the browser (MediaRecorder), uploading through the desktop relay.
5. **Consent line** on the screen: only clone a voice you have the right to use.

**Tests:** upload against a real loopback server that stores the file (no canned JSON); `eye-only:` recording on the emulator and on desktop; a web journey for the upload.

---

## 4. [~] Backgrounds that change with the scene — phase 1 released in 1.0.4 (`ff33e488`)

**Phase 1 (released 2026-10-30 in 1.0.4):** each character has **Scenes**, pictures named by place and time (`porch.png`, `porch-night.png`) in `Characters/<name>/scenes/`. They need no database change, travel with Sync and move with a rename. When the Realism Engine's location phrase names a place with a picture, the chat background crossfades to it.
- **Matching** is by words, with a few synonyms. A known place with no picture brings the normal background back; a line with no place keeps the current one.
- **The scene is computed, never stored,** from the stance on each reply, so regenerate, swipe, delete, edit and Continue follow on their own.
- **Switches:** Settings → Appearance → Backgrounds follow the scene (on by default), and a per-chat choice in UI Settings.
- **Phone web app:** a Scenes section on the edit page, and the chat background crossfades.
- **Passed:** `test/services/scenes/scenes_test.dart` (18), the new web tests and lint, and the red proofs.
- **Windowed runs (2026-10-30):**
  - `integration_test/scene_backdrop_test.dart` passed. With the layer removed from the chat it fails, as it should.
  - The browser journey passed on both the phone browser and the desktop browser. It is marked slow and skips the scripted backend's goal check, which never ends.
  - The desktop half of the layout sweep passed. The overflows it logs are older ones in other files.
  - The Linux goldens for UI Settings, Settings → Appearance and the chat page may need `./scripts/ci-local.sh update-goldens`.
- **Known gap:** two characters with the same name (or names that reduce to the same folder name) share one Scenes folder, because the folder is the library. A deleted character's scenes also stay while another character of that name exists. Expressions avoid this through their database rows.
- **Phase 2a, released in 1.1.0 (`088b507a`):** a place the story reaches with no picture is painted automatically (Settings → Appearance switch, on by default). The side lane turns the place, stance, reply and scenario into danbooru tags (or a sentence, per Prompt style), cleaned of people, names and the wrong time; `ImageGenService` paints it landscape on local backends; saved as `<place>-<time>` into the owner's Scenes. One picture per place and light, one painting at a time, waits for a busy generator, 10-minute back-off after a failure, a deleted painting is repainted. Desktop and phone show "Painting the …" / the failure. Verified live against vLLM + reForge (`test/live/scene_painting_live_test.dart`).
- **Phase 2c, released in 1.1.4 (`0732eb85`):** the place comes from the model, not the word list. After each reply the side lane gets the Realism position, the reply, the places already pictured and the place shown now, and answers `{"place": "stairwell"}` (`lib/services/chat/scene_place_reader.dart`). A pictured place is answered by its picture's name, so it is reused. Answers are kept by the text they were read from (`cache/scene_places.json`), so a reload reads the same place and a regenerate, swipe or edit is read again; only the newest stance is asked, older ones use what the model said before. An answer that isn't that JSON (a chat model talking in character) falls back to the word list, which also gained about 75 places. Verified: `test/services/scenes/scenes_test.dart` (31), `integration_test/scene_backdrop_test.dart` on Windows, and the live test against vLLM (stairwell, a gazebo only the reply names, the veranda swing as the pictured porch, and no place for "eyes closed").
- **Phase 2b:** worlds owning scenes; scenes inside `.porch` / PNG exports; an Image Batches kind for painting a whole set up front. Matching by meaning with the embedding model is no longer needed for places.

**Today:** one chat background per theme, chosen in Background settings (presets plus your uploads). The Realism Engine already reports *"current physical position and location (brief phrase)"* every turn, and the story clock knows the time of day. A "generate a chat background" mode existed once and was retired because a generated empty room confused people, so generation here is opt-in and reviewed.

**Plan**
1. **Scene backgrounds library**, per character and per world: images tagged with a place (*kitchen, porch, bedroom, forest, tavern*) and optionally a time (*day, night*). Add them in the Avatar Gallery's neighbour: a new "Scenes" section, with upload and ZIP import named by place (`porch.png`, `porch-night.png`), reusing the sprite-pack decoder.
2. **Matching:** map the Realism location phrase to a tag. First exact or keyword match, then the embedding model the app already runs for Memory (RAG), which handles "the back steps" → *porch*. Add time-of-day from the story clock. Hold the current background until the place actually changes (no flicker while a reply streams, the same stability rule expressions use).
3. **Switching:** crossfade on the chat background and on the visual novel stage; per-chat on/off switch plus a global default (same pattern as other per-chat features).
4. **Generation (opt-in):** when no background matches, offer **Generate this place** through the connected image generator (Draw Things, ComfyUI, A1111, remote) with an "empty scene, no people" prompt built from the world's lore and the place. It's saved to the library only after you keep it. An Image Batches job can pre-generate a world's common places.
5. **Phone web app:** the chat endpoint reports the current scene background; the phone shows and crossfades it the same way.
6. **Groups:** one background per scene (it's a place, not a person), from the speaker's location report.

**Tests:** tag matching (keyword and embedding) with the real embedding model on disk; a chat journey where the location changes and the background follows; stability while streaming; the web stage shows the same image; layout sweep stops for the Scenes section at 400 and 1440 px.

---

## 5. [ ] Library sync across devices and platforms

**Today:** each device keeps its own library (SQLite plus character folders). Automatic local backups exist (`BackupService`, `VACUUM INTO` snapshots). The phone web app already shares the *desktop's* library live, through LAN, Tailscale or ngrok.

**Why phased:** syncing record by record means change tracking and tombstones on every table, and a merge bug corrupts or loses chats (the project's database rule: migrations additive, plan first). So begin with whole-library handoff, which can't half-merge.

**Plan**
1. **Phase 0 (now, no code):** use the phone web app against the desktop over Tailscale. One library, already in sync.
2. **[x] Phase 1, released in 1.0.3 (`12bd5370`, `9a2dd155`):** Settings → Sync on desktop, Android and the phone web app. See `lib/services/sync/` and `docs/user-guide.md` → "Sync your library between devices". The Windows journey, the layout sweep and the browser journey passed. Still to do: try it on the phone against your Nextcloud, and run the `live` WebDAV test (`$env:SYNC_WEBDAV_URL=…; flutter test --tags live test/services/sync/sync_place_test.dart`).
   - Settings → Sync: pick a WebDAV place (your Nextcloud), or a folder on desktop (a NAS share).
   - **Send my library:** a consistent snapshot (the backup's `VACUUM INTO` plus the character media folders, only files that changed), with a manifest: device, time, last-synced stamp.
   - **Get the library:** pulls the newest snapshot. If *this* device changed since the last sync too, it stops and asks *Keep mine / Take theirs*, with an automatic backup of what's replaced.
   - Optional: send automatically on close, check for a newer one on start.
3. **Phase 2, chats merge:** chats are what diverges most. Merge per chat session by stable ids and message timestamps; everything else stays last-writer-wins with the Phase 1 prompt. This needs a schema change (stable ids and updated-at on sessions and messages): a migration plan first, reviewed before any code.
4. **Phase 3 (maybe):** live record-level sync. Only if Phase 2 proves the model.

**Tests:** round trip between two app instances on loopback WebDAV (a real server serving real files); the conflict prompt when both sides changed; restoring the automatic backup after "Take theirs"; Android and desktop both.

---

## Follow-ups from library sync (small)

- [x] **Tests filled the Windows drive (fixed in `4c6c368f`):** several suites make a fake 21 GB model by seeking to the end and writing one byte; NTFS allocates all of it (Linux and macOS make a sparse file), and the temp folders were never deleted. On 2026-10-30 they had reached 1.1 TB and filled the drive; cleared. `test/flutter_test_config.dart` now gives each test file its own temp folder on Windows (deleted when the file's tests finish), and each file sweeps what finished runs left (per-file folders after 30 minutes, loose `fpai*` folders after a day). Folders still in use when a file finishes wait for the next sweep, so a full run peaks around 80 GB.

- [ ] **`deleteMediaFolder` is case-sensitive** (`lib/services/character_store/character_media_store.dart`, the shared-folder check): on Windows, deleting `alice` also deletes `Alice`'s gallery, since both names are the same folder there.
- [ ] **Drop `webdav_client` and `googleapis*`** from `pubspec.yaml`: nothing imports them (Sync has its own small WebDAV client). It unblocks `xml` 7 and Syncfusion 34; drop their entries from `test/deps/dependency_floors.json` in the same change.
- [ ] **Encrypt the upload (optional):** a passphrase per library, for a sync place you don't run yourself. Today the library goes up as is, and the Sync tab and PRIVACY.md say so.
- [ ] **A folder place on Android:** needs Android's folder-access API (`ACTION_OPEN_DOCUMENT_TREE` with a persisted grant); WebDAV covers phones for now.

- [ ] **Chat abort and regen timing tests fail on this PC:** `lite_abort_clock_test`, `lite_one_to_one_host_wear_test`, `regen_aborts_settling_test` (2) and `studio_desk_not_ready_test` fail at HEAD too after midnight on 2026-10-30, and passed earlier that evening. Likely clock-dependent; check against CLAUDE.md's rule that a test never pins a date the code compares with the real clock.
  - On 2026-10-31 the list was longer: `test/ui/chat_components/`, `test/ui/pages/` and `test/services/chat/` at `--concurrency=4` had 19–23 failures in 17 files, every one also failing at HEAD (the clock_*, afk_*, lite_* and refractory_clock files, director_mode_engine, history_prefix_stability, regen_aborts_settling, join_during_new_chat, context_viewer_snapshot, gist_first_recall_locks, journal_story_day_heat, reprocess_needs_contract, group_afk_speaker_needs_stamp, and `token_alternatives_pick_test` on a pending timer).

## Follow-ups from Esc, markdown and the reopen (small)

- [ ] **Rerun the Esc end-to-end suite:** `flutter test integration_test/escape_back_test.dart -d windows` (check the raid first). Its first run failed (Esc on Settings didn't go back, most likely because the focus had fallen out of the pages); the fix moved the back step to `FocusManager`'s late key handler and the widget tests cover it, but the suite hasn't run since. Its failure message prints where the focus is.
- [ ] **Run the web journey** "Escape goes back a screen, then closes the Manage Chats sheet" (`web_ui/e2e/journeys.spec.ts`) through `integration_test/web_ui/browser_test.dart -d windows`. Written, never run.
- [ ] **Try the reopen with a real update:** 1.1.2 and later ask the installer to reopen the app, so Install now from 1.1.4 to 1.1.5 should bring it back by itself. (From 1.1.1 it stays closed.)
- [ ] **Look at markdown formatting in a real chat** on the desktop and the phone web app, switch on and off.
- [ ] **Block markdown isn't rendered:** headings, lists, block quotes and fenced code show as typed. Only inline marks are handled (`lib/ui/widgets/chat_markdown.dart`, `web_ui/src/components/chatMarkdown.tsx`; keep the two the same).
- [ ] **Find can match a hidden mark:** with formatting on, a search that only matches a `*` counts a hit and lights nothing. The engine searches the text as written.
- [ ] **Esc in the Narration panel's Starting at box** closes its dropdown, but Flutter's `DropdownMenu` keeps taking Escape after that, so the box never lets go of the cursor.
- [ ] **Esc on Android with a keyboard:** the phone shell's back now goes through `ShellIntents.back()`; only `integration_test/phone_shell_test.dart` covers it, and it wasn't run.
- [x] **Push `dev`**: pushed 2026-11-01 at 1.1.5.

## Dev server (from 2026-11-01)

Builds, test suites and window-opening runs move off the desktop. CLAUDE.md → **This fork** → **Where work runs** has what the server needs and what to copy.
- [ ] **Set up a Linux server:** Flutter 3.47.7, Node 24, Docker, a JDK and the Android SDK, the Linux packages listed there, `xvfb-run` for the end-to-end suites, KVM if the emulator should run there. Clone `origin`, `flutter pub get`, build the web bundle, and run `flutter test --concurrency=4 --exclude-tags golden` once to learn which tests fail there before any change.
- [ ] **Releases still need Windows** (`tools/publish_update.dart` builds the installer with Inno Setup 6): a Windows VM on the server, or keep publishing from the desktop.
- [ ] **Copy over by hand to whatever publishes:** `tools/publish_update.env` and its ssh key, the Android debug keystore (`%USERPROFILE%\.android\debug.keystore`; without it no published APK can update an installed phone), `android/key.properties` and its keystore.
- [ ] **Live test servers:** set the environment variables the `live` tests read on the server (`grep -rn "Platform.environment\[" test integration_test`).
- [ ] **Redraw the sidebar goldens** there with `./scripts/ci-local.sh update-goldens`: all six still show the Discord row's sliver and the Stoop button.

## Follow-ups from removing The Stoop button (small)

- [ ] **The Stoop is still on Android and in the phone web app** (Characters → New → Browse The Stoop; the phone web app's menu). Decide whether it goes there too.
- [ ] **The phone web app's menu still has Join the Discord** (`web_ui/src/components/Layout.tsx`), and the desktop update dialog still has a Ko-fi button.

## Distribution and licensing (decide first)

- [~] **Source of what is running:** since 1.1.3 (`69f2c21a`) Source code and Report a license violation open `shifusen329/front-porch-AI`, and `dev` is pushed there. AGPL sections 6(d) and 13 want the source of the running build: still to do, tag each release (`v1.1.1` is `3084aa26`) and say where the source is next to the downloads.
- [ ] **Google Play, if wanted:** a Play Console account (a personal account must run a closed test with 12 testers for 14 days first); a tested release build and `.aab` from `tools/publish_update.dart`; a name of the fork's own (the AGPL grants no rights to the "Front Porch AI" name; the app id is already `app.sidepatio.android`); and the Stoop switched off at build time for that build. Give Play the existing release key, so Play and self-hosted installs can update each other. Android developer verification is planned to reach sideloaded apps everywhere in 2027.
- [ ] **Hosted models, if wanted:** a load test on 2026-10-31 put the vLLM box (one RTX PRO 6000, `Qwen3.8-Flash-Next-Uncensored-NVFP4`) at about 25–50 people chatting at once, fewer with long chats. Keep port 8006 private; customers would go through LiteLLM with a key, a rate limit and a budget each. The test script lived in a temporary folder on the desktop and isn't kept.

## Follow-ups from 1.0.2 (small)

- [ ] **Try Cx File Explorer on the phone:** Import a ZIP sprite pack from a NAS share through *Browse files in other apps*. Only the emulator's Files screen was checked.
- [ ] **Your model's labels:** in Settings → Voice & Media → Expressions, enter `Shifusen/distilbert-go_emotions-nsfw` and press **Use** on each device; the field should list the 10 extra labels.
- [ ] **Avatar Gallery on a phone:** the *Default* badge sits on top of an expression's caption. Predates 1.0.2. (The *Replace portrait* overflow was fixed with the bulk delete.)
- [ ] **`desktop_drop` applies the Kotlin Gradle Plugin:** every APK build warns that future Flutter versions will refuse to build with it. Update the plugin, or replace it, before upgrading Flutter.
- [x] **Push `dev`**: pushed 2026-10-30 at 1.0.3 (`c4ad8614`); `dev` now tracks `origin/dev`. This fork takes no pull requests.
- [ ] **Local web tests on Node 26:** about 63 vitest tests fail because Node 26's own `localStorage` replaces the browser one. Use Node 22 or 24 for `npm test`, or give vitest a `--localstorage-file`.
- [ ] **Generated plugin registrants** (`linux/`, `windows/`, `macos/`) keep showing as modified, line endings only. A `.gitattributes` rule would stop the noise.
