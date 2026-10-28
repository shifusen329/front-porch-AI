# Change Log

Changes on the `dev` branch, newest first. Each entry names the commit that
carries it; `git log` has the full detail.

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
