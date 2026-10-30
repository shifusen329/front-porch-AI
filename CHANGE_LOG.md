# Change Log

Changes on the `dev` branch, newest first. Each entry names the commit that
carries it; `git log` has the full detail.

## 2026-10-30 03:03:51 -0500 (CDT)

On the `dev` branch. This is 1.0.3, with library sync (`12bd5370`, below)
and these.

### Added

- **Delete many pictures at once in the Avatar Gallery** (`01b33ea5`).
  Each section's ⋮ menu has **Select…** (pick pictures, then **Select
  all**, **Select every "joy"** for one emotion's alternates, and **Delete
  N**) and **Clear expressions** / **Clear looks**. The portrait is never
  deleted. One confirm shows how many, with thumbnails.
  - **Replace a sprite pack:** Import ZIP sprite pack asks **Add to these**
    or **Replace them** when the character has expressions. Replace only
    runs once the pack has a picture it recognizes, so a wrong ZIP never
    empties the gallery.
  - **Undo** for about 10 seconds after a delete, a clear or a replace puts
    the pictures back with their emotions, order, ★ and default expression.
  - The phone web app has the same Select, Clear, Replace and Undo, and its
    single delete now asks first, as the desktop's does.

### Fixed

- After a Send, the Sync card said nothing had been sent; it now shows the
  library just sent (`9a2dd155`).
- A new gallery picture could take the same order as an existing one after
  a delete, and both showed as the default expression (`01b33ea5`).
- Two pictures added in the same millisecond (a sprite-pack import) could
  share one file, so deleting one deleted the other's picture
  (`01b33ea5`).
- After a delete on the phone web app, chats could keep choosing the
  deleted picture until the library reloaded (`01b33ea5`).
- The portrait's **Replace portrait** label overflowed its tile on a phone
  (`01b33ea5`).

### Changed

- On Windows, test runs no longer leave their temp folders behind
  (`4c6c368f`). Several suites write a fake 21 GB model, which Windows
  stores in full; the leftovers had grown to 1.1 TB and filled the drive.

### Known gaps

- Library sync has run against a loopback WebDAV server and a folder, not
  yet against a real Nextcloud or between a real phone and PC.
- The gallery's Select mode was checked on the desktop and in the browser
  suite, not yet on the Android emulator at phone width.

## 2026-10-29 23:03:39 -0500 (CDT)

On the `dev` branch.

### Added

- **Library sync between devices** (`12bd5370`). Settings → Sync sends
  this device's whole library to a WebDAV server (such as Nextcloud) or, on
  a desktop, a folder, and gets it on another device: the PC and the
  Android phone, or two PCs. Nothing is merged. A Get replaces this
  device's library, asks **Keep mine** or **Take theirs** when this device
  changed since its last sync (and names the chats that changed), and
  **Undo** puts the old library back for 7 days. Chat photos, persona
  avatars and backgrounds are re-pointed when a library moves between
  Windows and Android. Sending on close and checking at start are
  optional. The phone web app has the same section. The WebDAV password is
  kept in the system's secure storage.

### Fixed

- **Change Data Directory** now re-points chat photos and persona avatars
  to the new folder; they used to break after a move (`12bd5370`).
- **Restoring a backup** keeps the database closed until the copy is in
  place, so nothing can reopen it halfway (`12bd5370`).

## 2026-10-29 15:41:20 -0500 (CDT)

On the `dev` branch.

### Added

- **Your own voice, a narrator voice and Narrate All** (`8ee6f0ba`).
  Settings → text to speech has a voice for your own messages with
  **Speak my messages**, and a narrator voice for narrator and Director
  lines. The chat's side panel has a **Narrate All** section that reads the
  chat aloud from any message, each line in its own voice. Each bubble's
  speaker button uses the voice its line is read in. The phone web app has
  all three.
