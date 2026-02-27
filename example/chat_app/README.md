# llamadart Chat Example

A Flutter chat application demonstrating real-world usage of llamadart with UI.

## Features

- 🦙 Real-time chat with local LLM
- 🖼️ **Vision & Audio Support**: Works on native and web bridge when a matching mmproj is loaded.
- 📱 Material Design 3 UI
- ⚙️ Model configuration (path, runtime-detected backend selection, GPU layers, context size)
- 🧩 Capability badges per model (Tools / Thinking / Vision / Audio / Video)
- 🎯 Per-model presets for temperature, Top-K, Top-P, context, and max tokens
- 🛠️ Tool-calling toggles with template support checks
- 💾 Settings persistence
- 🔇 Separate Dart vs native log level controls
- 🔄 Streaming generation
- 🎨 User and AI message bubbles

## Setup

### 1. Run the App
```bash
cd example/chat_app
flutter pub get
flutter run
```

### 1.1 Run Tests
```bash
cd example/chat_app
flutter test
```

Note: this is a Flutter app, so use `flutter test` (not `dart test`).

### 2. Choose and Download a Model
1. The app will open to a **Model Selection** screen.
2. Select one of the pre-configured models (for example: FunctionGemma 270M, Llama 3.2 3B, Qwen 3 4B, Gemma 3/3n, DeepSeek R1 distills).
3. Tap the **Download** icon. The app uses `Dio` to download the model directly to your device's documents directory.
4. Once downloaded, tap **Select** to load the model.

### 3. Advanced Configuration (Optional)
1. Tap the settings icon (⚙️) in the app bar.
2. Adjust **GPU Layers**, **Context Size**, **Preferred Backend**, **Dart Log Level**, and **Native Log Level**.
   - Backend choices are concrete runtime-detected options (for example: CPU/Vulkan/CUDA), not `Auto`.
3. Optionally enable **Function Calling** and edit tool declarations depending on model/template support.
4. Tap **Load Model** to apply changes.


## Testing Scenarios

### Scenario 1: Fresh Install
1. Install the app
2. Model not loaded -> Show welcome screen
3. Configure and load model
4. Verify it works

### Scenario 2: App Restart
1. Load model and chat
2. Close and reopen app
3. Verify settings persist
4. Verify model reloads automatically

### Scenario 3: Offline Mode
1. Use app once (downloads libraries)
2. Disconnect internet
3. Restart app
4. Verify it works offline

### Scenario 4: Multiple Messages
1. Load model
2. Send multiple messages
3. Verify responses
4. Check context is maintained

## Architecture

The app follows a clean, layered architecture with strict separation of concerns:

```
lib/
├── main.dart              # App entry point
├── screens/
│   ├── chat_screen.dart            # Main chat screen
│   └── model_selection_screen.dart  # Model management UI
├── widgets/
│   ├── chat_input.dart             # Message input area
│   ├── message_bubble.dart         # Styled chat bubbles
│   ├── settings_sheet.dart         # Advanced config UI
│   └── ...                         # Other modular UI components
├── providers/
│   └── chat_provider.dart          # App state & orchestration
├── services/
│   ├── chat_service.dart           # Business logic & prompt building
│   ├── model_service.dart          # File system & download logic
│   └── settings_service.dart       # Local persistence (SharedPreferences)
├── models/
│   ├── chat_message.dart           # Message data with token caching
│   ├── chat_settings.dart          # Configuration data
│   └── downloadable_model.dart     # Model metadata
└── stub/
    └── io_stub.dart                # Web compatibility stubs
```

### Key Components

- **`ChatProvider`**: Orchestrates state and reacts to user input.
- **`ChatService`**: Handles prompt construction, token counting, and engine interaction.
- **`ModelService`**: Manages the local model library and background downloads.
- **`SettingsService`**: Handles persistent storage of user preferences.
- **`ChatMessage`**: Implements **Token Caching** to optimize performance during long conversations.

## Code Examples

