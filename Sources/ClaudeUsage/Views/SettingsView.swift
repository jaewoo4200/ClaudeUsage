import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var language: LanguageStore

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        let _ = language.current  // reactivity hint
        let t = theme.current.tokens
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(spacing: 12) {
                AppIconDot(theme: theme.current, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude + Codex Usage")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(t.textPrimary)
                    Text("v\(appVersion) · \("settings_title".l)")
                        .font(.system(size: 11))
                        .foregroundStyle(t.textTertiary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            // 테마 섹션
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "section_theme".l)
                    VStack(spacing: 8) {
                        ForEach(ThemeKind.allCases) { kind in
                            ThemeRow(kind: kind, isSelected: theme.current == kind) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    theme.current = kind
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    SectionHeader(title: "section_appearance".l)
                    AppearancePickerRow()
                        .padding(.horizontal, 20)

                    SectionHeader(title: "section_widget".l)
                    WidgetSettingsRow()
                        .padding(.horizontal, 20)

                    SectionHeader(title: "section_companion".l)
                    CompanionSettingsRow()
                        .padding(.horizontal, 20)

                    SectionHeader(title: "section_language".l)
                    LanguagePickerRow()
                        .padding(.horizontal, 20)

                    SectionHeader(title: "section_account".l)
                    VStack(spacing: 8) {
                        ClaudeAccountRow()
                        OpenAIAccountRow()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.visible)  // 스크롤바 항상 표시
        }
        .frame(width: 420, height: 600)
        .id("\(language.current.rawValue)-\(theme.current.rawValue)")  // 트리 재생성
        .background(t.bg)
    }
}

private struct SectionHeader: View {
    let title: String
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(theme.current.tokens.textTertiary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

private struct ThemeRow: View {
    let kind: ThemeKind
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let active = theme.current.tokens
        let preview = kind.tokens
        Button(action: action) {
            HStack(spacing: 14) {
                // 좌측 미니 프리뷰
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(preview.bgSecondary)
                        .frame(width: 56, height: 40)
                    VStack(spacing: 4) {
                        switch kind {
                        case .daangn:
                            HStack(spacing: 4) {
                                Circle()
                                    .trim(from: 0, to: 0.4)
                                    .stroke(preview.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 14, height: 14)
                                Text("38%")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(preview.textPrimary)
                            }
                        case .toss:
                            VStack(alignment: .leading, spacing: 2) {
                                Text("38")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(preview.textPrimary)
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(preview.accent)
                                    .frame(width: 26, height: 3)
                            }
                        case .hybrid:
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 2) {
                                    Text("38")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(preview.textPrimary)
                                    Text("MAX")
                                        .font(.system(size: 6, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 2)
                                        .padding(.vertical, 0.5)
                                        .background(preview.textPrimary)
                                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                                }
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(LinearGradient(colors: [preview.accent, preview.accentSecondary], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 30, height: 3)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active.textPrimary)
                    Text(kind.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(active.textTertiary)
                }
                Spacer()
                if isSelected {
                    ZStack {
                        Circle().fill(active.accent).frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                } else {
                    Circle()
                        .stroke(active.divider, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(12)
            .background(active.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? active.accent : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct WidgetSettingsRow: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let t = theme.current.tokens
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                settingIcon("rectangle.3.group")
                VStack(alignment: .leading, spacing: 2) {
                    Text("widget_layout".l)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.textPrimary)
                    Text(settings.widgetLayoutMode.descriptionText)
                        .font(.system(size: 11))
                        .foregroundStyle(t.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(12)

            Picker("widget_layout".l, selection: $settings.widgetLayoutMode) {
                ForEach(WidgetLayoutMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemSymbol)
                        .tag(mode)
                        .help(mode.descriptionText)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            if settings.widgetLayoutMode == .separate {
                Divider().background(t.divider)
                VStack(alignment: .leading, spacing: 8) {
                    Text("separate_widgets".l)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(t.textTertiary)
                    HStack(spacing: 8) {
                        separateProviderToggle(
                            title: "show_claude_widget".l,
                            provider: .claude,
                            isOn: $settings.separateClaudeWidgetEnabled,
                            isLastEnabled: settings.separateClaudeWidgetEnabled
                                && !settings.separateOpenAIWidgetEnabled
                        )
                        separateProviderToggle(
                            title: "show_openai_widget".l,
                            provider: .codex,
                            isOn: $settings.separateOpenAIWidgetEnabled,
                            isLastEnabled: settings.separateOpenAIWidgetEnabled
                                && !settings.separateClaudeWidgetEnabled
                        )
                    }
                }
                .padding(10)
            }

            Divider().background(t.divider)

            HStack(spacing: 12) {
                settingIcon("rectangle.on.rectangle")
                VStack(alignment: .leading, spacing: 2) {
                    Text("always_on_top".l)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.textPrimary)
                    Text(settings.widgetAlwaysOnTop
                         ? "always_on_top_on_desc".l
                         : "always_on_top_off_desc".l)
                        .font(.system(size: 11))
                        .foregroundStyle(t.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.widgetAlwaysOnTop)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(t.accent)
                    .labelsHidden()
            }
            .padding(12)

            Divider().background(t.divider)

            HStack(spacing: 12) {
                settingIcon("bolt.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("show_spark_limits".l)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.textPrimary)
                        .lineLimit(2)
                    Text("show_spark_limits_desc".l)
                        .font(.system(size: 11))
                        .foregroundStyle(t.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
                Toggle("", isOn: $settings.showOpenAISparkLimits)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(t.accent)
                    .labelsHidden()
            }
            .padding(12)
        }
        .background(t.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: settings.widgetLayoutMode)
    }

    private func settingIcon(_ systemName: String) -> some View {
        ZStack {
            Circle().fill(theme.current.tokens.bgRing).frame(width: 36, height: 36)
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.current.tokens.accent)
        }
    }

    private func separateProviderToggle(
        title: String,
        provider: ProviderBrand,
        isOn: Binding<Bool>,
        isLastEnabled: Bool
    ) -> some View {
        HStack(spacing: 6) {
            ProviderBrandIcon(provider: provider, size: 18)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.current.tokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(theme.current.tokens.accent)
                .labelsHidden()
                .disabled(isLastEnabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(theme.current.tokens.bg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct CompanionSettingsRow: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var appDelegate: AppDelegate
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var history: UsageHistoryStore

    var body: some View {
        let tokens = theme.current.tokens
        let trend = settings.usageHistoryEnabled ? history.trend() : .empty
        let snapshot = vm.historySnapshot(includingSpark: settings.showOpenAISparkLimits)
        let mood = PetMood.resolve(
            snapshot: snapshot,
            trend: trend,
            sensitivity: settings.mimoSensitivity
        )

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MimoAvatar(
                    mood: mood,
                    pressure: snapshot.pressure ?? 0,
                    theme: theme.current,
                    size: 40,
                    kind: settings.companionKind,
                    animationMode: settings.mimoAnimationMode
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.companionKind.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.textPrimary)
                    Text("pet_enabled_desc".l)
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.usagePetEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(tokens.accent)
                    .labelsHidden()
            }
            .padding(12)

            Divider().background(tokens.divider)

            companionSelector(mood: mood, pressure: snapshot.pressure ?? 0)

            Divider().background(tokens.divider)

            companionPickerRow(
                icon: "gauge",
                title: "mimo_sensitivity".l,
                detail: String(
                    format: "mimo_sensitivity_threshold_format".l,
                    settings.mimoSensitivity.focusedPressure,
                    settings.mimoSensitivity.focusedBurnRate
                )
            ) {
                Picker("mimo_sensitivity".l, selection: $settings.mimoSensitivity) {
                    ForEach(MimoSensitivity.allCases) { sensitivity in
                        Text(sensitivity.displayName).tag(sensitivity)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 176)
            }

            Divider().background(tokens.divider)

            companionPickerRow(
                icon: "figure.run",
                title: "mimo_animation".l,
                detail: "mimo_animation_desc".l
            ) {
                Picker("mimo_animation".l, selection: $settings.mimoAnimationMode) {
                    ForEach(MimoAnimationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 176)
            }

            Divider().background(tokens.divider)

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tokens.bgRing).frame(width: 36, height: 36)
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("usage_history".l)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.textPrimary)
                    Text("usage_history_local_desc".l)
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.textTertiary)
                }
                Spacer()
                Button {
                    appDelegate.openUsageHistory(viewModel: vm)
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tokens.textTertiary)
                }
                .buttonStyle(.plain)
                .help("open_usage_history".l)

                Button {
                    history.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(history.hasSamples ? tokens.textTertiary : tokens.divider)
                }
                .buttonStyle(.plain)
                .disabled(!history.hasSamples)
                .help("clear_usage_history".l)

                Toggle("", isOn: Binding(
                    get: { settings.usageHistoryEnabled },
                    set: { enabled in
                        settings.usageHistoryEnabled = enabled
                        if enabled { vm.refreshNow() }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(tokens.accent)
                .labelsHidden()
            }
            .padding(12)
        }
        .background(tokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func companionSelector(mood: PetMood, pressure: Double) -> some View {
        let tokens = theme.current.tokens
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(tokens.bgRing).frame(width: 36, height: 36)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("companion_character".l)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.textPrimary)
                    Text("companion_character_desc".l)
                        .font(.system(size: 10))
                        .foregroundStyle(tokens.textTertiary)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(CompanionKind.allCases) { kind in
                    Button {
                        settings.companionKind = kind
                    } label: {
                        HStack(spacing: 6) {
                            MimoAvatar(
                                mood: mood,
                                pressure: pressure,
                                theme: theme.current,
                                size: 30,
                                animationTime: 0,
                                kind: kind,
                                animationMode: .still
                            )
                            Text(kind.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tokens.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            settings.companionKind == kind
                                ? tokens.accent.opacity(0.12)
                                : tokens.bg
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    settings.companionKind == kind ? tokens.accent : tokens.border,
                                    lineWidth: settings.companionKind == kind ? 1.5 : 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(kind.descriptionText)
                }
            }

            Text(settings.companionKind.descriptionText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tokens.textTertiary)
                .lineLimit(2)
        }
        .padding(12)
    }

    private func companionPickerRow<Control: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        let tokens = theme.current.tokens
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(tokens.bgRing).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            control()
        }
        .padding(12)
    }
}

private struct AppearancePickerRow: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        let t = theme.current.tokens
        HStack(spacing: 8) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.appearance = mode
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.systemSymbol)
                            .font(.system(size: 14, weight: .bold))
                        Text(mode.displayName)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(settings.appearance == mode ? Color.white : t.textPrimary)
                    .background(settings.appearance == mode ? t.accent : t.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LanguagePickerRow: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var language: LanguageStore
    var body: some View {
        let t = theme.current.tokens
        HStack(spacing: 8) {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        language.current = lang
                    }
                } label: {
                    HStack(spacing: 6) {
                        if language.current == lang {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(lang.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(language.current == lang ? .white : t.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(language.current == lang ? t.accent : t.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ClaudeAccountRow: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        let t = theme.current.tokens
        HStack(spacing: 12) {
            ClaudeProviderIcon(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.organizationName ?? "Claude")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.textPrimary)
                    .lineLimit(1)
                if vm.state.isLoaded {
                    PlanBadge(plan: vm.plan, theme: theme.current)
                        .scaleEffect(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("login_required".l)
                        .font(.system(size: 11))
                        .foregroundStyle(t.textTertiary)
                }
            }
            Spacer()
            if vm.state.isLoaded {
                Button {
                    vm.logout()
                } label: {
                    Text("logout".l)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(t.divider)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(t.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OpenAIAccountRow: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        HStack(spacing: 12) {
            CodexProviderIcon(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.textPrimary)
                    .lineLimit(1)
                if vm.openAIState.isLoaded {
                    TextPlanBadge(
                        displayName: vm.openAIPlanDisplayName,
                        compactName: vm.openAIPlanCompactName,
                        theme: theme.current
                    )
                    .scaleEffect(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(openAIStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.textTertiary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(action: openUsagePage) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
                    .padding(7)
                    .background(tokens.divider)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("open_usage_page".l)
        }
        .padding(12)
        .background(tokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var openAIStatus: String {
        switch vm.openAIState {
        case .loaded: return "connected_automatically".l
        case .loading: return "loading".l
        case .unavailable: return "openai_not_connected".l
        case .error(let message): return message
        }
    }

    private func openUsagePage() {
        guard let url = URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage") else { return }
        NSWorkspace.shared.open(url)
    }
}
