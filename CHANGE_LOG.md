# Change Log

Changes on the `dev` branch, newest first. Each entry names the commit that
carries it; `git log` has the full detail.

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
