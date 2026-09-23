import PocketTmuxAgent
import SwiftUI

/// Agent log window. The transcript is intentionally monospaced; navigation and
/// actions remain standard macOS window chrome.
struct LogView: View {
    @ObservedObject var controller: AgentController
    @State private var copied: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(controller.logEntries) { entry in
                        Text(entry.line)
                            .font(.body.monospaced())
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
        .navigationTitle("Agent Log")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Clear") { controller.clearLog() }
                CopyButton(id: "log", text: controller.logText, copied: $copied)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
        .frame(minWidth: 480, minHeight: 240)
    }

    private func color(_ level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
