import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var draft: AppSettings = AppSettings()
    @State private var showOpenAIKey = false
    @State private var showAnthropicKey = false
    @State private var saving = false
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: "Configuration").padding(.bottom, 10)
                Text("Settings")
                    .font(.serif(48, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .padding(.bottom, 24)

                userCard.padding(.bottom, 22)
                aiKeysCard.padding(.bottom, 22)
                liquidGlassCard.padding(.bottom, 22)
                maintenanceCard.padding(.bottom, 22)

                Button {
                    save()
                } label: {
                    Text(saving ? "Saving…" : "Save settings")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(saving)
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
    }

    private var userCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("You")
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text("Used for the greeting on Listen Now.")
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 18)
            field(label: "Display name") {
                TextField("Your name", text: $draft.userName)
                    .textFieldStyle(.plain)
                    .font(.sans(13.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(fieldBg)
            }
        }
        .padding(28)
        .glass(.panel)
    }

    private var aiKeysCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI keys")
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text("Keys are stored locally (SwiftData on this device). Whisper handles transcription; Claude reads transcripts and writes summaries, takeaways, concepts, and answers.")
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .lineSpacing(2)
                .padding(.bottom, 18)

            field(label: "OpenAI API key (Whisper)") {
                HStack(spacing: 6) {
                    SecureOrPlainField(text: openaiBinding(), revealed: $showOpenAIKey, placeholder: "sk-…")
                    Button(showOpenAIKey ? "Hide" : "Show") {
                        showOpenAIKey.toggle()
                    }
                    .buttonStyle(GhostSmallButtonStyle())
                }
            }
            Text("Get one at platform.openai.com → API keys.")
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

            field(label: "Anthropic API key (Claude)") {
                HStack(spacing: 6) {
                    SecureOrPlainField(text: anthropicBinding(), revealed: $showAnthropicKey, placeholder: "sk-ant-…")
                    Button(showAnthropicKey ? "Hide" : "Show") {
                        showAnthropicKey.toggle()
                    }
                    .buttonStyle(GhostSmallButtonStyle())
                }
            }
            Text("Get one at console.anthropic.com → API keys.")
                .font(.sans(11.5))
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 14)

            field(label: "Claude model") {
                Picker("", selection: $draft.claudeModel) {
                    Text("Claude Haiku 4.5 (fast, cheap)").tag("claude-haiku-4-5-20251001")
                    Text("Claude Sonnet 4.6 (better)").tag("claude-sonnet-4-6")
                    Text("Claude Opus 4.7 (best)").tag("claude-opus-4-7")
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

    private var liquidGlassCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Liquid glass")
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text("Tune the look and feel of the canvas.")
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
            field(label: "Glass blur · \(Int(draft.glassBlur))px") {
                Slider(value: $draft.glassBlur, in: 6...48, step: 1)
            }
            HStack {
                Text("Secondary bloom")
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
            Text("Maintenance")
                .font(.serif(22, weight: .medium))
                .foregroundColor(Ink.primary)
                .padding(.bottom, 4)
            Text("Recompute the concept galaxy from current AI analysis.")
                .font(.sans(13))
                .foregroundColor(Ink.tertiary)
                .padding(.bottom, 18)
            Button {
                store.rebuildConcepts()
                store.toast("Concepts rebuilt")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    Text("Rebuild concept index")
                }
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(28)
        .glass(.panel)
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

    private func save() {
        saving = true
        store.saveSettings(draft)
        store.toast("Settings saved")
        saving = false
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
