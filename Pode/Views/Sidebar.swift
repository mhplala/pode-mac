import SwiftUI
import SwiftData

struct Sidebar: View {
    @Environment(AppStore.self) private var store
    @Query(sort: [SortDescriptor(\Show.addedAt, order: .reverse)]) private var allShows: [Show]

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
                            .foregroundColor(Brand.orange)
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
                TextField("Filter your shows…", text: $store.search)
                    .textFieldStyle(.plain)
                    .font(.sans(12.5))
                    .foregroundColor(Ink.primary)
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
                NavRow(view: .listenNow, icon: "headphones", label: "Listen Now")
                NavRow(view: .browse, icon: "globe", label: "Browse")
                NavRow(view: .library, icon: "rectangle.grid.2x2", label: "Library")
                NavRow(view: .knowledge, icon: "sparkles", label: "Knowledge", brand: true)
            }

            // Shows list
            VStack(spacing: 0) {
                HStack {
                    EyebrowText(text: "Shows")
                    Spacer()
                    Button {
                        store.view = .browse
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
                        let filtered = filteredShows()
                        if filtered.isEmpty {
                            Text(allShows.isEmpty ? "No subscriptions yet." : "No matches.")
                                .font(.serif(12, weight: .regular))
                                .italic()
                                .foregroundColor(Ink.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.top, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(filtered) { show in
                            ShowRow(show: show)
                        }
                    }
                }
            }
            .padding(.top, 18)
            .frame(maxHeight: .infinity)

            // Footer (avatar + settings)
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Brand.orange, Color(hex: "#e8a16c")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(store.settings.userName.isEmpty ? "·" : String(store.settings.userName.prefix(1)).uppercased())
                        .font(.serif(13, weight: .medium))
                        .italic()
                        .foregroundColor(.white)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 0) {
                    Text(store.settings.userName.isEmpty ? "Set your name" : store.settings.userName)
                        .font(.sans(12.5, weight: .medium))
                        .foregroundColor(Ink.primary)
                        .lineLimit(1)
                    Text("Pode")
                        .font(.mono(10))
                        .foregroundColor(Ink.tertiary)
                }
                Spacer()
                Button { store.view = .settings } label: {
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
        .padding(.vertical, 16)
        .frame(width: 244)
    }

    private var logoMark: some View {
        ZStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(Brand.orange)
        }
        .frame(width: 26, height: 26)
    }

    private func filteredShows() -> [Show] {
        let q = store.search.lowercased()
        if q.isEmpty { return allShows }
        return allShows.filter {
            $0.title.lowercased().contains(q) || $0.host.lowercased().contains(q)
        }
    }
}

private struct NavRow: View {
    @Environment(AppStore.self) private var store
    let view: AppView
    let icon: String
    let label: String
    var brand: Bool = false

    var body: some View {
        Button {
            store.view = view
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(brand && isOn ? Brand.orange : Ink.secondary)
                Text(label)
                    .font(.sans(13.5, weight: .medium))
                    .foregroundColor(Ink.primary)
                Spacer()
                if view == .knowledge {
                    Circle()
                        .fill(Brand.orange)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle().stroke(Brand.orange.opacity(0.14), lineWidth: 3)
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
    @Environment(AppStore.self) private var store
    let show: Show

    var body: some View {
        Button {
            store.view = .show(show.id)
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
                        .foregroundColor(Brand.orange)
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
