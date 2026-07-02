import Foundation
import SwiftUI
import Combine

struct UsageDisplayMetric: Identifiable, Equatable {
    let id: String
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let isWeekly: Bool
}

@MainActor
final class UsageViewModel: ObservableObject {
    enum State: Equatable {
        case needsLogin
        case loading
        case loaded(AccountSnapshot)
        case error(String)

        var isLoaded: Bool {
            if case .loaded = self { return true }
            return false
        }
    }

    @Published var state: State = .loading
    @Published var lastUpdated: Date?
    @Published var isRefreshing: Bool = false

    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    init() {
        bootstrap()
    }

    var snapshot: AccountSnapshot? {
        if case .loaded(let s) = state { return s }
        return nil
    }
    var fiveHourUtilization: Double { snapshot?.usage.fiveHour?.utilization ?? 0 }
    var sevenDayUtilization: Double { snapshot?.usage.sevenDay?.utilization ?? 0 }
    var fiveHourResetsAt: Date? { snapshot?.usage.fiveHour?.resetsAt }
    var sevenDayResetsAt: Date? { snapshot?.usage.sevenDay?.resetsAt }

    // Claude Design (Anthropic 내부 코드네임 = omelette)
    var claudeDesignUtilization: Double { snapshot?.usage.sevenDayOmelette?.utilization ?? 0 }
    var claudeDesignResetsAt: Date? { snapshot?.usage.sevenDayOmelette?.resetsAt }
    var hasClaudeDesign: Bool { snapshot?.usage.sevenDayOmelette != nil }

    // Claude Fable: new model-specific usage counter from claude.ai.
    var claudeFableUtilization: Double { snapshot?.usage.sevenDayFable?.utilization ?? 0 }
    var claudeFableResetsAt: Date? { snapshot?.usage.sevenDayFable?.resetsAt }
    var hasClaudeFable: Bool { snapshot?.usage.sevenDayFable != nil }

    var displayMetrics: [UsageDisplayMetric] {
        guard let usage = snapshot?.usage else { return [] }
        var metrics: [UsageDisplayMetric] = [
            UsageDisplayMetric(
                id: "five_hour",
                title: "five_hour".l,
                utilization: usage.fiveHour?.utilization ?? 0,
                resetsAt: usage.fiveHour?.resetsAt,
                isWeekly: false
            ),
            UsageDisplayMetric(
                id: "seven_day",
                title: "seven_day".l,
                utilization: usage.sevenDay?.utilization ?? 0,
                resetsAt: usage.sevenDay?.resetsAt,
                isWeekly: true
            )
        ]

        if let claudeDesign = usage.sevenDayOmelette {
            metrics.append(
                UsageDisplayMetric(
                    id: "seven_day_omelette",
                    title: "claude_design".l,
                    utilization: claudeDesign.utilization,
                    resetsAt: claudeDesign.resetsAt,
                    isWeekly: true
                )
            )
        }

        if let claudeFable = usage.sevenDayFable {
            metrics.append(
                UsageDisplayMetric(
                    id: "seven_day_fable",
                    title: "claude_fable".l,
                    utilization: claudeFable.utilization,
                    resetsAt: claudeFable.resetsAt,
                    isWeekly: true
                )
            )
        }

        let dynamicMetrics = usage.additionalSevenDayWindows
            .sorted { $0.key < $1.key }
            .map { entry in
                UsageDisplayMetric(
                    id: entry.key,
                    title: dynamicSevenDayTitle(for: entry.key),
                    utilization: entry.value.utilization,
                    resetsAt: entry.value.resetsAt,
                    isWeekly: true
                )
            }
        metrics.append(contentsOf: dynamicMetrics)
        return metrics
    }

    var plan: Plan { snapshot?.organization.plan ?? .unknown }
    var organizationName: String? { snapshot?.organization.name }

    func bootstrap() {
        if CookieStore.load() == nil {
            state = .needsLogin
            return
        }
        startAutoRefresh()
    }

    func onLoggedIn(cookie: String) {
        CookieStore.save(cookie)
        state = .loading
        startAutoRefresh()
    }

    func logout() {
        CookieStore.clear()
        timerTask?.cancel()
        refreshTask?.cancel()
        state = .needsLogin
        lastUpdated = nil
    }

    func refreshNow() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.fetch()
        }
    }

    private func startAutoRefresh() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            await self?.fetch()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                if Task.isCancelled { break }
                await self?.fetch()
            }
        }
    }

    private func fetch() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snapshot = try await UsageService.fetchSnapshot()
            state = .loaded(snapshot)
            lastUpdated = Date()
        } catch UsageError.noCookie {
            state = .needsLogin
        } catch UsageError.authExpired {
            state = .needsLogin
            CookieStore.clear()
        } catch let e as UsageError {
            if case .loaded = state {
                // 잠시 실패 — 마지막 데이터 유지
            } else {
                state = .error(describe(e))
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func describe(_ e: UsageError) -> String {
        switch e {
        case .noCookie: return "no_cookie".l
        case .authExpired: return "session_expired".l
        case .network(let m): return "network_error_prefix".l + m
        case .decode: return "decode_failed".l
        }
    }

    private func dynamicSevenDayTitle(for key: String) -> String {
        let normalized = key.lowercased()
        if normalized.contains("fable") { return "claude_fable".l }
        if normalized.contains("omelette") { return "claude_design".l }

        let rawName = normalized
            .replacingOccurrences(of: "seven_day_", with: "")
            .replacingOccurrences(of: "_usage", with: "")
        let words = rawName
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
        return words.isEmpty ? "seven_day".l : words.joined(separator: " ")
    }
}
