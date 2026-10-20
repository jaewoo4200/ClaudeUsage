import SwiftUI

struct BrowserSessionLoginView: View {
    let onCookies: (String) -> Void
    let onCancel: () -> Void
    @State private var session = ""
    @State private var errorMessage: String?
    @State private var isValidating = false
    @State private var validation: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("login_browser_session".l).font(.title3.bold())
            Text("login_session_privacy".l)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { NSWorkspace.shared.open(BrowserSession.loginURL) } label: {
                Label("login_browser_open".l, systemImage: "arrow.up.forward.app")
            }
            SecureField("claude.ai sessionKey", text: $session)
                .textFieldStyle(.roundedBorder)
                .disabled(isValidating)
                .onSubmit(connect)
            DisclosureGroup("login_session_help".l) {
                Text("login_session_steps".l)
                    .font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isValidating { ProgressView().controlSize(.small) }
                Spacer()
                Button("login_cancel".l, action: onCancel).keyboardShortcut(.cancelAction)
                Button("login_session_connect".l, action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isValidating || session.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440, height: 460, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            validation?.cancel()
            session = ""
        }
    }

    private func connect() {
        guard !isValidating else { return }
        guard let cookie = BrowserSession.cookie(from: session) else {
            errorMessage = "login_session_invalid".l
            return
        }
        isValidating = true
        errorMessage = nil
        validation = Task { @MainActor in
            defer { isValidating = false }
            do {
                _ = try await UsageService.fetchSnapshot(cookie: cookie)
                guard !Task.isCancelled else { return }
                session = ""
                onCookies(cookie)
            } catch {
                guard !Task.isCancelled else { return }
                // Never surface a URL/request/error containing a pasted secret.
                errorMessage = "login_session_rejected".l
            }
        }
    }
}
