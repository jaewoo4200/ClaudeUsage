import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var language: LanguageStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let image = MenuBarLabelRenderer.makeImage(
            claudeValue: claudeValue,
            claudeUtilization: vm.state.isLoaded ? vm.fiveHourUtilization : nil,
            codexValue: codexValue,
            codexUtilization: vm.openAIState.isLoaded ? vm.openAIPrimaryUtilization : nil,
            colorScheme: colorScheme,
            weight: appKitTextWeight
        )

        Image(nsImage: image)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .frame(width: image.size.width, height: image.size.height)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Claude \(claudeValue), Codex \(codexValue)")
    }

    private var claudeValue: String {
        let _ = language.current
        if vm.state.isLoaded { return "\(Int(round(vm.fiveHourUtilization)))%" }
        switch vm.state {
        case .loading: return "…"
        case .error: return "!"
        case .needsLogin: return "—"
        case .loaded: return "—"
        }
    }

    private var codexValue: String {
        let _ = language.current
        if vm.openAIState.isLoaded { return "\(Int(round(vm.openAIPrimaryUtilization)))%" }
        switch vm.openAIState {
        case .loading: return "…"
        case .error: return "!"
        case .unavailable: return "—"
        case .loaded: return "—"
        }
    }

    private var appKitTextWeight: NSFont.Weight {
        if vm.hasAnyLoadedProvider {
            switch UsageLevel.from(vm.highestPrimaryUtilization) {
            case .ok: return .semibold
            case .warn: return .bold
            case .danger: return .heavy
            }
        }
        return .semibold
    }
}

@MainActor
private enum MenuBarLabelRenderer {
    private struct Item {
        let provider: ProviderBrand
        let value: String
        let utilization: Double?
    }

    private static let imageHeight: CGFloat = 19
    private static let iconSlotWidth: CGFloat = 17
    private static let iconTextSpacing: CGFloat = 2
    private static let providerSpacing: CGFloat = 6

    static func makeImage(
        claudeValue: String,
        claudeUtilization: Double?,
        codexValue: String,
        codexUtilization: Double?,
        colorScheme: ColorScheme,
        weight: NSFont.Weight
    ) -> NSImage {
        let items = [
            Item(provider: .claude, value: claudeValue, utilization: claudeUtilization),
            Item(provider: .codex, value: codexValue, utilization: codexUtilization)
        ]
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: weight)
        let attributes = items.map {
            textAttributes(
                utilization: $0.utilization,
                value: $0.value,
                font: font,
                colorScheme: colorScheme
            )
        }
        let textSizes = zip(items, attributes).map { item, attributes in
            (item.value as NSString).size(withAttributes: attributes)
        }
        let contentWidth = zip(items, textSizes).reduce(CGFloat.zero) { partial, pair in
            partial + iconSlotWidth + iconTextSpacing + ceil(pair.1.width)
        } + providerSpacing

        let image = NSImage(
            size: NSSize(width: ceil(contentWidth), height: imageHeight),
            flipped: false
        ) { _ in
            var x: CGFloat = 0
            for index in items.indices {
                drawIcon(items[index].provider, slotOriginX: x, colorScheme: colorScheme)
                x += iconSlotWidth + iconTextSpacing

                let textSize = textSizes[index]
                let y = floor((imageHeight - textSize.height) / 2)
                (items[index].value as NSString).draw(
                    at: NSPoint(x: x, y: y),
                    withAttributes: attributes[index]
                )
                x += ceil(textSize.width)
                if index < items.count - 1 { x += providerSpacing }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func textAttributes(
        utilization: Double?,
        value: String,
        font: NSFont,
        colorScheme: ColorScheme
    ) -> [NSAttributedString.Key: Any] {
        let color: NSColor
        if let utilization {
            switch UsageLevel.from(utilization) {
            case .ok:
                color = colorScheme == .dark ? .white : .black
            case .warn:
                color = .systemOrange
            case .danger:
                color = .systemRed
            }
        } else if value == "!" {
            color = .systemRed
        } else {
            color = colorScheme == .dark
                ? NSColor(white: 0.72, alpha: 1)
                : NSColor(white: 0.38, alpha: 1)
        }
        return [.font: font, .foregroundColor: color]
    }

    private static func drawIcon(
        _ provider: ProviderBrand,
        slotOriginX: CGFloat,
        colorScheme: ColorScheme
    ) {
        let iconSize: CGFloat = provider == .claude ? 14.5 : 16.5
        let rect = NSRect(
            x: slotOriginX + (iconSlotWidth - iconSize) / 2,
            y: (imageHeight - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )

        if let icon = ProviderBrandIconLoader.image(for: provider, colorScheme: colorScheme) {
            icon.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: false,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return
        }

        let fill = provider == .claude
            ? NSColor(red: 0.85, green: 0.43, blue: 0.29, alpha: 1)
            : NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()

        let letter = provider.compactLabel as NSString
        let font = NSFont.systemFont(ofSize: iconSize * 0.54, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = letter.size(withAttributes: attributes)
        letter.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
