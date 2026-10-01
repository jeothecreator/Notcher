import NotcherCore
import SwiftUI
import UniformTypeIdentifiers

/// What the notch becomes while a file is dragged near it.
struct DropZoneView: View {
    let arcade: ArcadeController
    @State var phase: CGFloat = 0
    @State var bob = false
    @Environment(\.previewRendering) private var previewRendering

    var body: some View {
        let m = arcade.metrics
        let targeted = arcade.dropTargeted
        let colors = LauncherPage.library.colors
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    NotcherMark(size: 11)
                    Text("notcher")
                        .font(Theme.rounded(12.5, .heavy))
                        .foregroundStyle(Theme.primary)
                }
                Spacer(minLength: m.notchWidth + 16)
                Text("LIBRARY · \(arcade.roms.count)")
                    .font(Theme.rounded(9, .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(height: m.notchHeight)
            .padding(.top, m.hasNotch ? 0 : 2)

            HStack(spacing: 18) {
                CartridgeFan(size: 76)
                    .frame(width: 104)
                    .offset(y: bob ? -3 : 3)
                    .scaleEffect(targeted ? 1.08 : 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text(targeted ? "Release to play" : "Drop a ROM to play")
                        .font(Theme.rounded(19, .heavy))
                        .foregroundStyle(Theme.primary)
                        .contentTransition(.opacity)
                    Text(detail)
                        .font(Theme.rounded(11.5, .medium))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        ForEach(ConsoleSystem.allCases, id: \.self) { system in
                            SystemBadge(system: system)
                        }
                        Text("+ zip")
                            .font(Theme.mono(9, .bold))
                            .foregroundStyle(Theme.tertiary)
                    }
                    .padding(.top, 3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(LinearGradient(
                colors: [colors[0].opacity(targeted ? 0.16 : 0.07), colors[1].opacity(targeted ? 0.12 : 0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: targeted ? colors : [.white.opacity(0.3), .white.opacity(0.15)], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: targeted ? 2 : 1.25, dash: [7, 6], dashPhase: phase)
                )
            )
            .shadow(color: colors[1].opacity(targeted ? 0.45 : 0), radius: 18)
            .padding(.top, 10)
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
        }
        .animation(Theme.snappy, value: targeted)
        .onAppear {
            guard !previewRendering else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = -13 }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    private var detail: String {
        if let name = arcade.dragNames.first {
            let more = arcade.dragNames.count - 1
            return more > 0 ? "\(name) and \(more) more" : name
        }
        return "It joins your library and starts right away. Saves are kept for you."
    }
}

/// Accepts files dropped anywhere on the notch. SwiftUI calls these on the
/// main thread; `assumeIsolated` keeps that explicit whichever way the SDK
/// annotates `DropDelegate`.
struct NotchDropDelegate: DropDelegate {
    let arcade: ArcadeController

    func validateDrop(info: DropInfo) -> Bool {
        let hasFiles = info.hasItemsConforming(to: [.fileURL])
        return MainActor.assumeIsolated { arcade.acceptsDrops } && hasFiles
    }

    func dropEntered(info: DropInfo) {
        let names = info.itemProviders(for: [.fileURL]).compactMap(\.suggestedName)
        MainActor.assumeIsolated {
            guard arcade.acceptsDrops else { return }
            if arcade.mode != .drop {
                // Dragged straight onto the open launcher: become the drop target there too.
                arcade.fileDragMoved(to: CGPoint(x: arcade.shapeRect.midX, y: 10), names: [])
            }
            arcade.dragNames = names
            arcade.dropTargetChanged(true)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { arcade.dropTargetChanged(false) }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let collector = URLCollector(count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.set(url, at: index)
                } else if let url = item as? URL {
                    collector.set(url, at: index)
                }
                group.leave()
            }
        }
        let arcade = self.arcade
        group.notify(queue: .main) {
            MainActor.assumeIsolated { arcade.handleDrop(collector.urls) }
        }
        return true
    }
}

/// Gathers URLs loaded on background queues, in drop order.
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [URL?]

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func set(_ url: URL, at index: Int) {
        lock.lock()
        slots[index] = url
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}
