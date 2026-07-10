import AppKit
import SwiftUI
import XCTest
@testable import ClaudeUsage

final class WidgetLayoutTests: XCTestCase {
    @MainActor
    func testMenuBarDropdownKeepsScrollableContentVisible() throws {
        let viewModel = UsageViewModel(autoStart: false)
        viewModel.state = .loaded(
            AccountSnapshot(
                organization: Organization(
                    uuid: "test",
                    name: "Test Account",
                    capabilities: ["claude_max"],
                    rateLimitTier: "max_20x"
                ),
                usage: UsageData(
                    fiveHour: UsageWindow(utilization: 37, resetsAt: Date().addingTimeInterval(3_600)),
                    sevenDay: UsageWindow(utilization: 18, resetsAt: Date().addingTimeInterval(300_000)),
                    sevenDayFable: UsageWindow(utilization: 24, resetsAt: Date().addingTimeInterval(300_000))
                )
            )
        )
        viewModel.openAIState = .loaded(try stressOpenAIUsage())

        let appDelegate = AppDelegate()
        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-menu-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL)
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        let originalPetEnabled = appSettings.usagePetEnabled
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
            appSettings.usagePetEnabled = originalPetEnabled
            try? FileManager.default.removeItem(at: historyURL)
        }
        themeStore.current = .hybrid
        languageStore.current = .ko
        appSettings.usagePetEnabled = true

        let root = MenuBarContentView()
            .environmentObject(viewModel)
            .environmentObject(appDelegate)
            .environmentObject(themeStore)
            .environmentObject(languageStore)
            .environmentObject(appSettings)
            .environmentObject(historyStore)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        size = host.fittingSize

        XCTAssertGreaterThanOrEqual(size.height, 300, "menu content must not collapse behind the footer")
        XCTAssertLessThanOrEqual(size.height, 650, "menu should remain scrollable on smaller displays")

        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-menu-dropdown.png"),
            options: .atomic
        )
    }

    @MainActor
    func testMimoSummaryCardRendersWithKoreanTrendText() throws {
        let viewModel = UsageViewModel(autoStart: false)
        viewModel.state = .loaded(
            AccountSnapshot(
                organization: Organization(
                    uuid: "test",
                    name: "Test Account",
                    capabilities: ["claude_max"],
                    rateLimitTier: "max_20x"
                ),
                usage: UsageData(
                    fiveHour: UsageWindow(utilization: 82, resetsAt: Date().addingTimeInterval(3_600)),
                    sevenDay: UsageWindow(utilization: 41, resetsAt: Date().addingTimeInterval(300_000))
                )
            )
        )
        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-mimo-card-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL, minimumSampleInterval: 0)
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        let originalHistoryEnabled = appSettings.usageHistoryEnabled
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
            appSettings.usageHistoryEnabled = originalHistoryEnabled
            try? FileManager.default.removeItem(at: historyURL)
        }

        themeStore.current = .hybrid
        languageStore.current = .ko
        appSettings.usageHistoryEnabled = true
        let now = Date()
        historyStore.record(
            UsageHistorySnapshot(
                claudeFiveHour: 58,
                claudeWeekly: 41,
                claudeModelMaximum: nil,
                openAIFiveHour: nil,
                openAIWeekly: nil,
                openAIModelMaximum: nil,
                claudeTodayTokens: 10_000,
                openAITodayTokens: nil
            ),
            at: now.addingTimeInterval(-3_000),
            force: true
        )
        historyStore.record(
            UsageHistorySnapshot(
                claudeFiveHour: 82,
                claudeWeekly: 41,
                claudeModelMaximum: nil,
                openAIFiveHour: nil,
                openAIWeekly: nil,
                openAIModelMaximum: nil,
                claudeTodayTokens: 42_500,
                openAITodayTokens: nil
            ),
            at: now,
            force: true
        )

        let root = PetSummaryCard()
            .environmentObject(viewModel)
            .environmentObject(themeStore)
            .environmentObject(languageStore)
            .environmentObject(appSettings)
            .environmentObject(historyStore)
            .frame(width: 300)
            .padding(16)
            .background(themeStore.current.tokens.bg)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-mimo-card.png"),
            options: .atomic
        )
    }

    @MainActor
    func testCompactMimoKeepsMoodBadgeAndTrendInsideItsColumn() throws {
        let viewModel = UsageViewModel(autoStart: false)
        viewModel.state = .loaded(
            AccountSnapshot(
                organization: Organization(
                    uuid: "test",
                    name: "Test Account",
                    capabilities: ["claude_max"],
                    rateLimitTier: "max_20x"
                ),
                usage: UsageData(
                    fiveHour: UsageWindow(utilization: 15, resetsAt: Date().addingTimeInterval(3_600)),
                    sevenDay: UsageWindow(utilization: 8, resetsAt: Date().addingTimeInterval(300_000))
                )
            )
        )
        let themeStore = ThemeStore()
        let languageStore = LanguageStore.shared
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-mimo-compact-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL, minimumSampleInterval: 0)
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        let originalHistoryEnabled = appSettings.usageHistoryEnabled
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
            appSettings.usageHistoryEnabled = originalHistoryEnabled
            try? FileManager.default.removeItem(at: historyURL)
        }
        themeStore.current = .daangn
        languageStore.current = .ko
        appSettings.usageHistoryEnabled = true

        let now = Date()
        historyStore.record(
            UsageHistorySnapshot(
                claudeFiveHour: 12,
                claudeWeekly: 8,
                claudeModelMaximum: nil,
                openAIFiveHour: nil,
                openAIWeekly: nil,
                openAIModelMaximum: nil,
                claudeTodayTokens: nil,
                openAITodayTokens: nil
            ),
            at: now.addingTimeInterval(-1_800),
            force: true
        )
        historyStore.record(
            UsageHistorySnapshot(
                claudeFiveHour: 15,
                claudeWeekly: 8,
                claudeModelMaximum: nil,
                openAIFiveHour: nil,
                openAIWeekly: nil,
                openAIModelMaximum: nil,
                claudeTodayTokens: nil,
                openAITodayTokens: nil
            ),
            at: now,
            force: true
        )

        let root = WidgetMimoCompanion()
            .environmentObject(viewModel)
            .environmentObject(historyStore)
            .environmentObject(appSettings)
            .environmentObject(themeStore)
            .frame(width: 204)
            .padding(10)
            .background(Color.white)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(size.width, 224, accuracy: 1)
        XCTAssertLessThanOrEqual(size.height, 90)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-mimo-compact-trend.png"),
            options: .atomic
        )
    }

    @MainActor
    func testMimoMoodSheetRendersAllStates() throws {
        let pressures: [PetMood: Double] = [
            .waiting: 0,
            .calm: 25,
            .focused: 60,
            .sleepy: 80,
            .tired: 95,
            .refreshed: 12
        ]
        let root = HStack(spacing: 16) {
            ForEach(PetMood.allCases, id: \.self) { mood in
                VStack(spacing: 8) {
                    MimoAvatar(
                        mood: mood,
                        pressure: pressures[mood] ?? 0,
                        theme: .hybrid,
                        size: 72
                    )
                    Text(mood.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black)
                }
            }
        }
        .padding(20)
        .background(Color.white)

        let host = NSHostingView(rootView: root)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-mimo-states.png"),
            options: .atomic
        )
    }

    @MainActor
    func testAllCompanionKindsRenderAcrossEveryMood() throws {
        let pressures: [PetMood: Double] = [
            .waiting: 0,
            .calm: 25,
            .focused: 60,
            .sleepy: 80,
            .tired: 95,
            .refreshed: 12
        ]
        let matrix = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Companion")
                    .frame(width: 76, alignment: .leading)
                ForEach(PetMood.allCases, id: \.self) { mood in
                    Text(mood.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 62)
                }
            }
            ForEach(CompanionKind.allCases) { kind in
                HStack(spacing: 8) {
                    Text(kind.displayName)
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 76, alignment: .leading)
                    ForEach(PetMood.allCases, id: \.self) { mood in
                        MimoAvatar(
                            mood: mood,
                            pressure: pressures[mood] ?? 0,
                            theme: .hybrid,
                            size: 62,
                            animationTime: 0.84,
                            kind: kind,
                            animationMode: .still
                        )
                        .frame(width: 62, height: 62)
                    }
                }
            }
        }
        .padding(20)
        .foregroundStyle(Color.black)
        .background(Color.white)

        let matrixHost = NSHostingView(rootView: matrix)
        matrixHost.appearance = NSAppearance(named: .aqua)
        matrixHost.layoutSubtreeIfNeeded()
        let matrixSize = matrixHost.fittingSize
        matrixHost.frame = NSRect(origin: .zero, size: matrixSize)
        matrixHost.layoutSubtreeIfNeeded()
        let matrixBitmap = try XCTUnwrap(matrixHost.bitmapImageRepForCachingDisplay(in: matrixHost.bounds))
        matrixHost.cacheDisplay(in: matrixHost.bounds, to: matrixBitmap)
        let matrixPNG = try XCTUnwrap(matrixBitmap.representation(using: .png, properties: [:]))
        XCTAssertEqual(matrixSize.width, 536, accuracy: 2)
        XCTAssertGreaterThan(matrixPNG.count, 25_000)
        try matrixPNG.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-companion-mood-matrix.png"),
            options: .atomic
        )

        let featuredMoods: [PetMood] = [
            .focused, .focused, .tired,
            .calm, .focused, .refreshed,
            .refreshed, .focused, .sleepy
        ]
        let columns = Array(repeating: GridItem(.fixed(170), spacing: 12), count: 3)
        let lineup = LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(CompanionKind.allCases.enumerated()), id: \.offset) { index, kind in
                let mood = featuredMoods[index]
                VStack(spacing: 8) {
                    MimoAvatar(
                        mood: mood,
                        pressure: pressures[mood] ?? 0,
                        theme: .hybrid,
                        size: 96,
                        animationTime: 0.84,
                        kind: kind,
                        animationMode: .still
                    )
                    Text(kind.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.10, green: 0.12, blue: 0.15))
                    Text(mood.rawValue.capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.42, green: 0.46, blue: 0.50))
                }
                .frame(width: 170, height: 158)
                .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(20)
        .background(Color.white)

        let lineupHost = NSHostingView(rootView: lineup)
        lineupHost.appearance = NSAppearance(named: .aqua)
        lineupHost.layoutSubtreeIfNeeded()
        let lineupSize = lineupHost.fittingSize
        lineupHost.frame = NSRect(origin: .zero, size: lineupSize)
        lineupHost.layoutSubtreeIfNeeded()
        let lineupBitmap = try XCTUnwrap(lineupHost.bitmapImageRepForCachingDisplay(in: lineupHost.bounds))
        lineupHost.cacheDisplay(in: lineupHost.bounds, to: lineupBitmap)
        let lineupPNG = try XCTUnwrap(lineupBitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(lineupPNG.count, 20_000)
        try lineupPNG.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-companion-lineup.png"),
            options: .atomic
        )
    }

    @MainActor
    func testAllCompanionsKeepCompactWidgetTextInsideStableFootprint() throws {
        let viewModel = try makeStressViewModel()
        let themeStore = ThemeStore()
        let languageStore = LanguageStore.shared
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-companion-widget-grid-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL)
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        let originalCompanion = UserDefaults.standard.object(forKey: "companionKind")
        let originalHistoryEnabled = UserDefaults.standard.object(forKey: "usageHistoryEnabled")
        let originalAnimationMode = UserDefaults.standard.object(forKey: "mimoAnimationMode")
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
            if let originalCompanion {
                UserDefaults.standard.set(originalCompanion, forKey: "companionKind")
            } else {
                UserDefaults.standard.removeObject(forKey: "companionKind")
            }
            if let originalHistoryEnabled {
                UserDefaults.standard.set(originalHistoryEnabled, forKey: "usageHistoryEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "usageHistoryEnabled")
            }
            if let originalAnimationMode {
                UserDefaults.standard.set(originalAnimationMode, forKey: "mimoAnimationMode")
            } else {
                UserDefaults.standard.removeObject(forKey: "mimoAnimationMode")
            }
            try? FileManager.default.removeItem(at: historyURL)
        }

        themeStore.current = .daangn
        languageStore.current = .ko
        let settingsByKind = CompanionKind.allCases.map { kind in
            let settings = AppSettings()
            settings.companionKind = kind
            settings.usageHistoryEnabled = false
            settings.mimoAnimationMode = .still
            settings.floatingWidgetVisible = false
            return settings
        }
        let columns = Array(repeating: GridItem(.fixed(224), spacing: 8), count: 3)
        let root = LazyVGrid(columns: columns, spacing: 8) {
            ForEach(settingsByKind.indices, id: \.self) { index in
                WidgetMimoCompanion()
                    .environmentObject(viewModel)
                    .environmentObject(historyStore)
                    .environmentObject(settingsByKind[index])
                    .environmentObject(themeStore)
                    .frame(width: 204)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(16)
        .background(Color(red: 0.92, green: 0.93, blue: 0.94))

        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertEqual(size.width, 720, accuracy: 2)
        XCTAssertLessThan(size.height, 310)
        XCTAssertGreaterThan(png.count, 25_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-companion-widget-grid.png"),
            options: .atomic
        )
    }

    @MainActor
    func testProviderBrandIconsAndCodexLabelsRender() throws {
        XCTAssertEqual(ProviderBrand.claude.compactLabel, "C")
        XCTAssertEqual(ProviderBrand.codex.compactLabel, "G")
        XCTAssertEqual(L10n.strings["openai_short"]?[.ko], "Codex")
        XCTAssertEqual(L10n.strings["openai_short"]?[.en], "Codex")
        XCTAssertEqual(L10n.strings["openai_usage"]?[.ko], "Codex 사용량")
        XCTAssertEqual(L10n.strings["openai_usage"]?[.en], "Codex Usage")

        let root = HStack(spacing: 20) {
            VStack(spacing: 6) {
                ProviderBrandIcon(provider: .claude, size: 64)
                Text("Claude")
            }
            VStack(spacing: 6) {
                ProviderBrandIcon(provider: .codex, size: 64)
                Text("Codex")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(20)
        .background(Color.white)

        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-provider-icons.png"),
            options: .atomic
        )
    }

    @MainActor
    func testMenuBarLabelRendersProviderIconsBesideUsage() throws {
        let viewModel = try makeStressViewModel()
        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
        }
        themeStore.current = .hybrid
        languageStore.current = .ko

        let root = MenuBarLabel()
            .environmentObject(viewModel)
            .environmentObject(themeStore)
            .environmentObject(languageStore)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(size.width, 70)
        XCTAssertLessThan(size.width, 150)
        XCTAssertLessThanOrEqual(size.height, 28)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 2_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-menu-label.png"),
            options: .atomic
        )
    }

    @MainActor
    func testMenuBarLabelKeepsCodexVisibleWhileItLoads() throws {
        let viewModel = UsageViewModel(autoStart: false)
        viewModel.state = .loaded(
            AccountSnapshot(
                organization: Organization(
                    uuid: "test",
                    name: "Test Account",
                    capabilities: ["claude_max"],
                    rateLimitTier: "max_20x"
                ),
                usage: UsageData(
                    fiveHour: UsageWindow(utilization: 1, resetsAt: Date().addingTimeInterval(3_600)),
                    sevenDay: UsageWindow(utilization: 8, resetsAt: Date().addingTimeInterval(300_000))
                )
            )
        )
        viewModel.openAIState = .loading

        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let root = MenuBarLabel()
            .environmentObject(viewModel)
            .environmentObject(themeStore)
            .environmentObject(languageStore)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(size.width, 65, "Codex icon and loading mark must remain visible")
        XCTAssertLessThanOrEqual(size.height, 28)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 2_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-menu-label-loading.png"),
            options: .atomic
        )
    }

    @MainActor
    func testAllThemesFitStressCaseAndRenderNonblank() throws {
        let viewModel = UsageViewModel(autoStart: false)
        viewModel.state = .loaded(
            AccountSnapshot(
                organization: Organization(
                    uuid: "test",
                    name: "Test Account",
                    capabilities: ["claude_max"],
                    rateLimitTier: "max_20x"
                ),
                usage: UsageData(
                    fiveHour: UsageWindow(utilization: 68, resetsAt: Date().addingTimeInterval(4_000)),
                    sevenDay: UsageWindow(utilization: 14, resetsAt: Date().addingTimeInterval(300_000)),
                    sevenDayFable: UsageWindow(utilization: 24, resetsAt: Date().addingTimeInterval(300_000))
                )
            )
        )
        viewModel.openAIState = .loaded(try stressOpenAIUsage())

        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-widget-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL)
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        let originalPetEnabled = appSettings.usagePetEnabled
        let originalLayout = appSettings.widgetLayoutMode
        let originalSparkVisibility = appSettings.showOpenAISparkLimits
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
            appSettings.usagePetEnabled = originalPetEnabled
            appSettings.widgetLayoutMode = originalLayout
            appSettings.showOpenAISparkLimits = originalSparkVisibility
            try? FileManager.default.removeItem(at: historyURL)
        }
        languageStore.current = .en
        appSettings.usagePetEnabled = true
        appSettings.widgetLayoutMode = .stacked
        appSettings.showOpenAISparkLimits = false

        for theme in ThemeKind.allCases {
            themeStore.current = theme
            let root = WidgetView()
                .environmentObject(viewModel)
                .environmentObject(themeStore)
                .environmentObject(languageStore)
                .environmentObject(appSettings)
                .environmentObject(historyStore)
            let host = NSHostingView(rootView: root)
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize

            XCTAssertGreaterThan(size.width, 0, "\(theme.rawValue) width")
            XCTAssertGreaterThan(size.height, 0, "\(theme.rawValue) height")
            XCTAssertLessThanOrEqual(size.width, 300, "\(theme.rawValue) should stay compact")
            XCTAssertLessThanOrEqual(size.height, 900, "\(theme.rawValue) should fit a laptop display")

            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                XCTFail("Could not create \(theme.rawValue) bitmap")
                continue
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 1_000, "\(theme.rawValue) render should not be blank")

            let url = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-\(theme.rawValue)-widget.png")
            try png.write(to: url, options: .atomic)
        }
    }

    @MainActor
    func testAllWidgetLayoutsRenderWithExpectedFootprints() throws {
        let viewModel = try makeStressViewModel()
        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-layout-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL)
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        let originalLayout = appSettings.widgetLayoutMode
        let originalPetEnabled = appSettings.usagePetEnabled
        let originalSparkVisibility = appSettings.showOpenAISparkLimits
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
            appSettings.widgetLayoutMode = originalLayout
            appSettings.usagePetEnabled = originalPetEnabled
            appSettings.showOpenAISparkLimits = originalSparkVisibility
            try? FileManager.default.removeItem(at: historyURL)
        }

        themeStore.current = .hybrid
        languageStore.current = .ko
        appSettings.usagePetEnabled = true
        appSettings.showOpenAISparkLimits = false

        appSettings.widgetLayoutMode = .stacked
        let stacked = try renderWidget(
            viewModel: viewModel,
            themeStore: themeStore,
            languageStore: languageStore,
            appSettings: appSettings,
            historyStore: historyStore,
            fileName: "ClaudeUsage-layout-stacked.png"
        )

        appSettings.widgetLayoutMode = .horizontal
        let horizontal = try renderWidget(
            viewModel: viewModel,
            themeStore: themeStore,
            languageStore: languageStore,
            appSettings: appSettings,
            historyStore: historyStore,
            fileName: "ClaudeUsage-layout-horizontal.png"
        )

        appSettings.widgetLayoutMode = .paged
        let paged = try renderWidget(
            viewModel: viewModel,
            themeStore: themeStore,
            languageStore: languageStore,
            appSettings: appSettings,
            historyStore: historyStore,
            fileName: "ClaudeUsage-layout-paged.png"
        )

        appSettings.widgetLayoutMode = .separate
        let claudeOnly = try renderWidget(
            provider: .claude,
            viewModel: viewModel,
            themeStore: themeStore,
            languageStore: languageStore,
            appSettings: appSettings,
            historyStore: historyStore,
            fileName: "ClaudeUsage-layout-claude-only.png"
        )
        let openAIOnly = try renderWidget(
            provider: .openAI,
            viewModel: viewModel,
            themeStore: themeStore,
            languageStore: languageStore,
            appSettings: appSettings,
            historyStore: historyStore,
            fileName: "ClaudeUsage-layout-openai-only.png"
        )

        XCTAssertEqual(stacked.width, 240, accuracy: 1)
        XCTAssertEqual(horizontal.width, 480, accuracy: 1)
        XCTAssertEqual(paged.width, 240, accuracy: 1)
        XCTAssertEqual(claudeOnly.width, 240, accuracy: 1)
        XCTAssertEqual(openAIOnly.width, 240, accuracy: 1)
        XCTAssertLessThan(horizontal.height, stacked.height)
        XCTAssertLessThan(paged.height, stacked.height)
        XCTAssertLessThan(claudeOnly.height, stacked.height)
        XCTAssertLessThan(openAIOnly.height, stacked.height)
    }

    @MainActor
    func testBalancedHorizontalWidgetUsesCodexSpaceAndStaysCompact() throws {
        let viewModel = UsageViewModel(autoStart: false)
        viewModel.state = .loaded(
            AccountSnapshot(
                organization: Organization(
                    uuid: "balanced",
                    name: "Balanced Account",
                    capabilities: ["claude_max"],
                    rateLimitTier: "max_20x"
                ),
                usage: UsageData(
                    fiveHour: UsageWindow(utilization: 30, resetsAt: Date().addingTimeInterval(3_600)),
                    sevenDay: UsageWindow(utilization: 14, resetsAt: Date().addingTimeInterval(240_000)),
                    sevenDayFable: UsageWindow(utilization: 25, resetsAt: Date().addingTimeInterval(240_000))
                )
            )
        )
        let openAIJSON = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 0,
              "reset_after_seconds": 18000,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 3,
              "reset_after_seconds": 600000,
              "limit_window_seconds": 604800
            }
          }
        }
        """
        let decodedOpenAI = try JSONDecoder().decode(OpenAIUsageData.self, from: Data(openAIJSON.utf8))
        let resetCredits = OpenAIRateLimitResetCredits(
            availableCount: 3,
            credits: (0..<3).map { index in
                OpenAIRateLimitResetCredit(
                    id: "balanced-credit-\(index)",
                    resetType: "codexRateLimits",
                    status: "available",
                    grantedAt: Date(),
                    expiresAt: Date().addingTimeInterval(TimeInterval(7 + index * 5) * 86_400),
                    title: "Full reset (Weekly + 5 hr)",
                    description: "One free reset"
                )
            }
        )
        viewModel.openAIState = .loaded(
            OpenAIUsageData(
                planType: decodedOpenAI.planType,
                rateLimit: decodedOpenAI.rateLimit,
                codeReviewRateLimit: decodedOpenAI.codeReviewRateLimit,
                additionalRateLimits: decodedOpenAI.additionalRateLimits,
                tokenActivity: decodedOpenAI.tokenActivity,
                rateLimitResetCredits: resetCredits
            )
        )
        viewModel.claudeLocalTokenUsage = ClaudeLocalTokenUsage(todayTokens: 12_400, updatedAt: Date())

        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-balanced-horizontal-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL)
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        let originalLayout = appSettings.widgetLayoutMode
        let originalPetEnabled = appSettings.usagePetEnabled
        let originalHistoryEnabled = appSettings.usageHistoryEnabled
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
            appSettings.widgetLayoutMode = originalLayout
            appSettings.usagePetEnabled = originalPetEnabled
            appSettings.usageHistoryEnabled = originalHistoryEnabled
            try? FileManager.default.removeItem(at: historyURL)
        }

        themeStore.current = .daangn
        languageStore.current = .ko
        appSettings.widgetLayoutMode = .horizontal
        appSettings.usagePetEnabled = true
        appSettings.usageHistoryEnabled = false

        let size = try renderWidget(
            viewModel: viewModel,
            themeStore: themeStore,
            languageStore: languageStore,
            appSettings: appSettings,
            historyStore: historyStore,
            fileName: "ClaudeUsage-layout-horizontal-balanced.png"
        )

        XCTAssertEqual(size.width, 480, accuracy: 1)
        XCTAssertGreaterThan(size.height, 240)
        XCTAssertLessThan(size.height, 350)
    }

    @MainActor
    func testLiveLayoutSwitchesKeepStableWidgetFootprints() throws {
        let viewModel = try makeStressViewModel()
        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-layout-switch-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL)
        let originalLayout = appSettings.widgetLayoutMode
        let originalPetEnabled = appSettings.usagePetEnabled
        defer {
            appSettings.widgetLayoutMode = originalLayout
            appSettings.usagePetEnabled = originalPetEnabled
            try? FileManager.default.removeItem(at: historyURL)
        }

        appSettings.usagePetEnabled = true
        appSettings.widgetLayoutMode = .horizontal
        let root = WidgetView()
            .environmentObject(viewModel)
            .environmentObject(themeStore)
            .environmentObject(languageStore)
            .environmentObject(appSettings)
            .environmentObject(historyStore)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)

        let sequence: [(WidgetLayoutMode, CGFloat)] = [
            (.horizontal, 480),
            (.stacked, 240),
            (.paged, 240),
            (.horizontal, 480),
            (.stacked, 240)
        ]
        for (index, item) in sequence.enumerated() {
            appSettings.widgetLayoutMode = item.0
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()

            XCTAssertEqual(size.width, item.1, accuracy: 1)
            XCTAssertGreaterThan(size.height, 180)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 5_000)
            try png.write(
                to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-layout-switch-\(index).png"),
                options: .atomic
            )
        }
    }

    @MainActor
    func testHorizontalWidgetReturnsToDaangnIntrinsicSizeAfterThemeSwitches() throws {
        let viewModel = try makeStressViewModel()
        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-theme-switch-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL)
        let originalTheme = themeStore.current
        let originalLayout = appSettings.widgetLayoutMode
        let originalPetEnabled = appSettings.usagePetEnabled
        defer {
            themeStore.current = originalTheme
            appSettings.widgetLayoutMode = originalLayout
            appSettings.usagePetEnabled = originalPetEnabled
            try? FileManager.default.removeItem(at: historyURL)
        }

        appSettings.widgetLayoutMode = .horizontal
        appSettings.usagePetEnabled = true
        appSettings.floatingWidgetVisible = false
        let root = WidgetView()
            .environmentObject(viewModel)
            .environmentObject(themeStore)
            .environmentObject(languageStore)
            .environmentObject(appSettings)
            .environmentObject(historyStore)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)

        func fittingSize(for theme: ThemeKind) -> CGSize {
            themeStore.current = theme
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.invalidateIntrinsicContentSize()
            host.layoutSubtreeIfNeeded()
            return host.fittingSize
        }

        let firstDaangn = fittingSize(for: .daangn)
        _ = fittingSize(for: .toss)
        _ = fittingSize(for: .hybrid)
        let returnedDaangn = fittingSize(for: .daangn)

        XCTAssertEqual(firstDaangn.width, 480, accuracy: 1)
        XCTAssertEqual(returnedDaangn.width, firstDaangn.width, accuracy: 1)
        XCTAssertEqual(returnedDaangn.height, firstDaangn.height, accuracy: 1)
    }

    @MainActor
    func testUsageHistoryDashboardRendersModelSeries() throws {
        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-dashboard-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL, minimumSampleInterval: 0)
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        let originalHistoryEnabled = appSettings.usageHistoryEnabled
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
            appSettings.usageHistoryEnabled = originalHistoryEnabled
            try? FileManager.default.removeItem(at: historyURL)
        }

        themeStore.current = .daangn
        languageStore.current = .ko
        appSettings.usageHistoryEnabled = true
        let now = Date()
        for index in 0..<8 {
            historyStore.record(
                UsageHistorySnapshot(
                    claudeFiveHour: Double(20 + index * 4),
                    claudeWeekly: Double(12 + index),
                    claudeModelMaximum: Double(24 + index * 3),
                    openAIFiveHour: Double(10 + index * 3),
                    openAIWeekly: Double(7 + index),
                    openAIModelMaximum: nil,
                    claudeTodayTokens: Int64(index * 10_000),
                    openAITodayTokens: nil,
                    claudeModelCounters: [
                        UsageHistoryCounter(
                            id: "seven_day_fable",
                            label: "Claude Fable",
                            utilization: Double(24 + index * 3)
                        )
                    ]
                ),
                at: now.addingTimeInterval(TimeInterval(index - 7) * 600),
                force: true
            )
        }

        let root = UsageHistoryDashboardView()
            .environmentObject(historyStore)
            .environmentObject(appSettings)
            .environmentObject(themeStore)
            .environmentObject(languageStore)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 560)
        host.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-history-dashboard.png"),
            options: .atomic
        )
    }

    @MainActor
    func testMimoAnimationChangesPoseWithoutChangingFootprint() throws {
        let root = HStack(spacing: 16) {
            MimoAvatar(mood: .refreshed, pressure: 18, theme: .hybrid, size: 96, animationTime: 0)
            MimoAvatar(mood: .refreshed, pressure: 18, theme: .hybrid, size: 96, animationTime: 0.46)
            MimoAvatar(mood: .refreshed, pressure: 18, theme: .hybrid, size: 96, animationTime: 1.38)
        }
        .padding(20)
        .background(Color.white)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(size.width, 360, accuracy: 1)
        XCTAssertEqual(size.height, 136, accuracy: 1)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 8_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-mimo-animation-frames.png"),
            options: .atomic
        )
    }

    @MainActor
    func testFocusedMimoLaptopStaysInsideTheAvatarFootprint() throws {
        let root = HStack(spacing: 16) {
            MimoAvatar(mood: .focused, pressure: 58, theme: .hybrid, size: 96, animationTime: 0)
            MimoAvatar(mood: .focused, pressure: 58, theme: .hybrid, size: 96, animationTime: 0.22)
            MimoAvatar(mood: .focused, pressure: 58, theme: .hybrid, size: 96, animationTime: 0.44)
        }
        .padding(20)
        .background(Color.white)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(size.width, 360, accuracy: 1)
        XCTAssertEqual(size.height, 136, accuracy: 1)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 8_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-mimo-laptop-frames.png"),
            options: .atomic
        )
    }

    @MainActor
    func testSparkCountersCanBeHiddenWithoutChangingFetchedUsage() throws {
        let viewModel = UsageViewModel(autoStart: false)
        viewModel.openAIState = .loaded(try stressOpenAIUsage())

        let allMetrics = viewModel.openAIDisplayMetrics(includingSpark: true)
        let hiddenMetrics = viewModel.openAIDisplayMetrics(includingSpark: false)
        let sparkMetrics = allMetrics.filter { $0.title.lowercased().contains("codex-spark") }
        let pressureWithSpark = viewModel.historySnapshot(includingSpark: true).pressure
        let pressureWithoutSpark = viewModel.historySnapshot(includingSpark: false).pressure

        XCTAssertEqual(sparkMetrics.count, 2)
        XCTAssertEqual(allMetrics.count, hiddenMetrics.count + 2)
        XCTAssertFalse(hiddenMetrics.contains { $0.title.lowercased().contains("codex-spark") })
        XCTAssertEqual(pressureWithSpark, 87)
        XCTAssertEqual(pressureWithoutSpark, 31)
    }

    @MainActor
    func testSettingsShowsLayoutProviderAndSparkControls() throws {
        let themeStore = ThemeStore()
        let appSettings = AppSettings()
        let originalTheme = themeStore.current
        let originalLayout = appSettings.widgetLayoutMode
        defer {
            themeStore.current = originalTheme
            appSettings.widgetLayoutMode = originalLayout
        }

        themeStore.current = .hybrid
        appSettings.widgetLayoutMode = .separate

        let root = WidgetSettingsRow()
            .environmentObject(themeStore)
            .environmentObject(appSettings)
            .frame(width: 380)
            .padding(20)
            .background(themeStore.current.tokens.bg)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(size.width, 420, accuracy: 1)
        XCTAssertGreaterThan(size.height, 250)
        XCTAssertLessThan(size.height, 500)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-layout-settings.png"),
            options: .atomic
        )
    }

    @MainActor
    func testCompanionSettingsShowsSensitivityAnimationAndHistoryControls() throws {
        let viewModel = try makeStressViewModel()
        let appDelegate = AppDelegate()
        let themeStore = ThemeStore()
        let appSettings = AppSettings()
        let historyURL = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-companion-settings-history.json")
        let historyStore = UsageHistoryStore(fileURL: historyURL)
        let originalTheme = themeStore.current
        let originalCompanion = appSettings.companionKind
        let originalSensitivity = appSettings.mimoSensitivity
        let originalAnimation = appSettings.mimoAnimationMode
        defer {
            themeStore.current = originalTheme
            appSettings.companionKind = originalCompanion
            appSettings.mimoSensitivity = originalSensitivity
            appSettings.mimoAnimationMode = originalAnimation
            try? FileManager.default.removeItem(at: historyURL)
        }

        themeStore.current = .daangn
        appSettings.companionKind = .mimo
        appSettings.mimoSensitivity = .balanced
        appSettings.mimoAnimationMode = .still

        let root = CompanionSettingsRow()
            .environmentObject(viewModel)
            .environmentObject(appDelegate)
            .environmentObject(themeStore)
            .environmentObject(appSettings)
            .environmentObject(historyStore)
            .frame(width: 380)
            .padding(20)
            .background(themeStore.current.tokens.bg)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(size.width, 420, accuracy: 1)
        XCTAssertGreaterThan(size.height, 260)
        XCTAssertLessThan(size.height, 550)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 8_000)
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-companion-settings.png"),
            options: .atomic
        )
    }

    @MainActor
    private func renderWidget(
        provider: WidgetProvider? = nil,
        viewModel: UsageViewModel,
        themeStore: ThemeStore,
        languageStore: LanguageStore,
        appSettings: AppSettings,
        historyStore: UsageHistoryStore,
        fileName: String
    ) throws -> CGSize {
        let panelID = provider?.rawValue ?? WidgetPanelKind.combined.rawValue
        let root = WidgetView(panelID: panelID, provider: provider)
            .environmentObject(viewModel)
            .environmentObject(themeStore)
            .environmentObject(languageStore)
            .environmentObject(appSettings)
            .environmentObject(historyStore)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1_000)
        try png.write(to: URL(fileURLWithPath: "/private/tmp/\(fileName)"), options: .atomic)
        return size
    }

    @MainActor
    private func makeStressViewModel() throws -> UsageViewModel {
        let viewModel = UsageViewModel(autoStart: false)
        viewModel.state = .loaded(
            AccountSnapshot(
                organization: Organization(
                    uuid: "test",
                    name: "Test Account",
                    capabilities: ["claude_max"],
                    rateLimitTier: "max_20x"
                ),
                usage: UsageData(
                    fiveHour: UsageWindow(utilization: 68, resetsAt: Date().addingTimeInterval(4_000)),
                    sevenDay: UsageWindow(utilization: 14, resetsAt: Date().addingTimeInterval(300_000)),
                    sevenDayFable: UsageWindow(utilization: 24, resetsAt: Date().addingTimeInterval(300_000))
                )
            )
        )
        viewModel.openAIState = .loaded(try stressOpenAIUsage())
        return viewModel
    }

    private func stressOpenAIUsage() throws -> OpenAIUsageData {
        let namedModels = [
            ("GPT-5.6-Sol", "gpt_5_6_sol", 24),
            ("GPT-5.6-Terra", "gpt_5_6_terra", 24),
            ("GPT-5.6-Luna", "gpt_5_6_luna", 24),
            ("GPT-5.3-Codex-Spark", "gpt_5_3_codex_spark", 87)
        ]
        let models = namedModels.map { name, feature, usedPercent in
            """
            {
              "limit_name": "\(name)",
              "metered_feature": "\(feature)",
              "rate_limit": {
                "primary_window": {
                  "used_percent": \(usedPercent),
                  "reset_after_seconds": 4000,
                  "limit_window_seconds": 18000
                },
                "secondary_window": {
                  "used_percent": 11,
                  "reset_after_seconds": 300000,
                  "limit_window_seconds": 604800
                }
              }
            }
            """
        }.joined(separator: ",")

        let json = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 20,
              "reset_after_seconds": 4000,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 31,
              "reset_after_seconds": 300000,
              "limit_window_seconds": 604800
            }
          },
          "additional_rate_limits": [\(models)]
        }
        """
        return try JSONDecoder().decode(OpenAIUsageData.self, from: Data(json.utf8))
    }
}
