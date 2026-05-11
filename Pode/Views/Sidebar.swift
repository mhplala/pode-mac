import SwiftUI
import SwiftData

struct Sidebar: View {
    @Environment(\.brandAccent) private var accent: Color
    @Environment(\.appLanguage) private var lang: AppLanguage
    @Environment(AppStore.self) private var store
    @Query(sort: [SortDescriptor(\Show.addedAt, order: .reverse)]) private var allShows: [Show]
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                logoMark
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("pod")
                            .font(.serif(17, weight: .medium))
                            .tracking(-0.25)
                        Text("e")
                            .font(.serif(17, weight: .regular))
                            .italic()
                            .foregroundColor(accent)
                    }
                    Text("podcasts, transcribed")
                        .font(.mono(9.5))
                        .foregroundColor(Ink.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(Ink.tertiary)
                TextField(
                    t("Search…", lang),
                    text: Binding(
                        get: { store.search },
                        set: { store.updateSearch($0) }
                    )
                )
                    .textFieldStyle(.plain)
                    .font(.sans(12.5))
                    .foregroundColor(Ink.primary)
                    .focused($searchFocused)
                    // Hidden ⌘F binding — the visible "⌘F" hint chip next
                    // to the field actually does something now. Anywhere in
                    // the app, ⌘F focuses (and selects) the sidebar search.
                    .background(
                        Button("") {
                            searchFocused = true
                        }
                        .keyboardShortcut("f", modifiers: .command)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                    )
                Text("⌘F")
                    .font(.mono(10))
                    .foregroundColor(Ink.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 12)

            // Primary nav
            VStack(spacing: 1) {
                NavRow(view: .listenNow, icon: "headphones",        label: L10n.t("Listen Now", language: lang))
                NavRow(view: .browse,    icon: "globe",             label: L10n.t("Browse",     language: lang))
                NavRow(view: .library,   icon: "rectangle.grid.2x2", label: L10n.t("Library",    language: lang))
                NavRow(view: .knowledge, icon: "sparkles",          label: L10n.t("Knowledge",  language: lang), brand: true)
            }

            // Shows list
            VStack(spacing: 0) {
                HStack {
                    EyebrowText(text: L10n.t("Shows", language: lang).uppercased())
                    Spacer()
                    Button {
                        store.goTo(.browse)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Ink.secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.black.opacity(0.04))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // The sidebar list is *not* filtered by the search
                        // field — that field drives an iTunes podcast search
                        // in the main view. Always render every subscription
                        // so the user can still navigate while searching.
                        if allShows.isEmpty {
                            Text(L10n.t("No subscriptions yet.", language: lang))
                                .font(.serif(12, weight: .regular))
                                .italic()
                                .foregroundColor(Ink.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.top, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(allShows) { show in
                            ShowRow(show: show)
                        }
                    }
                }
            }
            .padding(.top, 18)
            .frame(maxHeight: .infinity)

            // Background tasks (transcribe, model download, etc.)
            TaskPill()

            // Footer (avatar + settings)
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [accent, Color(hex: "#e8a16c")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(store.settings.userName.isEmpty ? "·" : String(store.settings.userName.prefix(1)).uppercased())
                        .font(.serif(13, weight: .medium))
                        .italic()
                        .foregroundColor(.white)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 0) {
                    Text(store.settings.userName.isEmpty
                         ? L10n.t("Set your name", language: lang)
                         : store.settings.userName)
                        .font(.sans(12.5, weight: .medium))
                        .foregroundColor(Ink.primary)
                        .lineLimit(1)
                    Text("Pode")
                        .font(.mono(10))
                        .foregroundColor(Ink.tertiary)
                }
                Spacer()
                Button { store.goTo(.settings) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundColor(Ink.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.black.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .overlay(
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 1)
                    .padding(.horizontal, 6),
                alignment: .top
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(width: 244)
    }

    private var logoMark: some View {
        ZStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(accent)
        }
        .frame(width: 26, height: 26)
    }

}

private struct NavRow: View {
    @Environment(\.brandAccent) private var accent: Color
    @Environment(AppStore.self) private var store
    let view: AppView
    let icon: String
    let label: String
    var brand: Bool = false

    var body: some View {
        Button {
            // Sidebar nav = top-level destination. Clear back history
            // so Back from anywhere drilled-down off this root doesn't
            // bounce across roots.
            store.goTo(view)
        } label: {
            HStack(spacing: 11) {
                // Fixed-width icon frame so labels start at the same x across
                // rows even though SF Symbol natural widths vary (headphones
                // is wider than sparkles, etc).
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(brand && isOn ? accent : Ink.secondary)
                    .frame(width: 16, alignment: .center)
                Text(label)
                    .font(.sans(13.5, weight: .medium))
                    .foregroundColor(Ink.primary)
                Spacer()
                if view == .knowledge {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle().stroke(accent.opacity(0.14), lineWidth: 3)
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Color.white.opacity(0.7) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isOn ? Color.black.opacity(0.06) : .clear, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isOn: Bool {
        switch (store.view, view) {
        case (.listenNow, .listenNow), (.browse, .browse), (.library, .library), (.knowledge, .knowledge), (.settings, .settings):
            return true
        default: return false
        }
    }
}

private struct ShowRow: View {
    @Environment(\.brandAccent) private var accent: Color
    @Environment(AppStore.self) private var store
    let show: Show

    var body: some View {
        Button {
            // Sidebar show entries are like sidebar root nav — treat as
            // a fresh destination, not a drill-down. Back from a
            // sub-page should land here, not whatever non-related place
            // the user was in before.
            store.goTo(.show(show.id))
        } label: {
            HStack(spacing: 10) {
                CoverView(artworkUrl: show.artworkUrl, title: show.title, size: 26, radius: 5)
                Text(show.title)
                    .font(.sans(13, weight: .medium))
                    .foregroundColor(Ink.primary)
                    .lineLimit(1)
                Spacer()
                if let id = store.player.currentEpisodeID,
                   show.episodes.contains(where: { $0.id == id }),
                   store.player.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundColor(accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
