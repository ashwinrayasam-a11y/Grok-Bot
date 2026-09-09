import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKeys.macURL) private var macURL = SettingsKeys.defaultMacURL
    @AppStorage(SettingsKeys.userName) private var userName = ""
    @AppStorage(SettingsKeys.notes) private var notes = ""
    @AppStorage(SettingsKeys.warmthBias) private var warmthBias = 0.55
    @AppStorage(SettingsKeys.sadismBias) private var sadismBias = 0.55
    @AppStorage(SettingsKeys.intensityBias) private var intensityBias = 0.55
    @AppStorage(SettingsKeys.awayModel) private var awayModel = SettingsKeys.defaultAwayModel
    @AppStorage(SettingsKeys.replyStyle) private var replyStyle = "chat"
    @AppStorage(SettingsKeys.speakTypedReplies) private var speakTypedReplies = true
    @AppStorage(SettingsKeys.vesperVoice) private var vesperVoice = SettingsKeys.defaultVesperVoice
    @AppStorage(SettingsKeys.mikaVoice) private var mikaVoice = SettingsKeys.defaultMikaVoice
    @AppStorage(SettingsKeys.ttsEngine) private var ttsEngine = SettingsKeys.defaultTTSEngine
    @AppStorage(SettingsKeys.voiceIntensity) private var voiceIntensity = 0.5
    @AppStorage(SettingsKeys.voiceHeat) private var voiceHeat = 0.5
    @AppStorage(SettingsKeys.routeMode) private var routeMode = "auto"

    @AppStorage("mikaLiveEnabled") private var mikaLiveEnabled = false
    @AppStorage("mikaReplyBase") private var mikaReplyBase = "https://ashs-macbook-pro.tail75e054.ts.net"

    @State private var xaiKey: String = Keychain.get(Keychain.xaiKeyAccount) ?? ""
    @State private var mikaWebhookURL: String = Keychain.get(Keychain.mikaWebhookURLAccount) ?? ""
    @State private var mikaWebhookKey: String = Keychain.get(Keychain.mikaWebhookKeyAccount) ?? ""
    @State private var knockResult: String?
    @State private var knocking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(SettingsKeys.defaultMacURL, text: $macURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        Task { await knock() }
                    } label: {
                        HStack {
                            Text("Knock")
                            Spacer()
                            if knocking {
                                ProgressView()
                            } else if let knockResult {
                                Text(knockResult)
                                    .foregroundStyle(VesperTheme.mute)
                            }
                        }
                    }
                } header: {
                    Text("Her home — your Mac")
                } footer: {
                    Text("Run `python -m companion.phone_api` on the Mac. Find its name with `scutil --get LocalHostName`.")
                }

                Section {
                    Picker("Route", selection: $routeMode) {
                        Text("Auto").tag("auto")
                        Text("Home").tag("home")
                        Text("Away").tag("away")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: routeMode) {
                        Task { await model.refreshLink() }
                    }
                } header: {
                    Text("Route")
                } footer: {
                    Text("Auto prefers the Mac and falls back. Home pins the Mac. Away goes straight to the xAI key.")
                }

                Section {
                    SecureField("xAI API key", text: $xaiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: xaiKey) {
                            Keychain.set(
                                xaiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Keychain.xaiKeyAccount
                            )
                        }
                    TextField("Model", text: $awayModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Away — Grok direct")
                } footer: {
                    Text("Used only when her Mac is unreachable. The key lives in the iOS Keychain and never leaves this phone.")
                }

                Section {
                    Toggle("Live Mika", isOn: $mikaLiveEnabled)
                    Text("Off by default — the Mac owns Live; the phone uses her sheet so they don't fight over the same bot.")
                        .font(.footnote)
                        .foregroundStyle(VesperTheme.mute)
                    TextField("Webhook URL", text: $mikaWebhookURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: mikaWebhookURL) {
                            Keychain.set(
                                mikaWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Keychain.mikaWebhookURLAccount
                            )
                        }
                    SecureField("Webhook key", text: $mikaWebhookKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: mikaWebhookKey) {
                            Keychain.set(
                                mikaWebhookKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Keychain.mikaWebhookKeyAccount
                            )
                        }
                    TextField("Reply base (Tailscale Funnel)", text: $mikaReplyBase)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(model.mikaLiveArmed ? "Armed" : "Sheet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(model.mikaLiveArmed ? .green : VesperTheme.mute)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(
                                    model.mikaLiveArmed
                                        ? Color.green.opacity(0.15)
                                        : Color.white.opacity(0.05)
                                )
                            )
                    }
                } header: {
                    Text("Mika — live bridge")
                } footer: {
                    Text("Live turns relay through the Mac's phone API to the Mika App Chat Bridge; replies come home over the Tailscale Funnel. Credentials stay in the Keychain (or live in the Mac's .vesper files). When the bridge is down, Mika answers from her sheet.")
                }

                Section {
                    Picker("Reply style", selection: $replyStyle) {
                        Text("Chat").tag("chat")
                        Text("Narrative").tag("narrative")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Replies")
                } footer: {
                    Text("Chat keeps it tight and spoken-feel; Narrative lets scene and atmosphere breathe.")
                }

                Section {
                    Picker("Mouth", selection: $ttsEngine) {
                        ForEach(SettingsKeys.mouthEngines, id: \.self) { engine in
                            Text(engine).tag(engine)
                        }
                    }
                    Picker("Vesper voice", selection: $vesperVoice) {
                        ForEach(SettingsKeys.companionVoices, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                    Picker("Mika voice", selection: $mikaVoice) {
                        ForEach(SettingsKeys.companionVoices, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                    LabeledSlider("Energy", value: $voiceIntensity)
                    LabeledSlider("Horny", value: $voiceHeat)
                    Toggle("Speak typed replies", isOn: $speakTypedReplies)
                } header: {
                    Text("Her voice")
                } footer: {
                    Text("Energy shapes speaking pace. Mouths beyond ara need a Mac server that carries them; this repo's phone API always speaks through xAI. Chat is text only.")
                }

                Section("Presence") {
                    TextField("What she calls you", text: $userName)
                    TextField("Private notes / dynamics", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                    LabeledSlider("Warmth bias", value: $warmthBias)
                    LabeledSlider("Sadism bias", value: $sadismBias)
                    LabeledSlider("Intensity", value: $intensityBias)
                }

                Section {
                    Button("Reset mood & chat", role: .destructive) {
                        model.resetSoul()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(VesperTheme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(VesperTheme.ember)
        .onDisappear {
            Task { await model.refreshLink() }
        }
    }

    private func knock() async {
        knocking = true
        knockResult = nil
        if let link = MacLink(urlString: macURL), await link.isAwake() {
            knockResult = "she answered"
        } else {
            knockResult = "no answer"
        }
        knocking = false
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double

    init(_ label: String, value: Binding<Double>) {
        self.label = label
        self._value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(VesperTheme.mute)
            }
            Slider(value: $value, in: 0...1)
        }
    }
}
