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
                    Text("Claude Usage")
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

                    SectionHeader(title: "section_language".l)
                    LanguagePickerRow()
                        .padding(.horizontal, 20)

                    SectionHeader(title: "section_account".l)
                    AccountRow()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.visible)  // 스크롤바 항상 표시
        }
        .frame(width: 420, height: 520)
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

private struct WidgetSettingsRow: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        let t = theme.current.tokens
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(t.bgRing).frame(width: 36, height: 36)
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
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
        .background(t.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

private struct AccountRow: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        let t = theme.current.tokens
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(t.bgRing).frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.organizationName ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    PlanBadge(plan: vm.plan, theme: theme.current)
                        .scaleEffect(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
            Button {
                vm.logout()
            } label: {
                Text("로그아웃")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.textTertiary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(t.divider)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(t.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