### Loading a Model
```dart
final engine = LlamaEngine(LlamaBackend());
await engine.loadModel(
  modelPath,
  modelParams: ModelParams(
    gpuLayers: 99, // Offload all layers for best performance on GPU
    contextSize: 2048,
    preferredBackend: GpuBackend.vulkan,
  ),
);

// Optional: Load multimodal projector
if (mmprojPath != null) {
  await engine.loadMultimodalProjector(mmprojPath);
}
```

### Sending a Multimodal Message
```dart
final messages = [
  LlamaChatMessage.withContent(
    role: LlamaChatRole.user,
    content: [
      LlamaImageContent(path: 'path/to/image.jpg'),
      LlamaTextContent('What is this image?'),
    ],
  ),
];

final stream = engine.create(
  messages,
  params: GenerationParams(
    maxTokens: 4096, // Current default in 0.5.0
    temp: 0.7,
  ),
);

await for (final chunk in stream) {
  stdout.write(chunk.choices.first.delta.content ?? '');
}
```

### Persisting Settings
```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('model_path', modelPath);
await prefs.setInt('preferred_backend', backendIndex);
```

## Screenshots

_(Add screenshots here when complete)_

## Troubleshooting

**"Failed to load library" or "Native asset not found" on first run:**
- Ensure you have an active internet connection. The `llamadart` build hook needs to download the pre-compiled `llama.cpp` binary for your platform.
- Check the console for download progress logs.
- If behind a proxy, ensure Dart/Flutter can access GitHub.
- If you recently changed native backend config and are upgrading from an older build cache, run a one-time `flutter clean`.

**"Model file not found" error:**
- Ensure you have successfully downloaded a model from the selection screen.
- If you manually moved a model, verify the path in the settings sheet.

**Slow generation:**
- Ensure hardware acceleration is enabled (e.g., Metal on Apple, Vulkan on Android/Linux/Windows).
- Check if `GPU Layers` is set to a high enough value (default 99 offloads all layers).
- Use a model with a smaller quantization level (e.g., Q4_K_M).

**Slow model downloads on iOS/Android:**
- Run on a release/profile build (`flutter run --release`) for realistic transfer performance.
- Large multimodal bundles download both model and mmproj files; expect two-stage transfer.
- Optional Hugging Face auth can improve throughput/rate-limits:
  `flutter run --dart-define=HF_TOKEN=<your_token>`
- Optional experimental parallel range downloader for large files:
  `flutter run --dart-define=LLAMADART_CHAT_PARALLEL_DOWNLOAD=true`

**Backend list/selection notes:**
- The settings sheet shows detected runtime backends/devices, not only packaged modules.
- Legacy saved `Auto` backend preferences are resolved to the best detected backend at runtime.


**App crashes on startup:**
- Check console output for error messages
- Verify llamadart dependency is correctly configured
- Ensure Flutter version >= 3.38.0

**macOS warning: "Stale file ... located outside of the allowed root paths":**
- This is usually a stale Flutter/Xcode build cache path after moving or renaming directories.
- From `example/chat_app`, run:
  - `flutter clean`
  - `flutter pub get`
  - `flutter run -d macos`

**`llama_grammar_init_impl: failed to parse grammar` during tool calls:**
- This indicates invalid generated GBNF (often from custom template/handler grammar escaping).
- Update to the latest package version and retry.
- If using custom handlers, validate grammar strings and prefer Dart raw strings (`r'''...'''`) for multiline GBNF.

**Assistant response appears as JSON (for example `{"response":"..."}`):**
- This can be model/template behavior (notably in Ministral-family flows), not necessarily a UI rendering bug.
- The chat app intentionally shows raw assistant content and adds a `content:json` debug badge when output looks JSON-shaped.
- If you want plain-text UX, unwrap known response envelopes in app-level normalization before rendering.

## Tech Stack

- **llamadart** - High-performance LLM inference
- **Provider** - Reactive state management
- **Dio** - Robust background downloads
- **SharedPreferences** - Persistent settings
- **Material Design 3** - Modern UI components
- **Google Fonts** - Typography

## Platform Support

