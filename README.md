# Video Voice Translator Recorder

A macOS desktop app that listens to both system audio and microphone input, turns speech into text, and presents the original transcript, Chinese content, Q&A, and post-meeting summary in separate areas of the UI.

## Current Features

- Capture system audio and microphone audio
- Cloud-based speech transcription with OpenAI or Gemini
- Show either native Chinese text or translated Chinese content in the Chinese content panel
- Manually select questions before triggering answers
- Display both Chinese answers and English translations in the answer panel
- Generate a meeting summary after capture stops
- Edit the summary in a modal and export it as PDF
- Persist sessions locally in SQLite
- Switch and delete sessions from the sidebar

## Run

1. Open the Swift package in this directory with Xcode.
2. Select the `VVTRApp` scheme.
3. Run the app.

## Permissions

The app may require the following permissions:

- Microphone: capture microphone audio
- Screen and System Audio Recording: capture system audio

The app checks microphone permission status before requesting access, and only prompts when the system has not made a decision yet.

## Cloud Configuration

Fill in the following fields on the app's Settings page:

- Provider: `OpenAI / Compatible Endpoint` or `Gemini`
- API Key
- Base URL
- Model

Notes:

- The OpenAI path is currently the better fit for this project's transcription flow
- The Gemini path is more sensitive to quota limits and model support
- Configuration is stored locally under `Application Support` and is not committed to the repository

## Data Storage

Local data is stored in SQLite, including:

- Sessions
- Transcript segments
- Outputs such as Chinese content, answers, and summaries

## Known Notes

- System audio capture depends on macOS screen and system audio recording permission. If you just changed that permission, you usually need to fully quit and reopen the app.
- The current character-by-character display is a UI animation, not true token-level streaming ASR output.
- The meeting summary is generated after capture stops, not continuously while recording.
