import SwiftUI
import PocketTmuxKit

/// Horizontal strip of `index:name` chips for the attached session's windows,
/// plus a trailing `+`. Active chip is filled shu; tap selects, long-press
/// offers rename/kill.
struct WindowStrip: View {
    let windows: [WindowInfo]
    let onSelect: (WindowInfo) -> Void
    let onCreate: () -> Void
    let onRename: (WindowInfo) -> Void
    let onKill: (WindowInfo) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(windows) { w in
                        chip(w)
                            .id(w.id)
                            .contextMenu {
                                Button { onRename(w) } label: { Label(L.renameWindow, systemImage: "pencil") }
                                Button(role: .destructive) { onKill(w) } label: { Label(L.killWindow, systemImage: "xmark") }
                            }
                    }
                    Button(action: onCreate) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 28, height: 22)
                            .background(Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.newWindow)
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 28)
            .background(Theme.surface)
            .onChange(of: windows.first { $0.active }?.id) { id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private func chip(_ w: WindowInfo) -> some View {
        Button { onSelect(w) } label: {
            Text("\(w.index):\(w.name)")
                .font(Theme.mono(11, w.active ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(w.active ? Theme.vermilion : Theme.surface2)
                .foregroundStyle(w.active ? Theme.paper : Theme.muted)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