| Platform | Status | Hardware Acceleration |
|----------|--------|-----------------------|
| macOS    | ✅ Tested | Metal |
| iOS      | ✅ Tested | Metal |
| Android  | ✅ Tested | Vulkan |
| Linux    | 🟡 Expected | Vulkan |
| Windows  | ✅ Tested | Vulkan |
| Web      | ✅ Tested | CPU / Experimental WebGPU |

### Web Limitations

- Web uses the llama.cpp bridge backend with CPU mode and experimental WebGPU acceleration.
- Bridge runtime loading is local-first (`web/webgpu_bridge`) with jsDelivr fallback.
- Override CDN source/version with `window.__llamadartBridgeAssetsRepo` and
  `window.__llamadartBridgeAssetsTag` in `web/index.html`.
- To pin self-hosted assets before build:
  `WEBGPU_BRIDGE_ASSETS_TAG=<tag> ./scripts/fetch_webgpu_bridge_assets.sh`.
- Bridge fetch defaults include Safari compatibility patching for universal
  browser support (`WEBGPU_BRIDGE_PATCH_SAFARI_COMPAT=1`,
  `WEBGPU_BRIDGE_MIN_SAFARI_VERSION=170400`).
- `web/index.html` also applies Safari compatibility patching at runtime before
  bridge initialization (including CDN fallback).
- Bridge model loading uses browser Cache Storage by default, so repeated loads
  of the same model URL can avoid full re-download.
- Current browser targets in this repo: Chrome >= 128, Firefox >= 129,
  Safari >= 17.4.
- Safari WebGPU uses a compatibility gate in `llamadart`: legacy bridge assets
  default to CPU fallback, while adaptive bridge assets can probe/cap GPU
  layers and auto-fallback to CPU when unstable.
- For legacy assets, experimental override remains available via
  `window.__llamadartAllowSafariWebGpu = true` before model load.
- Multimodal projector loading on web is URL-based (model + matching mmproj URL).
- Model selection auto-wires mmproj URLs for multimodal web models.
- Image/audio attachments on web use browser file bytes (local path-based loading remains native-only).
- On web, model files are loaded by URL (local file download/cache flow differs from native).
- On web, **Download** prefetches model/mmproj bytes into browser Cache Storage with progress.
- For very large web models, runtime may switch to worker-thread fetch-backed loading to reduce contiguous allocation pressure; this path may bypass prefetch cache reuse.
- If optional `llama_webgpu_core_mem64` bridge assets are present and supported by the browser, chat app bridge bootstrapping can prefer wasm64 core and transparently fall back to wasm32.
- Large single-file web model loading requires cross-origin isolation
  (`window.crossOriginIsolated === true`).
- You can force wasm32 preference for debugging by setting
  `window.__llamadartBridgeEnableMem64 = false` before bridge bootstrap.
- You can skip auto fetch-backed pre-attempts by setting
  `window.__llamadartBridgeAllowAutoRemoteFetchBackend = false` before bridge bootstrap.

### Hugging Face static deployment (CI)

- Workflow: `.github/workflows/chat_app_hf_static_deploy.yml`
- Triggered on pushes to `main/master` when chat app files change, and by manual dispatch.
- Required repository secret: `HF_TOKEN` (write access to your Space repo).
- Required repository variable: `HF_CHAT_APP_SPACE_REPO` in `owner/space` format.
- Manual dispatch can override target Space via `space_repo` input and deploy a specific ref via `deploy_ref`.
- The workflow-generated Space `README.md` already injects required COI headers
  for large-model web runtime support.

If deploying outside this workflow, set this frontmatter in Space README (all
lowercase):

```yaml
custom_headers:
  cross-origin-embedder-policy: require-corp
  cross-origin-opener-policy: same-origin
  cross-origin-resource-policy: cross-origin
```


## Implemented Highlights ✅

- [x] Conversation history maintenance
- [x] Multiple model support & switching
- [x] Per-model sampling/runtime presets
- [x] Model capability badges in selection cards
- [x] Professional layered architecture
- [x] Real-time streaming UI
- [x] Persistent settings & split Dart/native log control
- [x] Advanced sampling parameters (Temp/Top-K/Top-P)