- **Updates from the app's own server** (`9a4d22ee`). Windows and Android
  check for a newer version at startup and ask; Settings → General checks
  by hand. A download that does not match its size and checksum is thrown
  away and the app says why. On Android, Android's installer asks once to
  allow installing apps. `tools/publish_update.dart` builds and publishes a
  release. This is 1.0.1.
- **Import from any file app on Android** (`9cd65519`). Every Import opens
  Android's Files screen with **Browse files in other apps**, so file
  managers such as Cx File Explorer, and the network drives they reach,
  can hand over a file. A file of the wrong kind gets a plain message
  saying what to pick instead.
- **Up to 40 expressions, with any number of alternates** (`6bd1d9a5`).
  The Avatar Gallery counts expressions, not images: `joy.png`,
  `joy-1.png` and `joy-2.png` are one expression. The limit applies
  wherever images are added (the gallery, the creator, Image Studio packs,
  Image Batches, the phone web app); restores and `.porch` imports never
  drop images.
  - ZIP sprite packs import the plain `joy.png` first, then its alternates
    by number.
  - The phone web app's character page has **Import ZIP sprite pack** and
    the same counter.
  - A classifier model's own expression labels can be chosen by the
    Realism Engine too, so LLM mode can show them.
  - On a group's visual novel stage, the member who just spoke follows
    ONNX mode and `/expression`.

### Changed

- The Android launcher icon is the Front Porch icon instead of Flutter's
  logo, with a themed-icon layer for Android 13 (`ca745d21`).
- The updater no longer reads GitHub releases; it reads the app's own
  update server (`9a4d22ee`).

### Fixed

- A sprite pack's file names can no longer let one label take another's
  images (`reverse-cowgirl-1.png` was read as `reverse`) (`6bd1d9a5`).
- The Avatar Gallery's expression row no longer overflows on a phone
  (`6bd1d9a5`).

### Known gaps

- Android's silent self-update, periodic update checks and voice cloning
  from a clip are planned, not built.
- Cx File Explorer and NAS shares are verified on the emulator's Files
  screen only, not yet on a physical phone.

## 2026-10-28 14:07:15 -0500 (CDT)

On the `uiux` branch.

### Changed

- **The phone's bar is Chats, Porch, Images and Settings** (`cef71530`).
  The same four sit in the rail with the phone on its side. The desktop is
  unchanged.
  - **Porch** holds the library's main content in four sub-tabs:
    Characters, Personas, Worlds and Stories. Each keeps its place when you
    switch away. Back closes an open persona form before it leaves the tab,
    and switching away from unsaved persona edits asks first. Tapping the
    open sub-tab again takes it back to its start.
  - **Images** opens Image Studio over the tabs. Closing it returns to the
    tab you were on.
  - **Settings** is a tab of its own, with a **Backups** tab inside it for
    making, restoring and deleting backups. About & License is under
    General.
  - **The Stoop** moved from the bar to Characters → **New** → **Browse The
    Stoop**, next to importing a card.
  - More is gone, and the Discord and Ko-fi links are left off the phone.
- The Worlds and Personas headers fit a phone screen: below 560 px wide the
  buttons move under the title and the picture shrinks (`cef71530`).
- Release builds are signed with the key named in `android/key.properties`
  (`619b4588`). Without that file they still fall back to the debug key, and
  the build says so.

### Fixed

- **Create Backup Now tapped twice quickly makes one backup**, not two
  (`cef71530`). This was true on the desktop too.
- Persona cards no longer overflow at large text sizes; they grow to fit
  (`cef71530`).
- A long sender name at a large text size ends in "…" instead of pushing a
  message's buttons off its bubble (`cef71530`).

### Known gaps

- Pages inside Porch and Settings are still their desktop layouts fitted to
  the width; Settings rows can wrap a word per line.
- The phone tests ran on the Android emulator, not yet on a physical
  phone, and there is no Android CI job.

## 2026-10-28 03:55:27 -0500 (CDT)

