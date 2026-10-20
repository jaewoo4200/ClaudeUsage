import SwiftUI

struct CodexPetAvatar: View {
    let mood: PetMood
    let size: CGFloat
    let animated: Bool
    var time: TimeInterval?
    var refreshActive = true
    @ObservedObject private var store = CodexPetStore.shared

    var body: some View {
        Group {
            if animated, time == nil, store.sheet != nil {
                TimelineView(.periodic(from: .now, by: 0.16)) { context in
                    sprite(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                sprite(time: time ?? 0)
            }
        }
        .frame(width: size, height: size)
        .help(store.sheet?.name ?? "codex_pet_missing".l)
        .task(id: refreshActive) {
            guard refreshActive else { return }
            repeat {
                await store.refresh()
                if time != nil { break }
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { break }
            } while !Task.isCancelled
        }
    }

    @ViewBuilder
    private func sprite(time: TimeInterval) -> some View {
        if let frame = store.frame(mood: mood, time: time) {
            Image(decorative: frame, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(size * 0.08)
        } else {
            Image(systemName: "pawprint")
                .font(.system(size: size * 0.38))
                .foregroundStyle(.secondary)
                .accessibilityLabel("codex_pet_missing".l)
        }
    }
}
