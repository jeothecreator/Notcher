import NotcherCore
import SwiftUI
import UniformTypeIdentifiers

/// Frames of hoverable launcher items in panel coordinates.
struct ItemFramesKey: PreferenceKey {
    static let defaultValue: [LauncherItem: CGRect] = [:]

    static func reduce(value: inout [LauncherItem: CGRect], nextValue: () -> [LauncherItem: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Reports this view's frame so the controller can hit-test hover.
    func hoverItem(_ item: LauncherItem) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ItemFramesKey.self, value: [item: proxy.frame(in: .named("panel"))])
            }
        )
    }
}

struct NotchRootView: View {
    let arcade: ArcadeController

    private var expanded: Bool { arcade.mode.isExpanded }

    var body: some View {
        let size = arcade.shapeSize
        let hasToast = arcade.toast != nil
        let top: CGFloat = expanded ? 14 : (hasToast ? 10 : 7)
        let bottom: CGFloat = expanded ? 28 : (hasToast ? 20 : (arcade.metrics.hasNotch ? 11 : 13))

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: top, bottomRadius: bottom)
                    .fill(Color.black)
                    .overlay(
                        // A hairline of light along the edge, only once expanded.
                        NotchShape(topRadius: top, bottomRadius: bottom)
                            .stroke(
                                LinearGradient(colors: [.white.opacity(0), .white.opacity(expanded ? 0.12 : 0)], startPoint: .top, endPoint: .bottom),
                                lineWidth: 1
                            )
                    )

                content
                    .frame(width: size.width, height: size.height, alignment: .top)
            }
            .frame(width: size.width)
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: size.width)
            .frame(height: size.height, alignment: .top)
            .animation(.spring(response: 0.46, dampingFraction: 0.82), value: size.height)
            .clipShape(NotchShape(topRadius: top, bottomRadius: bottom))
            .onDrop(of: [.fileURL], delegate: NotchDropDelegate(arcade: arcade))
            .overlay(alignment: .bottom) {
                if expanded, let toast = arcade.toast {
                    ToastPill(toast: toast)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .shadow(color: .black.opacity(expanded ? 0.6 : 0), radius: 22, y: 10)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The panel sits over the camera housing; never inset for it.
        .ignoresSafeArea()
        .coordinateSpace(.named("panel"))
        .focusEffectDisabled()
        .onPreferenceChange(ItemFramesKey.self) { frames in
            arcade.itemFrames = frames
        }
        .onPreferenceChange(LibraryViewportKey.self) { rect in
            arcade.libraryViewport = rect
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch arcade.mode {
        case .closed:
            if let toast = arcade.toast {
                ToastBanner(toast: toast, metrics: arcade.metrics)
                    .transition(.notchContent)
                    .id(toast.id)
            } else {
                ClosedNotchView(arcade: arcade)
                    .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.15)))
            }
        case .launcher:
            LauncherView(arcade: arcade)
                .transition(.notchContent)
        case .trophies:
            TrophiesView(arcade: arcade)
                .transition(.notchContent)
        case .game:
            if let session = arcade.activeSession {
                GameScreen(arcade: arcade, session: session)
                    .transition(.notchContent)
                    .id(ObjectIdentifier(session))
            }
        case .console:
            if let session = arcade.consoleSession {
                ConsoleScreen(arcade: arcade, session: session)
                    .transition(.notchContent)
                    .id(ObjectIdentifier(session))
            }
        case .drop:
            DropZoneView(arcade: arcade)
                .transition(.notchContent)
        }
    }
}

// MARK: - Closed

struct ClosedNotchView: View {
    let arcade: ArcadeController

    var body: some View {
        let m = arcade.metrics
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let info = arcade.ticker(at: context.date)
            if m.hasNotch {
                HStack(spacing: 0) {
                    if arcade.showTicker {
                        NotcherMark(size: 13)
                            .frame(width: ArcadeController.earWidth)
                    }
                    Spacer(minLength: m.notchWidth)
                    if arcade.showTicker {
                        TickerLabel(info: info)
                            .frame(width: ArcadeController.earWidth)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    NotcherMark(size: 12)
                    Text("notcher")
                        .font(Theme.rounded(12, .bold))
                        .foregroundStyle(Theme.primary)
                    if arcade.showTicker {
                        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 10)
                        TickerLabel(info: info)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(height: m.notchHeight)
    }
}

/// The little gamepad mark that lives beside the notch.
struct NotcherMark: View {
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: "gamecontroller.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: GameID.arcade.style.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .shadow(color: GameID.arcade.style.accent.opacity(0.6), radius: 4)
    }
}

struct TickerLabel: View {
    let info: TickerInfo

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: info.symbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(LinearGradient(colors: info.colors, startPoint: .top, endPoint: .bottom))
            Text(info.text)
                .font(Theme.mono(10.5, .bold))
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Toasts

/// Shown when the notch is closed: it grows like a live activity.
struct ToastBanner: View {
    let toast: Toast
    let metrics: NotchMetrics

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.hasNotch ? metrics.notchHeight : 4)
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: toast.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: toast.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.8))
                }
                .frame(width: 26, height: 26)
                .shadow(color: toast.colors[0].opacity(0.6), radius: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(toast.subtitle.uppercased())
                        .font(Theme.rounded(8.5, .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                    Text(toast.title)
                        .font(Theme.rounded(13, .bold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Shown at the bottom of the expanded notch.
struct ToastPill: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient(colors: toast.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(toast.title)
                .font(Theme.rounded(11.5, .bold))
                .foregroundStyle(Theme.primary)
            Text(toast.subtitle)
                .font(Theme.rounded(10.5, .medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(hex: 0x1C1C22)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}