On the `uiux` branch.

### Added

- **Memory search on a model server of your own** (`96642bf3`). Settings →
  Backend → **Memory search** chooses the embedding model behind Memory
  (RAG), Journal recall and the Data Bank: a model server (Ollama, or any
  OpenAI-compatible one) or the model that runs on this device.
  - Type the server's address and press **Load models**: the dropdown lists
    its embedding models. Ollama says which models embed; for other servers
    they are picked out by name. The API key is optional.
  - Search queries and saved text are worded the way each model family
    expects (nomic, Snowflake Arctic, e5, bge, mxbai, Qwen3), so searches
    find more.
  - A new install starts on a model server. One that already set up the
    on-device model keeps it.
  - **Clear and re-vectorize everything** gives every saved memory, Journal
    card and Data Bank entry a new vector from the current model, keeping
    the text. It can be stopped and finished later with **Vectorize the
    missing**, and it refuses to start when the model cannot be reached.
    When the saved vectors came from another model, the card says so: old
    memories are not found until you re-vectorize.
  - The phone web app has the same card in its Settings → Backend.
- **Visual novel mode** (`96642bf3`). Settings → Appearance → Chat
  Appearance → **Visual novel mode**, and for one chat in its UI Settings
  (As Settings, On or Off).
  - The characters stand on stage over the chat's background, each in the
    expression image for how they feel, or their portrait when they have
    none. In a group each wears their own feeling and the last speaker
    stands in front. Animated GIF and WebP expressions play.
  - The chat sits in a see-through panel over the lower part of the stage.
    Drag its handle to give it more or less room, or tap it to read the
    whole chat and tap again to see the stage.
  - The phone web app has both switches and shows the same stage.
- **The chat screen on a phone** (`96642bf3`). The side panel opens over the
  chat as a sheet from **Stats & story** in the app bar, instead of a column
  squeezing the chat. The message box gets the width: beside it are only
  **+** and one button, which is Send, Stop while a reply is written, or the
  mic when voice input is on and the box is empty. **+** holds Persona,
  Attach photo, Image Studio and Impersonate, and the chat menu moved to the
  app bar's ⋮. The composer stays clear of the gesture bar.

### Changed

- Long chat names in the app bar end in "…" instead of overflowing
  (`96642bf3`).
- The Memory sidebar says which model server memory search uses, and
  offers the on-device download when no model is set (`96642bf3`).

### Fixed

- **Text-to-speech on your own server says why it is silent** (`0ae8738c`).
  A self-hosted OpenAI-compatible server (an omnivoice box, say) no longer
  needs an API key. When it refuses, for an unsupported model such as the
  default `tts-1` or a voice it does not have, the chat shows its reason,
  on the desktop, the phone and the phone web app's Speak button.
- Checking the memory model right after choosing it reports its answer, not
  "not ready" (`96642bf3`).

### Known gaps

- The phone chat screen and visual novel mode have not been tried on a
  phone yet; their tests run on the desktop runner and have not run on a
  device.
- On a phone the chat bubbles keep the desktop's avatar column and header
  icons; a sheet for a message's actions is still to come.
- A chat never opened with Memory on is indexed only once it is opened and
  a reply arrives; re-vectorizing works on what is already saved.
- Video expressions (webm, mp4) do not play on the stage. The phone web
  app's stage follows the chat's turns, so changing the switch on the
  desktop shows there at the next turn.
- OpenAI's own TTS server with no API key still fails without a message.

## 2026-10-28 00:36:03 -0500 (CDT)

On the `uiux` branch.

### Added

