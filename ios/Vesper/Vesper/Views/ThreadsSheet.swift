import SwiftUI

/// Thread picker as a real sheet — nested menus were unreliable on device.
/// Cast-scoped: these are the current member's conversations only.
struct ThreadsSheet: View {
    @EnvironmentObject private var model: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    model.newThread()
                    dismiss()
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                        .foregroundStyle(model.cast.accent)
                }
                .listRowBackground(Color.white.opacity(0.04))

                if !model.threads.isEmpty {
                    Section("Recent") {
                        ForEach(model.threads) { thread in
                            Button {
                                model.openThread(thread.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(thread.title)
                                            .lineLimit(1)
                                            .foregroundStyle(VesperTheme.ink)
                                        Text(thread.updatedAt, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(VesperTheme.mute)
                                    }
                                    Spacer()
                                    if thread.id == model.currentThreadID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(model.cast.accent)
                                    }
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.04))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CastBackdrop.canvas(for: model.cast))
            .navigationTitle("\(model.cast.displayName) — threads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(model.cast.accent)
        .presentationDetents([.medium, .large])
    }
}
