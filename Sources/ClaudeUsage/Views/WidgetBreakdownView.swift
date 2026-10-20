import SwiftUI
import Combine

@MainActor
final class WidgetBreakdownPresentation: ObservableObject {
    @Published var isWidgetHovered = false
    @Published private(set) var revealed = false
    private var hoverSuppressed = false

    func isOpen(pinned: Bool) -> Bool { pinned || revealed }
    func reveal() {
        guard !hoverSuppressed else { return }
        revealed = true
    }
    func show() {
        hoverSuppressed = false
        revealed = true
    }
    func dismiss() {
        hoverSuppressed = true
        revealed = false
    }

    func resetForLayoutChange() {
        revealed = false
        hoverSuppressed = false
    }

    func dismissAfterExit() {
        guard !isWidgetHovered else { return }
        revealed = false
        hoverSuppressed = false
    }
}

struct WidgetBreakdownView: View {
    let breakdown: UsageBreakdown

    @EnvironmentObject private var presentation: WidgetBreakdownPresentation
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var theme: ThemeStore

    private var isOpen: Bool { presentation.isOpen(pinned: settings.widgetBreakdownPinned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Button {
                    if isOpen {
                        settings.widgetBreakdownPinned = false
                        presentation.dismiss()
                    } else {
                        presentation.show()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                        Text("breakdown_claude_title".l)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(theme.current.tokens.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("breakdown_toggle_help".l)
                Spacer(minLength: 4)
                Button {
                    settings.widgetBreakdownPinned.toggle()
                    presentation.dismiss()
                } label: {
                    Image(systemName: settings.widgetBreakdownPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(settings.widgetBreakdownPinned ? theme.current.tokens.accent : theme.current.tokens.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help((settings.widgetBreakdownPinned ? "widget_breakdown_unpin" : "widget_breakdown_pin").l)
                .accessibilityLabel((settings.widgetBreakdownPinned ? "widget_breakdown_unpin" : "widget_breakdown_pin").l)
                .accessibilityIdentifier("widget-breakdown-pin")
            }
            if isOpen {
                UsageBreakdownView(breakdown: breakdown, showsTitle: false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .background(WidgetHoverRegion { if $0 { presentation.reveal() } })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("widget-breakdown")
    }
}
