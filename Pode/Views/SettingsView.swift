import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.brandAccent) private var accent: Color
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    @Environment(UpdateChecker.self) private var updater

    @State private var draft: AppSettings = AppSettings()
    @State private var showOpenAIKey = false
    @State private var showAnthropicKey = false
    @State private var showGeminiKey = false
    @State private var showCustomKey = false
    @State private var loaded = false
    @State private var testStatus: TestStatus = .idle

    /// Debounced auto-save state. We don't write on every keystroke —
    /// `pending` is the post-edit grace window, `saving` is the brief
    /// instant we hit SwiftData, `saved` is the green-check confirmation
    /// (auto-fades back to idle after a moment).
    @State private var saveStatus: SaveStatus = .idle
    @State private var saveTask: Task<Void, Never>? = nil

    private enum SaveStatus { case idle, pending, saving, saved }

    private enum TestStatus {
        case idle
        case running
        case success(reply: String, ms: Int)
        case failure(String)
    }

    var body: some View {
        GlassScroll {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: L10n.t("Configuration", language: lang).uppercased())
                    .padding(.bottom, 10)
                Text(L10n.t("Settings", language: lang))
                    .font(.serif(48, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .padding(.bottom, 24)

                userCard.padding(.bottom, 22)
                transcriptionCard.padding(.bottom, 22)
                if draft.transcribeEngine == "openai" {
                    transcriptionKeyCard.padding(.bottom, 22)
                }
                summaryProviderCard.padding(.bottom, 22)
                liquidGlassCard.padding(.bottom, 22)
                maintenanceCard.padding(.bottom, 22)
                aboutCard.padding(.bottom, 22)

                // Inline auto-save status. Not a button — the Save button
                // was retired in favour of debounced writes.
                autoSaveStatusRow
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
        .onAppear {
            if !loaded {
                draft = store.settings
                loaded = true
            }
        }
        .onDisappear {
            // If we were mid-debounce, flush the pending change so the
            // user doesn't lose edits by leaving the page quickly.
            if case .pending = saveStatus { flushSaveNow() }
            saveTask?.cancel()
        }
        // Auto-save: any draft mutation schedules a debounced write.
        .onChange(of: draft) { _, newValue in
            guard loaded else { return }            // ignore initial copy
            scheduleAutoSave(newValue)
        }
        // When any input that affects connectivity changes, clear the test
        // result so a stale "OK" / error doesn't mislead.
        .onChange(of: draft.summaryProvider) { _, _ in testStatus = .idle }
        .onChange(of: draft.anthropicKey) { _, _ in if draft.summaryProvider == "anthropic" { testStatus = .idle } }
        .onChange(of: draft.openaiKey) { _, _ in if draft.summaryProvider == "openai" { testStatus = .idle } }
        .onChange(of: draft.geminiKey) { _, _ in if draft.summaryProvider == "gemini" { testStatus = .idle } }
        .onChange(of: draft.customKey) { _, _ in if draft.summaryProvider == "custom" { testStatus = .idle } }
        .onChange(of: draft.customBaseURL) { _, _ in if draft.summaryProvider == "custom" { testStatus = .idle } }
        .onChange(of: draft.claudeModel) { _, _ in if draft.summaryProvider == "anthropic" { testStatus = .idle } }
        .onChange(of: draft.openaiSummaryModel) { _, _ in if draft.summaryProvider == "openai" { testStatus = .idle } }
        .onChange(of: draft.geminiModel) { _, _ in if draft.summaryProvider == "gemini" { testStatus = .idle } }
        .onChange(of: draft.customModel) { _, _ in if draft.summaryProvider == "custom" { testStatus = .idle } }
    }

    private var userCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("You", language: lang))
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text(L10n.t("Used for the greeting on Listen Now.", language: lang))
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 18)
            field(label: L10n.t("Display name", language: lang)) {
                TextField(L10n.t("Your name", language: lang), text: $draft.userName)
                    .textFieldStyle(.plain)
                    .font(.sans(13.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(fieldBg)
            }

            field(label: L10n.t("App language", language: lang)) {
                Picker("", selection: $draft.appLanguage) {
                    ForEach(AppLanguage.allCases) { l in
                        Text(l.displayName).tag(l.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(fieldBg)
            }
            Text(L10n.t("Used for UI labels and as the language Claude/GPT/Gemini reply in.",
                        language: lang))
                .font(.sans(11.5))
                .foregroundColor(Ink.tertiary)
        }
        .padding(28)
        .glass(.panel)
    }

    /// Cloud Whisper key — only shown when transcription engine is "openai".
    /// Local Whisper (default) doesn't need an API key.
    private var transcriptionKeyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t("OpenAI key (cloud transcription)", lang))
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text(t("Used by the OpenAI Whisper engine selected above.", lang))
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 18)

            field(label: "OpenAI API key") {
                HStack(spacing: 6) {
                    SecureOrPlainField(text: openaiBinding(), revealed: $showOpenAIKey, placeholder: "sk-…")
                    Button(showOpenAIKey ? "Hide" : "Show") {
                        showOpenAIKey.toggle()
                    }
                    .buttonStyle(GhostSmallButtonStyle())
                }
            }
            Text(t("Get one at platform.openai.com → API keys.", lang))
                .font(.sans(11.5))
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 14)

            field(label: "Whisper model") {
                Picker("", selection: $draft.whisperModel) {
                    Text("whisper-1").tag("whisper-1")
                    Text("gpt-4o-transcribe (higher quality)").tag("gpt-4o-transcribe")
                    Text("gpt-4o-mini-transcribe (cheaper)").tag("gpt-4o-mini-transcribe")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(fieldBg)
            }
        }
        .padding(28)
        .glass(.panel)
    }

    /// Provider-agnostic summary / Q&A configuration.
    private var summaryProviderCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("Summary & analysis", language: lang))
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text(t("Reads transcripts and writes summaries, takeaways, concepts, and answers. Pick any provider — keys live on this device.", lang))
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .lineSpacing(2)
                .padding(.bottom, 18)

            field(label: "Provider") {
                DarkSegmented(
                    items: AIProvider.allCases.map { ($0.rawValue, $0.displayName) },
                    selection: $draft.summaryProvider
                )
            }

            switch AIProvider(rawValue: draft.summaryProvider) ?? .anthropic {
            case .anthropic: anthropicProviderFields
            case .openai:    openaiProviderFields
            case .gemini:    geminiProviderFields
            case .custom:    customProviderFields
            }

            testConnectionRow
                .padding(.top, 18)
        }
        .padding(28)
        .glass(.panel)
    }

    /// Test-connection button + inline status. Probes the configured
    /// provider with a 16-token "say ok" round-trip — cheap enough to spam
    /// while debugging, and surfaces auth / base URL / model errors in
    /// human terms via `AIError.errorDescription`.
    @ViewBuilder
    private var testConnectionRow: some View {
        HStack(spacing: 10) {
            Button {
                runTestConnection()
            } label: {
                HStack(spacing: 6) {
                    if case .running = testStatus {
                        ProgressView().scaleEffect(0.55).frame(width: 14, height: 14)
                        Text(t("Testing…", lang))
                    } else {
                        Image(systemName: "bolt.horizontal").font(.system(size: 11))
                        Text(t("Test connection", lang))
                    }
                }
            }
            .buttonStyle(GhostButtonStyle())
            .disabled({ if case .running = testStatus { return true } else { return false } }())

            switch testStatus {
            case .idle:
                EmptyView()
            case .running:
                EmptyView()
            case .success(let reply, let ms):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Success.primary)
                        .font(.system(size: 12))
                    Text(verbatim: "OK · \(ms) ms")
                        .font(.mono(11))
                        .foregroundColor(Ink.secondary)
                    if !reply.isEmpty {
                        Text("· “\(reply.prefix(40))\(reply.count > 40 ? "…" : "")”")
                            .font(.serif(12.5))
                            .italic()
                            .foregroundColor(Ink.tertiary)
                            .lineLimit(1)
                    }
                }
            case .failure(let msg):
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Danger.primary)
                        .font(.system(size: 11))
                        .padding(.top, 2)
                    Text(msg)
                        .font(.sans(12))
                        .foregroundColor(Danger.primary)
                        .lineSpacing(2)
                        .lineLimit(3)
                }
            }
            Spacer()
        }
    }

    private func runTestConnection() {
        testStatus = .running
        let cfg = AIClientConfig(settings: draft)
        let started = Date()
        Task { @MainActor in
            do {
                let reply = try await AIService.ping(config: cfg)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                testStatus = .success(reply: reply, ms: ms)
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var anthropicProviderFields: some View {
        field(label: "Anthropic API key") {
            HStack(spacing: 6) {
                SecureOrPlainField(text: anthropicBinding(), revealed: $showAnthropicKey, placeholder: "sk-ant-…")
                Button(showAnthropicKey ? "Hide" : "Show") {
                    showAnthropicKey.toggle()
                }
                .buttonStyle(GhostSmallButtonStyle())
            }
        }
        Text(t("Get one at console.anthropic.com → API keys.", lang))
            .font(.sans(11.5))
            .foregroundColor(Ink.tertiary)
            .padding(.bottom, 14)
        field(label: "Model") {
            Picker("", selection: $draft.claudeModel) {
                Text("Claude Haiku 4.5 · \(t("fast, cheap", lang))").tag("claude-haiku-4-5-20251001")
                Text("Claude Sonnet 4.6 · \(t("better", lang))").tag("claude-sonnet-4-6")
                Text("Claude Opus 4.7 · \(t("best", lang))").tag("claude-opus-4-7")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(fieldBg)
        }
    }

    @ViewBuilder
    private var openaiProviderFields: some View {
        field(label: "OpenAI API key") {
            HStack(spacing: 6) {
                SecureOrPlainField(text: openaiBinding(), revealed: $showOpenAIKey, placeholder: "sk-…")
                Button(showOpenAIKey ? "Hide" : "Show") {
                    showOpenAIKey.toggle()
                }
                .buttonStyle(GhostSmallButtonStyle())
            }
        }
        Text(t("Same OpenAI key — also drives Whisper if the cloud engine is selected.", lang))
            .font(.sans(11.5))
            .foregroundColor(Ink.tertiary)
            .padding(.bottom, 14)
        field(label: "Model") {
            Picker("", selection: $draft.openaiSummaryModel) {
                Text("gpt-4o-mini (fast, cheap)").tag("gpt-4o-mini")
                Text("gpt-4o (balanced)").tag("gpt-4o")
                Text("gpt-4.1-mini").tag("gpt-4.1-mini")
                Text("gpt-4.1 (best)").tag("gpt-4.1")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(fieldBg)
        }
    }

    @ViewBuilder
    private var geminiProviderFields: some View {
        field(label: "Gemini API key") {
            HStack(spacing: 6) {
                SecureOrPlainField(text: geminiBinding(), revealed: $showGeminiKey, placeholder: "AIza…")
                Button(showGeminiKey ? "Hide" : "Show") {
                    showGeminiKey.toggle()
                }
                .buttonStyle(GhostSmallButtonStyle())
            }
        }
        Text(t("Get one at aistudio.google.com → Get API key.", lang))
            .font(.sans(11.5))
            .foregroundColor(Ink.tertiary)
            .padding(.bottom, 14)
        field(label: "Model") {
            HStack(spacing: 6) {
                TextField("gemini-3.1-flash-lite-preview", text: $draft.geminiModel)
                    .textFieldStyle(.plain)
                    .font(.sans(13.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(fieldBg)

                // Preset menu — picking an option fills the text field. Free
                // typing still works so new Google models can be used without
                // shipping an app update.
                Menu {
                    Section("3.1 (newest, preview)") {
                        Button("gemini-3.1-pro-preview")              { draft.geminiModel = "gemini-3.1-pro-preview" }
                        Button("gemini-3.1-flash-lite · stable")      { draft.geminiModel = "gemini-3.1-flash-lite" }
                        Button("gemini-3.1-flash-lite-preview · default") { draft.geminiModel = "gemini-3.1-flash-lite-preview" }
                        Button("gemini-3.1-flash-image-preview")      { draft.geminiModel = "gemini-3.1-flash-image-preview" }
                    }
                    Section("3") {
                        Button("gemini-3-flash-preview")              { draft.geminiModel = "gemini-3-flash-preview" }
                    }
                    Section("2.5") {
                        Button("gemini-2.5-pro")                    { draft.geminiModel = "gemini-2.5-pro" }
                        Button("gemini-2.5-flash")                  { draft.geminiModel = "gemini-2.5-flash" }
                        Button("gemini-2.5-flash-lite")             { draft.geminiModel = "gemini-2.5-flash-lite" }
                    }
                    Section("2.0") {
                        Button("gemini-2.0-flash")                  { draft.geminiModel = "gemini-2.0-flash" }
                        Button("gemini-2.0-flash-lite")             { draft.geminiModel = "gemini-2.0-flash-lite" }
                        Button("gemini-2.0-flash-thinking-exp · reasoning") {
                            draft.geminiModel = "gemini-2.0-flash-thinking-exp"
                        }
                    }
                    Section("1.5") {
                        Button("gemini-1.5-pro")                    { draft.geminiModel = "gemini-1.5-pro" }
                        Button("gemini-1.5-flash")                  { draft.geminiModel = "gemini-1.5-flash" }
                        Button("gemini-1.5-flash-8b · cheapest")    { draft.geminiModel = "gemini-1.5-flash-8b" }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(t("Presets", lang))
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .buttonStyle(GhostSmallButtonStyle())
            }
        }
        Text(t("Type any model id Google supports. Presets fill the field; the API itself accepts new ids the moment Google ships them.", lang))
            .font(.sans(11.5))
            .foregroundColor(Ink.tertiary)
            .padding(.top, 6)
    }

    @ViewBuilder
    private var customProviderFields: some View {
        field(label: "Base URL") {
            TextField("https://api.deepseek.com/v1", text: $draft.customBaseURL)
                .textFieldStyle(.plain)
                .font(.sans(13.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(fieldBg)
        }
        Text(t("Any OpenAI-compatible endpoint: DeepSeek, OpenRouter, Together, Groq, local Ollama, etc.", lang))
            .font(.sans(11.5))
            .foregroundColor(Ink.tertiary)
            .padding(.bottom, 14)

        field(label: "API key") {
            HStack(spacing: 6) {
                SecureOrPlainField(text: customKeyBinding(), revealed: $showCustomKey, placeholder: "sk-…")
                Button(showCustomKey ? "Hide" : "Show") {
                    showCustomKey.toggle()
                }
                .buttonStyle(GhostSmallButtonStyle())
            }
        }

        field(label: "Model name") {
            TextField("e.g. deepseek-chat, llama-3.1-70b", text: $draft.customModel)
                .textFieldStyle(.plain)
                .font(.sans(13.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(fieldBg)
        }
    }

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("Transcription", language: lang))
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text(t("Local runs on this Mac (free, offline). Cloud uses your OpenAI key.", lang))
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 18)

            field(label: "Engine") {
                DarkSegmented(
                    items: [
                        ("local",  t("Local · WhisperKit", lang)),
                        ("openai", t("Cloud · OpenAI Whisper", lang))
                    ],
                    selection: $draft.transcribeEngine
                )
            }

            if draft.transcribeEngine == "local" {
                field(label: "Local model") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(LocalWhisperModel.allCases, id: \.self) { m in
                            localModelRow(m)
                        }
                    }
                }
            }

            field(label: "Language") {
                Picker("", selection: $draft.transcribeLanguage) {
                    Text(t("Auto-detect", lang)).tag("")
                    Text("中文 · Chinese").tag("zh")
                    Text("English").tag("en")
                    Text("日本語 · Japanese").tag("ja")
                    Text("한국어 · Korean").tag("ko")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(fieldBg)
            }

            HStack {
                Text(t("Simplified Chinese output", lang))
                    .font(.mono(10.5, weight: .semibold))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundColor(Ink.tertiary)
                Spacer()
                Toggle("", isOn: $draft.simplifiedChinese).labelsHidden()
            }
            .padding(.top, 8)
            Text(t("Whisper outputs Traditional by default; we convert to Simplified post-transcription. Turn off to keep Traditional.", lang))
                .font(.sans(11.5))
                .foregroundColor(Ink.tertiary)
        }
        .padding(28)
        .glass(.panel)
    }

    @ViewBuilder
    private func localModelRow(_ m: LocalWhisperModel) -> some View {
        let selected = draft.localWhisperModel == m.rawValue
        let cached = LocalWhisperService.isModelCached(m)
        HStack(spacing: 12) {
            Button {
                draft.localWhisperModel = m.rawValue
                draft.localWhisperPicked = true
            } label: {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? accent : Ink.tertiary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.displayName)
                    .font(.serif(14, weight: .medium))
                    .foregroundColor(Ink.primary)
                Text("\(m.sizeLabel) · \(m.speedLabel) · \(m.qualityLabel)")
                    .font(.mono(11))
                    .foregroundColor(Ink.tertiary)
            }
            Spacer()
            if cached {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Success.primary)
                    Text(t("Downloaded", lang))
                }
                .font(.mono(10))
                .foregroundColor(Ink.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? accent.opacity(0.06) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? accent.opacity(0.25) : Color.black.opacity(0.05),
                                lineWidth: 1)
                )
        )
    }

    private var liquidGlassCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("Liquid glass", language: lang))
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text(t("Tune the look and feel of the canvas.", lang))
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 18)

            field(label: "Accent color") {
                HStack(spacing: 8) {
                    ForEach(["#d06a3a", "#0075de", "#1f7a4c", "#7a3a78", "#141413", "#b85527"], id: \.self) { hex in
                        Button {
                            draft.accentHex = hex
                        } label: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(draft.accentHex == hex ? Color(.sRGB, white: 0, opacity: 0.95) : Color.black.opacity(0.1),
                                                lineWidth: draft.accentHex == hex ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            field(label: "Bloom strength · \(String(format: "%.2f", draft.bloomStrength))") {
                Slider(value: $draft.bloomStrength, in: 0...1.4, step: 0.05)
            }
            HStack {
                Text(t("Secondary bloom", lang))
                    .font(.mono(10.5, weight: .semibold))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundColor(Ink.tertiary)
                Spacer()
                Toggle("", isOn: $draft.showSecondaryBloom)
                    .labelsHidden()
            }
            .padding(.top, 16)
        }
        .padding(28)
        .glass(.panel)
    }

    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("Maintenance", language: lang))
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text(t("Recompute the concept galaxy from current AI analysis.", lang))
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 18)
            Button {
                store.rebuildConcepts()
                store.toast("Concepts rebuilt")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    Text(t("Rebuild concept index", lang))
                }
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(28)
        .glass(.panel)
    }

    // MARK: - About / Acknowledgements

    /// Per-dependency attribution row. Tuples are
    /// `(displayName, license, source URL)`. Kept here so adding a new
    /// SwiftPM package means one new row, not a separate file.
    private static let dependencies: [(name: String, license: String, url: String)] = [
        ("WhisperKit",          "Apache 2.0", "https://github.com/argmaxinc/WhisperKit"),
        ("swift-transformers",  "Apache 2.0", "https://github.com/huggingface/swift-transformers"),
        ("swift-jinja",         "MIT",        "https://github.com/huggingface/swift-jinja"),
        ("swift-collections",   "Apache 2.0", "https://github.com/apple/swift-collections"),
        ("swift-crypto",        "Apache 2.0", "https://github.com/apple/swift-crypto"),
        ("yyjson",              "MIT",        "https://github.com/ibireme/yyjson"),
    ]

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("About", language: lang))
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text(t("Pode is open infrastructure on the shoulders of open-source. These are the libraries that make it work.", lang))
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .lineSpacing(2)
                .padding(.bottom, 18)

            // Privacy + terms shortcuts — single source of truth lives on
            // the marketing site so the legal copy stays one document.
            HStack(spacing: 14) {
                Link(destination: URL(string: "https://podecast.cc/privacy.html")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.raised").font(.system(size: 10))
                        Text(t("Privacy", lang))
                    }
                }
                .buttonStyle(TextButtonStyle())
                Link(destination: URL(string: "https://podecast.cc/terms.html")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text").font(.system(size: 10))
                        Text(t("Terms", lang))
                    }
                }
                .buttonStyle(TextButtonStyle())
            }
            .padding(.bottom, 22)

            Text(t("Open-source libraries", lang).uppercased())
                .font(.mono(10.5, weight: .semibold))
                .tracking(1.3)
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.dependencies, id: \.name) { dep in
                    HStack(spacing: 10) {
                        Text(dep.name)
                            .font(.sans(13.5, weight: .medium))
                            .foregroundColor(Ink.primary)
                        Text(dep.license)
                            .font(.mono(10.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.black.opacity(0.05))
                            )
                            .foregroundColor(Ink.secondary)
                        Spacer()
                        if let u = URL(string: dep.url) {
                            Link(destination: u) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.right").font(.system(size: 9))
                                    Text(t("Source", lang)).font(.mono(11))
                                }
                                .foregroundColor(Ink.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.bottom, 18)

            Text(t("Audio transcription is performed locally via WhisperKit on Apple Silicon. AI summaries and Q&A use the provider configured above, calling that provider directly from this Mac — no Pode server is involved.", lang))
                .font(.sans(12))
                .foregroundColor(Ink.tertiary)
                .lineSpacing(2)
                .padding(.bottom, 14)

            // Update-check row. Manual "Check now" works regardless
            // of when the periodic 24h check last fired. If a newer
            // version is already known, the row inlines a Download
            // CTA so the user doesn't have to also dismiss the
            // floating chip.
            updateRow

            HStack(spacing: 8) {
                Text("Pode v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.mono(11))
                    .foregroundColor(Ink.tertiary)
                Text("·").foregroundColor(Ink.tertiary)
                Text("© 2026")
                    .font(.mono(11))
                    .foregroundColor(Ink.tertiary)
            }
        }
        .padding(28)
        .glass(.panel)
    }

    @ViewBuilder
    private var updateRow: some View {
        HStack(spacing: 10) {
            if let update = updater.available {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(accent)
                Text("Pode \(update.version) \(t("available", lang))")
                    .font(.sans(12.5, weight: .medium))
                    .foregroundColor(Ink.primary)
                Spacer()
                Button {
                    updater.openDownload()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down").font(.system(size: 10))
                        Text(t("Download", lang))
                    }
                }
                .buttonStyle(TextButtonStyle())
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(Ink.tertiary)
                Text(t("You're on the latest version.", lang))
                    .font(.sans(12.5))
                    .foregroundColor(Ink.tertiary)
                Spacer()
                Button {
                    Task { await updater.checkNow() }
                } label: {
                    HStack(spacing: 4) {
                        if updater.isChecking {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                        }
                        Text(t("Check for updates", lang))
                    }
                }
                .buttonStyle(TextButtonStyle())
                .disabled(updater.isChecking)
            }
        }
        .padding(.vertical, 8)
        .padding(.bottom, 8)
    }

    private func field<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.mono(10.5, weight: .semibold))
                .tracking(1.3)
                .foregroundColor(Ink.tertiary)
            content()
        }
        .padding(.bottom, 16)
    }

    private var fieldBg: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
    }

    private func openaiBinding() -> Binding<String> {
        Binding(get: { draft.openaiKey ?? "" },
                set: { draft.openaiKey = $0.isEmpty ? nil : $0 })
    }

    private func anthropicBinding() -> Binding<String> {
        Binding(get: { draft.anthropicKey ?? "" },
                set: { draft.anthropicKey = $0.isEmpty ? nil : $0 })
    }

    private func geminiBinding() -> Binding<String> {
        Binding(get: { draft.geminiKey ?? "" },
                set: { draft.geminiKey = $0.isEmpty ? nil : $0 })
    }

    private func customKeyBinding() -> Binding<String> {
        Binding(get: { draft.customKey ?? "" },
                set: { draft.customKey = $0.isEmpty ? nil : $0 })
    }

    /// Debounce window in nanoseconds. ~600ms is short enough to feel
    /// responsive after a typed key, long enough that we're not writing
    /// 10x while the user types a model name.
    private static let saveDebounceNs: UInt64 = 600_000_000

    private func scheduleAutoSave(_ value: AppSettings) {
        saveTask?.cancel()
        saveStatus = .pending
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.saveDebounceNs)
            if Task.isCancelled { return }
            saveStatus = .saving
            store.saveSettings(value)
            saveStatus = .saved
            // Hold the green check briefly, then fade to idle.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { saveStatus = .idle }
        }
    }

    /// Used on view-disappear: skip the debounce window and write right
    /// away so leaving the page mid-edit doesn't lose the user's input.
    private func flushSaveNow() {
        saveTask?.cancel()
        store.saveSettings(draft)
        saveStatus = .idle
    }

    @ViewBuilder
    private var autoSaveStatusRow: some View {
        HStack(spacing: 8) {
            switch saveStatus {
            case .idle:
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 12))
                    .foregroundColor(Ink.tertiary)
                Text(L10n.t("Changes save automatically", language: lang))
                    .font(.sans(12))
                    .foregroundColor(Ink.tertiary)
            case .pending:
                Circle()
                    .fill(Ink.tertiary)
                    .frame(width: 6, height: 6)
                Text(L10n.t("Editing…", language: lang))
                    .font(.sans(12))
                    .foregroundColor(Ink.tertiary)
            case .saving:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
                Text(L10n.t("Saving…", language: lang))
                    .font(.sans(12))
                    .foregroundColor(Ink.secondary)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Success.primary)
                Text(L10n.t("Saved", language: lang))
                    .font(.sans(12, weight: .medium))
                    .foregroundColor(Success.primary)
            }
            Spacer()
        }
        .animation(.easeOut(duration: 0.18), value: statusKey)
    }

    /// Stable identity for the status row's animation. Uses an enum-like
    /// integer so SwiftUI sees discrete transitions without comparing the
    /// associated values that `.success` carries on `TestStatus`.
    private var statusKey: Int {
        switch saveStatus {
        case .idle:    return 0
        case .pending: return 1
        case .saving:  return 2
        case .saved:   return 3
        }
    }
}

private struct SecureOrPlainField: View {
    @Binding var text: String
    @Binding var revealed: Bool
    let placeholder: String

    var body: some View {
        Group {
            if revealed {
                TextField(placeholder, text: $text)
            } else {
                SecureField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.sans(13.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

/// Brand-styled segmented control. Visually identical to a SwiftUI
/// `Picker(.segmented)` but the active segment is `Ink.onPaper` (the
/// dark/black brand color) with white text, matching the `PrimaryButton`
/// look — instead of the system-blue tint that the native segmented
/// control hard-codes on macOS.
struct DarkSegmented<T: Hashable>: View {
    let items: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.value) { item in
                let isSelected = selection == item.value
                Button {
                    selection = item.value
                } label: {
                    Text(item.label)
                        .font(.sans(13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : Ink.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Ink.onPaper : Color.black.opacity(0.04))
                        )
                        // Make the entire pill rectangle clickable, not
                        // just the glyphs — same dead-zone fix the tab
                        // pills got.
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