- **A phone layout: five tabs in a bottom bar** (`17a9da7a`). On a phone the
  app no longer shows the desktop sidebar beside a squeezed page. A bottom
  bar holds **Chats**, **Characters**, **Stoop**, **Stories** and **More**;
  with the phone on its side or on a tablet it becomes a rail down the left.
  Each tab keeps its place when you switch away or turn the phone. Back
  steps out of a selection or a folder first, then returns to Chats, then
  leaves the app. The desktop is unchanged.
  - **Chats** is new and is where the app opens: your recent conversations,
    one-on-one and group together, newest first, each with who it is with,
    the chat's own name if it has one, when, and the last thing said.
    Tapping one opens exactly that chat. Holding one offers Start New Chat,
    Manage Chats, Rename and Delete. A search box filters by name or words,
    and **Chat** starts a new one with whoever you pick.
  - **Characters** is the library: search, a sort chip, folder chips (hold
    one to rename it, add a subfolder or delete it), and cards with an
    always-visible ⋮. The ⋮ and a long press open the same actions as the
    desktop's right-click menu, plus **Select**, which picks cards to move,
    export or delete together. **New** offers Create with AI, Create
    Character, Create Group Chat and importing a card. Import Folder is left
    out, since a phone's folder picker gives no folder the app can read.
  - **More** opens Personas, Worlds, Image Studio, Backups & Restore and
    Settings, the Discord and Ko-fi links, and About.
- The phone uses its own font size setting, up to 200%, instead of the
  desktop's scaling by window width.

### Changed

- Porch Stories' header shortens its title and story count with an ellipsis
  when text is very large, instead of overflowing (`17a9da7a`). It looks the
  same as before at normal sizes.

### Known gaps

- Opening a chat on a phone still shows the desktop chat screen squeezed to
  fit: the side panel takes half the width and the composer overflows. The
  phone chat screen is the next step.
- Pages opened from More (Settings, Personas, Worlds, Backups) are still
  their desktop layouts, and they cover the tab bar while open.
- Starting a new chat with a character that has never been opened leaves an
  extra chat holding only the greeting, which shows in Chats. This is how
  new chats already behave on the desktop (seen in Manage Chats there).
- The phone layout is tested on the desktop runner with the phone switched
  on, and by hand on the emulator; there is no Android CI job yet.

## 2026-10-27 22:40:51 -0500 (CDT)

On the `uiux` branch, from `dev` at `c009330c`.

### Changed

- **On a phone the app no longer draws under the status bar** (`ad5d5269`).
  It runs edge to edge: the status and navigation bars are transparent, and
  their icons follow the app's own light or dark theme rather than the
  phone's setting. Before, the clock sat on top of the "FRONT PORCH AI"
  title.
- **The phone opens on the app's dark background** (`ad5d5269`) instead of
  a white launch screen.
- **Android's predictive back is switched on** (`ad5d5269`). A slow back
  swipe previews the page underneath before it commits.
- The library's view state (search, folder, sort, grid size, selection and
  each card's last activity) moved out of the Home page into its own
  controller, and the chat screen's desktop layout into its own widget
  (`ad5d5269`). Nothing changes on the desktop. This makes room for the
  phone layouts, since both page files were at the 500-line limit.

### Known gaps

- The phone layout is still the desktop one apart from the status bar: the
  fixed sidebar, the squeezed chat, Settings rows wrapping a word per line,
  and Create Character's **Next** off-screen in portrait. The phone shell is
  the next step.
- The chat's composer still sits on the gesture bar at the bottom of the
  screen.

## 2026-10-27 20:58:54 -0500 (CDT)

### Added

- **Android build: starts and chats over REST** (`2df48b61`). The app ran
  only on Windows, Linux and macOS. It now builds for Android and runs there
  as a client of OpenAI-compatible model hosts.
  - First launch on a phone starts on OpenRouter. Settings → Backend offers
    OpenRouter, Nano-GPT, xAI and Custom, under a note that the device cannot
    run a local engine. A model server on another computer (KoboldCpp,
    LM Studio, vLLM, Ollama) is reached through Custom, plain `http://`
    included.
  - Chats are saved each time the app goes to the background, because
    Android ends a backgrounded app without a close event.
  - KoboldCpp, LM Studio, the web server and Waifu Coder's OpenCode download
    stay off on a phone.
  - App id `app.sidepatio.android`, Android 11 (API 30) or later. Release
    builds are arm64 only; debug builds add x86_64 for the emulator.

