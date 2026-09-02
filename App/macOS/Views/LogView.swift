import PocketTmuxAgent
import SwiftUI

/// Agent log window: the last 500 `LogEntry.line`s in mono, Clear, Copy all.
struct LogView: View {
    @ObservedObject var controller: AgentController
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(controller.logEntries) { entry in
                            Text(entry.line)
                                .font(MacTheme.mono(11))
                                .foregroundStyle(color(entry.level))
                                .textSelection(.enabled)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: controller.logEntries.count, initial: true) {
                    if let last = controller.logEntries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                Text(verbatim: "\(controller.logEntries.count) lines")
                    .font(MacTheme.mono(11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { controller.clearLog() }
                CopyButton(id: "log", text: controller.logText, copied: $copied)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 480, minHeight: 240)
    }

    private func color(_ level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .primary
        case .warning: return MacTheme.yamabuki
        case .error: return MacTheme.shu
        }
    }
}
