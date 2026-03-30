<p align="center">
  <img src="SoloWhisper/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" height="128" alt="SoloWhisper icon">
</p>

<h1 align="center">SoloWhisper</h1>

<p align="center">A lightweight macOS menu bar app for speech-to-text.<br>Press a hotkey, speak, and get your transcription pasted right where your cursor is.</p>

> This is my first open-source project. I built it for myself and use it daily. It does everything I need, but I'd love to see the community take it further.

## Features

- **Menu bar app** — lives in your menu bar, always one hotkey away
- **Push-to-talk or toggle mode** — hold the key to record, or tap to start/stop
- **Multiple presets** — different hotkeys, languages, and settings for different use cases
- **Cloud & local transcription** — OpenAI Whisper API or on-device WhisperKit
- **System audio muting** — automatically ducks system audio while you're recording so your mic stays clean
- **Custom sounds** — pick start/end recording sounds from 14 built-in macOS sounds
- **LLM post-processing** — optionally run transcriptions through GPT to fix grammar, translate, or reformat
- **Auto-paste** — transcribed text is pasted directly into the focused app, with optional clipboard restoration
- **8 languages** — English, Russian, Spanish, French, German, Chinese, Japanese, Korean (or auto-detect)
- **Transcription history** — searchable log of all your transcriptions

## How It Works

1. Configure a preset with your preferred hotkey, language, and engine
2. Press the hotkey (or hold it in push-to-talk mode)
3. Speak
4. Release the key (or press again in toggle mode)
5. Your speech is transcribed and pasted where your cursor is

Under the hood: audio is captured at 16kHz mono via AVAudioEngine, sent to OpenAI Whisper API (or processed locally with WhisperKit), optionally post-processed with an LLM, and inserted via clipboard + Cmd+V.

## Installation

1. Download `SoloWhisper.app.zip` from the [latest release](../../releases/latest)
2. Unzip and drag **SoloWhisper.app** to your Applications folder
3. Open the app — if macOS shows a security warning, go to **System Settings → Privacy & Security** and click **Open Anyway**
4. Grant **Microphone** and **Accessibility** permissions when prompted
5. Click the menu bar icon, open Settings, and add your OpenAI API key
6. Configure your first preset — pick a hotkey, language, and engine
7. Start talking

### Requirements

- macOS 14 Sonoma or later
- OpenAI API key (for cloud transcription and LLM features; not needed for local WhisperKit engine)

### Building from Source

If you prefer to build it yourself:

```bash
git clone https://github.com/chefrtm/solowhisper.git
cd solowhisper
xcodebuild -scheme SoloWhisper -configuration Release archive -archivePath build/SoloWhisper.xcarchive
```

The built app will be at `build/SoloWhisper.xcarchive/Products/Applications/SoloWhisper.app`.

## Architecture

```
SoloWhisper/
  App/           — Entry point, MenuBarExtra + Settings window
  Models/        — Preset, PresetStore, AppState, HistoryStore
  Core/
    Transcription/  — CloudEngine (OpenAI), WhisperKitEngine (on-device)
    Audio/          — AudioRecorder, SoundManager, SystemAudioDucker
    LLM/            — OpenAI Chat Completions post-processing
    Hotkeys/        — Global hotkey monitoring via CGEventTap
    TextInsertion/  — Clipboard management + auto-paste
    Security/       — Keychain-based API key storage
  Features/
    Settings/    — Preset editor, API keys, history viewer
    MenuBar/     — Menu bar UI with status indicator
```

## Security

- API keys are stored in the macOS Keychain, never in code or config files
- No data is sent anywhere except the OpenAI API (when using cloud engine)
- WhisperKit runs entirely on-device

## Future Ideas

These are directions I think would be cool but don't plan to implement myself — PRs welcome:

- **More transcription engines** — GigaAM, Deepgram, Azure Speech, local Whisper.cpp
- **More LLM providers** — local models via Ollama, Anthropic Claude, etc.
- **Audio input device selection** — choose which mic to use
- **Export options** — save transcriptions to files, Notion, etc.
- **Localized UI** — the app UI is currently English-only

## Contributing

Contributions are welcome! Whether it's a bug fix, a new transcription engine, or a UI improvement — feel free to open an issue or submit a PR.

## License

[MIT](LICENSE)
