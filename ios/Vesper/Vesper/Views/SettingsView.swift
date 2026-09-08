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

    @State private var xaiKey: String = Keychain.get(Keychain.xaiKeyAccount) ?? ""
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
                    Toggle("Speak typed replies", isOn: $speakTypedReplies)
                    TextField("Vesper voice (xAI)", text: $vesperVoice)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Spoken turns always answer aloud. Mika speaks with eve; Chat is text only.")
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
