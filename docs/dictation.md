# Realtime Voice Dictation

Pocket Stack includes a dual-engine realtime dictation system designed to transcribe speech directly into the active editor at the current cursor selection.

---

## Dictation Engines

You can select your preferred speech recognition engine in **Settings → Dictation**:

### 1. Apple On-Device Speech (Default)
- **Engine:** macOS Speech framework using `SpeechAnalyzer` and `DictationTranscriber.progressiveLongDictation`.
- **Privacy:** 100% on-device processing. No audio is ever sent over the network.
- **Offline Capable:** Works without an active internet connection.
- **Latency:** Instant transcription with punctuation support tailored to macOS system languages.

### 2. Gemini Live Streaming Transcription
- **Engine:** Google Gemini live streaming audio API (`gemini-3.5-transcribe-live`).
- **Transport:** Full-duplex `URLSessionWebSocketTask` stream.
- **Audio Format:** Mono PCM 16-bit at 16,000 Hz, delivered in real-time ~100 ms audio chunks.
- **Configuration:** Requires a Gemini API key. The key is securely saved in your macOS Keychain.
- **Privacy:** Pocket Stack never switches from Apple to Gemini automatically; Gemini is strictly opt-in by the user.

---

## Setup & Configuration

1. **Microphone Permission:**
   Upon starting dictation for the first time, macOS will prompt you for microphone access. You can review or revoke this permission at any time in **System Settings → Privacy & Security → Microphone**.

2. **Gemini API Key Setup:**
   - Open **Settings** (`⌘,`) in Pocket Stack.
   - Navigate to the **Dictation** tab.
   - Select **Gemini Live** as your engine.
   - Enter your Gemini API key and click **Save**. The key is stored in your macOS Keychain.

3. **Triggering Dictation:**
   - Place your cursor anywhere in a note.
   - Click the microphone icon in the note toolbar or trigger the dictation shortcut to begin speaking.
   - Dictation streams transcribed words directly at your cursor.
