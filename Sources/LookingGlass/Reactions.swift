import SwiftUI

struct ReactionItem: Identifiable {
    let id = UUID()
    let emoji: String
    let x: CGFloat          // 0...1 across the view
    let drift: CGFloat      // horizontal wobble in points
    let size: CGFloat
    let delay: Double
    let duration: Double
}

/// Fires little emoji bursts that float up over the camera feed.
final class ReactionEngine: ObservableObject {
    static let shared = ReactionEngine()
    static let palette = ["❤️", "👍", "😂", "🎉", "🔥", "😮"]

    @Published private(set) var items: [ReactionItem] = []

    func fire(_ emoji: String) {
        let burst = (0..<6).map { i in
            ReactionItem(emoji: emoji, x: .random(in: 0.18...0.82), drift: .random(in: -26...26),
                         size: .random(in: 26...46), delay: Double(i) * 0.07, duration: .random(in: 1.4...2.1))
        }
        items.append(contentsOf: burst)
        let ids = Set(burst.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            self?.items.removeAll { ids.contains($0.id) }
        }
    }

    func fire(index: Int) {
        guard Self.palette.indices.contains(index) else { return }
        fire(Self.palette[index])
    }
}

struct ReactionLayer: View {
    @ObservedObject var engine = ReactionEngine.shared
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            ForEach(engine.items) { ReactionBubble(item: $0, width: width, height: height) }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

private struct ReactionBubble: View {
    let item: ReactionItem
    let width: CGFloat
    let height: CGFloat
    @State private var phase = 0   // 0 waiting, 1 rising, 2 fading

    var body: some View {
        Text(item.emoji)
            .font(.system(size: item.size))
            .scaleEffect(phase == 0 ? 0.3 : 1)
            .opacity(phase == 1 ? 1 : 0)
            .offset(x: phase == 0 ? 0 : item.drift, y: phase == 0 ? 0 : -height * 0.7)
            .position(x: width * item.x, y: height - 36)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(item.delay))
                    withAnimation(.easeOut(duration: item.duration)) { phase = 1 }
                    try? await Task.sleep(for: .seconds(item.duration * 0.55))
                    withAnimation(.easeIn(duration: item.duration * 0.45)) { phase = 2 }
                }
            }
    }
}
