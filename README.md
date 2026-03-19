# Video Voice Translator Recorder

Video Voice Translator Recorder is a macOS meeting companion that captures system audio and microphone input, transcribes speech, translates non-Chinese content into Chinese, lets you manually choose which detected questions should be answered, and generates an editable meeting summary that can be exported as PDF.

## Demo Preview

Add product screenshots or short demo clips here when available.

```text
README assets suggestion:
- docs/images/live-view.png
- docs/images/summary-editor.png
- docs/images/answer-panel.png
```

Example section layout you can enable later:

```md
[Live View](docs/images/live-view.png)
[Summary Editor](docs/images/summary-editor.png)
```

## Highlights

- Dual audio capture from system audio and microphone
- Speech-to-text through OpenAI or Gemini
- Separate panels for original transcript, Chinese content, and answers
- Manual question selection before LLM answering
- Chinese answers with parallel English rendering
- End-of-session summary with in-app editing and PDF export
- Local session persistence with SQLite

## Ideal Use Cases

- Bilingual meetings where live Chinese reading support is needed
- Interview capture with manual question answering support
- Lecture or webinar review with post-session summarization
- Personal note-taking for mixed-language calls

## Workflow

1. Start a session and capture system audio plus microphone input.
2. Speech is chunked, filtered, and sent to the configured ASR provider.
3. Original transcript appears in the left panel.
4. Chinese speech is shown directly in the Chinese content panel.
5. Non-Chinese speech is translated into Chinese and shown in the same panel.
6. If a transcript segment is a question, you can manually mark it and trigger answering.
7. When the session stops, the app generates a meeting summary and opens it in an editor sheet.
8. The edited summary can be saved as PDF.

## Feature Overview

### Transcript

- Live transcript list with per-segment timestamps
- Silence filtering to reduce empty or noise-only records
- Endpoint-based chunking so segments are less likely to break mid-sentence

### Translation

- Chinese source text is preserved as-is
- Non-Chinese source text is translated into Chinese
- Chinese content is kept separate from the raw transcript for easier reading during meetings

### Q&A

- Questions are detected automatically
- Answers are not generated automatically
- You manually select the question segments you care about, then trigger answer generation
- Answers include both Chinese and English output

### Summary

- Generated only after the meeting ends
- Opened in a dedicated editor sheet
- Can be edited before saving
- Exportable as PDF

## Project Structure

The app is organized as a Swift package with separate modules:

- `VVTRApp`: SwiftUI app, state management, and UI
- `VVTRCapture`: audio capture, buffer handling, and chunking
- `VVTRCloud`: ASR and LLM provider integration
- `VVTRCore`: shared models and settings
- `VVTRStorage`: SQLite persistence layer

## Architecture at a Glance

```text
System Audio / Microphone
          |
          v
   Capture + Chunking
          |
          v
        ASR Layer
          |
          v
 Transcript Segments
    |            |
    |            +--> Manual question selection --> Answer pipeline
    |
    +--> Chinese passthrough / translation pipeline
          |
          v
        UI Panels
          |
          v
   End-of-session summary + PDF export
```

## Requirements

- macOS 13 or later
- Xcode with Swift 6.1 toolchain support
- A valid API key for either OpenAI or Gemini

## Quick Start

1. Open the package in Xcode.
2. Select the `VVTRApp` scheme.
3. Run the app.
4. Open Settings and configure:
   - Provider
   - API Key
   - Base URL
   - Model
5. Grant microphone permission when requested.
6. Grant screen and system audio recording permission if you want system audio capture.

## Provider Notes

### OpenAI

- Better aligned with the current transcription flow in this project
- Uses the configured OpenAI-compatible endpoint and model settings from the app

### Gemini

- Supported, but more sensitive to project quota and model availability
- If Gemini requests fail with quota or free-tier errors, check billing and quota configuration in Google AI Studio / Google Cloud

## Permissions

The app may require:

- Microphone access for microphone capture
- Screen and System Audio Recording access for system audio capture

Microphone authorization is checked before requesting access. If permission was previously denied, macOS system settings must be updated manually.

## Data Storage

Local data is stored with SQLite and includes:

- Sessions
- Transcript segments
- Translation outputs
- Answer outputs
- Meeting summaries

API keys and provider settings are stored locally under `Application Support` and are not intended to be committed to the repository.

## Roadmap

- Add polished screenshots and demo media to the repository
- Improve streaming responsiveness for transcript rendering
- Make chunking and silence thresholds configurable in a more user-friendly way
- Add clearer provider diagnostics for quota and permission failures
- Expand export options beyond PDF

## Current Limitations

- System audio capture depends on macOS permission state and may require fully restarting the app after a permission change
- The character-by-character text effect is a UI animation, not true token streaming from the ASR service
- Summary generation happens after capture stops, not continuously during the meeting
- Accuracy depends on the selected provider, model quality, audio quality, and API quota availability
