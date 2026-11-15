import SwiftUI

struct BrowserProtectionSettingsView: View {
    let library: AppsLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checkmark.shield.fill").font(.system(size: 25)).foregroundStyle(Color.cvPrimary)
                            .frame(width: 48, height: 48).background(Color.cvPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Browse with a little more intention.").font(.headline)
                            Text("What ClearView hides inside this browser").font(.subheadline).foregroundStyle(Color.cvOnSurfaceVariant)
                        }
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.cvSurfaceContainerLow)

                Section("Filtering") {
                    setting("Strict Mode", detail: "Also blocks discovery words like bikini and lingerie.", symbol: "shield.lefthalf.filled",
                            value: Binding(get: { ProtectionModel.shared.strictMode }, set: { ProtectionModel.shared.strictMode = $0 }), id: "browser.strict-mode")
                    NavigationLink {
                        AppFilterSettingsView(site: .web, library: library)
                    } label: {
                        Label("Blocked words & creators", systemImage: "text.badge.minus")
                    }
                }.listRowBackground(Color.cvSurfaceContainerLow)

                Section("Feeds & search") {
                    setting("Hide YouTube Shorts", detail: "Blocks Shorts entry points, shelves and direct links.", symbol: "play.rectangle",
                            value: shortBinding(.youtube), id: "browser.hide-shorts")
                        .disabled(library.protectionBlocksShortVideos(for: .youtube))
                    if library.protectionBlocksShortVideos(for: .youtube) {
                        Text("Shorts is also blocked in full ClearView protection.").font(.caption).foregroundStyle(Color.cvOnSurfaceVariant)
                    }
                    setting("Hide Instagram Reels", detail: "Removes Reels entry points and keeps Reels links from opening.", symbol: "film",
                            value: shortBinding(.instagram), id: "browser.hide-reels")
                    setting("Hide Snapchat Spotlight", detail: "Removes Spotlight entry points and keeps Spotlight links from opening.", symbol: "sparkles",
                            value: shortBinding(.snapchat), id: "browser.hide-spotlight")
                    setting("Hide Facebook Reels", detail: "Removes Reels entry points and keeps Reels links from opening.", symbol: "play.square.stack",
                            value: shortBinding(.facebook), id: "browser.hide-facebook-reels")
                    setting("Hide Google search categories", detail: "Keeps only the All tab; Images, Videos, News and the rest are hidden.", symbol: "line.3.horizontal.decrease",
                            value: browserBinding(\.hideGoogleCategories), id: "browser.hide-google-categories")
                    setting("Remove blocked videos from feed", detail: "Blocked cards leave the feed instead of only being covered.", symbol: "rectangle.stack.badge.minus",
                            value: browserBinding(\.removeBlockedCards), id: "browser.remove-blocked-cards")
                }.listRowBackground(Color.cvSurfaceContainerLow)

                Section {
                    captionSizeSetting
                    setting("Block YouTube ads", detail: "Refuses ad requests, removes ad slots and skips video ads.", symbol: "hand.raised",
                            value: browserBinding(\.blockYouTubeAds), id: "browser.block-youtube-ads")
                } header: { Text("YouTube") } footer: {
                    Text("Caption size applies to the expanded horizontal player. YouTube default keeps the size chosen in YouTube's own caption settings. YouTube can change how ads are delivered; some ads may still get through.")
                }.listRowBackground(Color.cvSurfaceContainerLow)

                Section {
                    NavigationLink {
                        ProtectionView(model: ProtectionModel.shared)
                    } label: {
                        HStack {
                            Label("Open full ClearView protection…", systemImage: "checkmark.shield")
                            Spacer(minLength: 0)
                        }.foregroundStyle(Color.cvPrimary)
                    }
                } header: {
                    Text("Changes apply to this browser immediately. Some hidden feed items return when you turn a switch off. Tap page whitespace to show or hide the navigation bar.")
                        .font(.footnote).textCase(nil).padding(.bottom, 14)
                }.listRowBackground(Color.cvSurfaceContainerLow)
            }.scrollContentBackground(.hidden).background(Color.cvBackground)
                .navigationTitle("Protection settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(.cvPrimary).presentationDragIndicator(.visible)
    }

    private func shortBinding(_ site: AppSite) -> Binding<Bool> {
        Binding(get: { library.blocksShortVideos(for: site) }, set: { value in library.update(site) { $0.blockShortVideos = value } })
    }
    /// Off by default so YouTube's own caption size wins until the reader asks for a custom one.
    private var captionSizeSetting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { library.browserPreferences.captionFontSize != nil },
                set: { enabled in library.updateBrowser { $0.captionFontSize = enabled ? 22 : nil } }
            )) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "textformat.size").font(.system(size: 18)).foregroundStyle(Color.cvPrimary).frame(width: 24).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Custom caption size").font(.subheadline.weight(.semibold)).foregroundStyle(Color.cvOnSurface)
                        Text("Overrides the size YouTube uses for captions in the horizontal player.").font(.caption).foregroundStyle(Color.cvOnSurfaceVariant).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.tint(.cvPrimary).accessibilityIdentifier("browser.custom-caption-size")

            if let size = library.browserPreferences.captionFontSize {
                HStack(spacing: 12) {
                    Slider(value: Binding(
                        get: { Double(library.browserPreferences.captionFontSize ?? size) },
                        set: { value in library.updateBrowser { $0.captionFontSize = Int(value.rounded()) } }
                    ), in: 14...32, step: 1)
                        .accessibilityLabel("Caption font size")
                        .accessibilityIdentifier("browser.caption-font-size")
                    Text("\(size) px").font(.subheadline.monospacedDigit()).foregroundStyle(Color.cvOnSurfaceVariant)
                        .frame(width: 52, alignment: .trailing).accessibilityIdentifier("browser.caption-font-size-value")
                }.padding(.leading, 36)

                Text("Captions preview")
                    .font(.system(size: CGFloat(size), weight: .medium))
                    .foregroundStyle(.white).frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("browser.caption-preview")
            }
        }.padding(.vertical, 7)
    }
    private func browserBinding(_ path: WritableKeyPath<BrowserProtectionPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { library.browserPreferences[keyPath: path] }, set: { value in library.updateBrowser { $0[keyPath: path] = value } })
    }
    private func setting(_ title: String, detail: String, symbol: String, value: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: value) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Color.cvPrimary).frame(width: 24).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.cvOnSurface)
                    Text(detail).font(.caption).foregroundStyle(Color.cvOnSurfaceVariant).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.vertical, 7)
        }.tint(.cvPrimary).accessibilityIdentifier(id)
    }
}