### Changed

- The "no local engine here" check that hid KoboldCpp on Intel Macs now
  covers phones too (`2df48b61`): the Backend tab banner, the engine chip,
  the side-jobs host bar, first-launch setup and the engine update check.
  An Intel Mac's engine download now reports the same message the Backend
  tab shows.
- **Reveal in folder** on a chat image does nothing outside Windows, macOS
  and Linux, where it used to run `xdg-open` (`2df48b61`).

### Known gaps

- On a phone the layout is still the desktop one: a fixed 250 px sidebar,
  content under the status bar, Settings rows wrapping a word per line, and
  Create Character's **Next** off-screen in portrait (landscape works). A
  phone design is drafted, not built.
- Tested only on the emulator. Not yet tried on a physical phone, against
  OpenRouter, with voice input or speech, or as a release build.
- Release builds are signed with the debug key, and the launcher icon is
  Flutter's placeholder. No CI job builds the APK.
- The library lives in the app's private storage and is lost on uninstall;
  there is no export or share on the phone yet. Folder pickers do not work
  on Android.
- The phone web app bundle (`assets/web_app`) ships inside the APK unused.
- Debug APKs still carry armeabi-v7a libraries despite the ABI filter.

## 2026-10-27 17:17:40 -0500 (CDT)

Branched from `main` at `c1a14423`.

### Added

- **Choose the ONNX expression classifier model** (`86121dbc`). With
  Expression Images set to Local ONNX Model, Settings → Voice & Media has a
  **Model** field that takes a Hugging Face model (`owner/name`, or a pasted
  huggingface.co link), with a reset to the default
  (`Cohee/distilbert-base-uncased-go-emotions-onnx`).
  - Labels come from the model's own `config.json`, so a fine-tune with more
    than go-emotions' 28 labels reports them all. Before, every output past
    the 28th came back as `neutral`, and the chat dropped any label outside
    the standard set.
  - A model's own labels join the list for tagging expression images: the
    avatar gallery picker, the character creator's upload tag dialog, and
    file names in a ZIP sprite pack.
  - Each model downloads into its own folder,
    `models/emotion_classifiers/<owner>--<name>/`, and its labels are saved
    per model. The default model keeps its old folder.
  - The phone's Settings → Voice & Media has the same field
    (`/api/voice/settings`, `expressionModel`).
- **Voices from your own OpenAI-compatible TTS server** (`b2cf8ce2`). With
  text-to-speech on OpenAI and the API Base URL pointing at another server,
  the Voice list shows the voices that server publishes at
  `{base}/audio/voices`, not OpenAI's ten. OpenAI's own address keeps
  OpenAI's voices.
  - The list loads at startup, after the base URL changes, and when the TTS
    settings open; **Refresh** reads it again. It is saved for the next launch.
  - A voice id the server does not list can be typed in.
  - The phone's Settings → Voice & Media has **Refresh voices**
    (`/api/voice/list-voices`), and the character voice picker shows the
    server's list.

### Changed

- `.gitignore` ignores `graphify-out/` and `lib/graphify-out/`, the output
  of the graphify knowledge-graph tool (`8f826908`).

### Known gaps

- Image Studio's expression packs generate only the standard emotions;
  images for a model's own labels are added by hand or by ZIP.
- A model's own labels have no emoji, so the emoji fallback and emoji burst
  show nothing for them.
- A custom TTS server still needs something in the API Key field, and the
  note under the voice picker still describes OpenAI billing.
- The ElevenLabs Refresh button fetches voices but the dropdown keeps the
  defaults (found while reading the TTS code; not changed).
