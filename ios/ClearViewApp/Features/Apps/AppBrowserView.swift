import SwiftUI
import WebKit

struct AppBrowserView: View {
    @Bindable var session: AppBrowserSession
    let library: AppsLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFilters = false
    @State private var showSignInHelp = false
    @State private var dialogEntry = ""
    @State private var showSearch = false
    @Namespace private var navigationSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        browserWithAlerts
            .alert(session.site.name, isPresented: Binding(
                get: { session.websiteDialog != nil }, set: { _ in }
            ), presenting: session.websiteDialog) { dialog in
                if dialog.kind == .input { TextField("Response", text: $dialogEntry) }
                Button(dialog.kind == .notice ? "OK" : "Continue") { session.finishDialog(dialog.kind == .input ? dialogEntry : "true") }
                if dialog.kind != .notice { Button("Cancel", role: .cancel) { session.finishDialog(nil) } }
            } message: { dialog in Text(dialog.message) }
    }

    private var browserLayout: some View {
        VStack(spacing: 0) {
            if !session.navigationHidden && !session.playerFullscreen { header }
            if let notice = session.protectionNotice, !session.playerFullscreen {
                Text(notice).font(.caption).foregroundStyle(Color.cvOnSurfaceVariant).padding(8)
            }
            ZStack(alignment: .leading) {
                Color.cvOutlineVariant.opacity(0.3)
                GeometryReader { geometry in
                    Rectangle().fill(Color.cvPrimary).frame(width: geometry.size.width * session.progress)
                }.opacity(session.isLoading ? 1 : 0)
            }.frame(height: session.playerFullscreen ? 0 : 2).accessibilityHidden(true)
            ZStack {
                AppWebsiteView(session: session)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { session.updatePlayerViewport($0) }
                    .accessibilityHidden(session.blockedPage != nil || session.errorMessage != nil || session.showsIntentHome)
                if let blocked = session.blockedPage {
                    browserState(symbol: "eye.slash", title: "A little less noise", message: blocked, action: "Back to home") { session.goHome() }
                } else if let error = session.errorMessage {
                    browserState(symbol: "wifi.exclamationmark", title: "Let’s try that again", message: error, action: "Reload") { session.reload() }
                } else if session.showsIntentHome {
                    intentHome
                } else if session.isLoading && session.progress < 0.15 && session.currentURL == nil {
                    VStack(spacing: 18) {
                        AppBrandMark(site: session.site, size: 64)
                        ProgressView().tint(.cvPrimary)
                        Text("Opening \(session.site.name)…").font(.footnote).foregroundStyle(Color.cvOnSurfaceVariant)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.cvBackground)
                }
            }
            if showsBottomNavigation && session.site != .youtube {
                if session.site.usesAppShell { navigationBar } else { browserToolbar }
            }
        }
        .overlay(alignment: .bottom) {
            if showsBottomNavigation && session.site == .youtube {
                youtubeNavigation
                    .padding(.horizontal, 18).padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.container, edges: bottomSafeAreaEdges)
        .statusBarHidden(session.playerFullscreen)
        .persistentSystemOverlays(session.playerFullscreen ? .hidden : .automatic)
        .overlay(alignment: .bottomTrailing) {
            if session.navigationHidden && !session.playerFullscreen {
                Button { withAnimation(.easeInOut(duration: 0.18)) { session.navigationHidden = false } } label: {
                    Image(systemName: "chevron.up").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.cvPrimary).frame(width: 44, height: 34)
                        .background(Color.cvSurfaceContainerHigh, in: Capsule())
                }.padding(12).accessibilityLabel("Show navigation").accessibilityIdentifier("browser.show-navigation")
            }
        }
        .animation(.easeInOut(duration: 0.18), value: session.navigationHidden)
    }

    private var configuredBrowser: some View {
        browserLifecycle
        .sheet(isPresented: $showFilters, onDismiss: { session.applyPreferences() }) {
            BrowserProtectionSettingsView(library: library)
        }
        .sheet(isPresented: $showSearch) {
            AppSearchSheet(site: session.site) { session.search($0) }
        }
    }

    private var browserLifecycle: some View {
        browserLayout
        .background(Color(uiColor: session.pageBackground)).tint(.cvPrimary)
        .preferredColorScheme(session.site == .facebook ? .light : nil)
        .task { session.resume(dark: colorScheme == .dark) }
        .task(id: session.filterSignature) { session.applyPreferences() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.resume(dark: colorScheme == .dark) } else if phase == .background { session.pause() }
        }
        .onChange(of: colorScheme) { _, scheme in session.resume(dark: scheme == .dark) }
        .onChange(of: session.websiteDialog?.id) { _, _ in dialogEntry = session.websiteDialog?.defaultText ?? "" }
        .onChange(of: DeviceControlsController.shared.expired) { _, expired in
            if expired { session.pause(); dismiss() }
        }
        .onDisappear { session.pause() }
    }

    private var browserWithAlerts: some View {
        configuredBrowser
        .confirmationDialog("Open outside ClearView?", isPresented: Binding(
            get: { session.externalURL != nil }, set: { if !$0 { session.externalURL = nil } }
        ), titleVisibility: .visible, presenting: session.externalURL) { url in
            Button("Open \(url.host ?? "link")") { openURL(url); session.externalURL = nil }
            Button("Cancel", role: .cancel) { session.externalURL = nil }
        } message: { _ in Text("ClearView’s filters apply inside Apps. This link opens in another app.") }
        .alert("This link needs another app", isPresented: $session.unsupportedLink) {
            Button("OK", role: .cancel) { }
        } message: { Text("Stay here to use the website, or choose Open in Safari from the menu.") }
        .alert("Signing in", isPresented: $showSignInHelp) {
            Button("Keep browsing", role: .cancel) { }
            Button("Open in Safari") { if let url = session.currentURL { openURL(url) } }
        } message: {
            Text("Sign in using \(session.site.name)’s own page. Some providers, including Google, restrict embedded browser sign-in. If the provider refuses, you can browse publicly here or use Safari. Safari’s login session won’t transfer into ClearView.")
        }
    }

    private var facebookHeader: Bool { session.site == .facebook }
    private var headerForeground: Color { facebookHeader ? .black : .cvOnSurface }

    private var header: some View {
        HStack(spacing: 2) {
            Button {
                if showsBackButton { session.goBack() } else { session.pause(); dismiss() }
            } label: {
                Image(systemName: showsBackButton ? "chevron.left" : "xmark")
                    .font(.system(size: 17, weight: .medium)).frame(width: 40, height: 44)
            }.accessibilityLabel(showsBackButton ? "Back" : "Back to Apps")
            if session.site == .youtube && session.showsAppNavigation {
                Button { session.goHome() } label: { appTitle }
                    .buttonStyle(.plain).accessibilityLabel("YouTube home")
                    .accessibilityIdentifier("apps.youtube-home")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                appTitle.frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.showsAppNavigation {
                // Snapchat's site has no query-based search route; the native
                // Discover tab is its discovery surface instead.
                if session.site != .snapchat {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 21)).frame(width: 40, height: 44)
                    }.accessibilityLabel(session.site.usesAppShell ? "Search \(session.site.name)" : "Search the web")
                }
                if session.site == .instagram {
                    Button { session.openInbox() } label: {
                        Image(systemName: "paperplane").font(.system(size: 20)).frame(width: 40, height: 44)
                    }.accessibilityLabel("Messages")
                }
            }
            Button { showFilters = true } label: {
                Image(systemName: session.blocksShortVideos ? "shield.lefthalf.filled" : "checkmark.shield")
                    .font(.system(size: 21)).foregroundStyle(facebookHeader ? Color.blue : Color.cvPrimary).frame(width: 40, height: 44)
            }.accessibilityLabel("Filters, \(session.hiddenCount) items hidden this session").accessibilityIdentifier("apps.filters")
            Menu {
                if session.showsAppNavigation && session.site.usesBrandedHeader {
                    Section("Go to") {
                        ForEach(visibleDestinations) { destination in
                            Button { session.navigate(destination) } label: {
                                Label(destination.title(for: session.site),
                                      systemImage: destination.symbol(selected: false))
                            }
                        }
                    }
                }
                if session.site == .facebook && session.showsAppNavigation {
                    Button("Facebook menu", systemImage: "line.3.horizontal") { session.openFacebookMenu() }
                }
                if session.canGoBack { Button("Back", systemImage: "chevron.left") { session.goBack() } }
                Button("Reload", systemImage: "arrow.clockwise") { session.reload() }
                Button("Protection settings", systemImage: "slider.horizontal.3") { showFilters = true }
                Button("Back to Apps", systemImage: "square.grid.2x2") { session.pause(); dismiss() }
                Button("Sign-in help", systemImage: "person.crop.circle.badge.questionmark") { showSignInHelp = true }
                if let url = session.currentURL {
                    if session.site.owns(url) {
                        ShareLink(item: url) { Label("Share page", systemImage: "square.and.arrow.up") }
                    }
                    Button("Open in Safari", systemImage: "safari") { session.pause(); openURL(url) }
                }
            } label: { Image(systemName: "ellipsis").font(.system(size: 19, weight: .semibold)).frame(width: 36, height: 44) }
                .accessibilityLabel("App menu")
        }.padding(.horizontal, 6).padding(.vertical, 2).foregroundStyle(headerForeground)
            .background(facebookHeader ? Color.white : Color.cvBackground)
            .overlay(alignment: .bottom) { Color.cvOutlineVariant.opacity(0.3).frame(height: 0.5) }
    }

    /// Facebook and Snapchat are branded web apps whose own pages already carry
    /// navigation. A second bottom bar only covers their content, so their
    /// destinations live in the header menu instead.
    private var bottomSafeAreaEdges: Edge.Set {
        session.playerFullscreen ? .all : session.site.usesBrandedHeader ? .bottom : Edge.Set()
    }

    private var showsBottomNavigation: Bool {
        session.showsAppNavigation && !session.navigationHidden && !session.playerFullscreen && !session.youtubePanelVisible && !session.site.usesBrandedHeader
    }

    private var showsBackButton: Bool {
        guard session.canGoBack else { return false }
        // YouTube and Instagram use their native tabs for top-level movement. The
        // branded web apps keep ordinary page history, so Back stays available
        // wherever they have somewhere to go back to.
        if session.site.usesBrandedHeader { return true }
        let path = session.currentURL?.path ?? "/"
        return !session.showsAppNavigation || path == "/watch" || path == "/results" || path.hasPrefix("/p/")
    }

    private var intentHome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 20)
            Image(systemName: "play.rectangle").font(.system(size: 37)).foregroundStyle(Color.cvPrimary)
                .frame(width: 76, height: 76).background(Color.cvPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
            Text("What’s worth\nyour time today?").font(.system(size: 31, weight: .bold, design: .rounded)).tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pick something you want to watch. A little intention goes a long way.")
                .font(.subheadline).foregroundStyle(Color.cvOnSurfaceVariant).lineSpacing(3)
            Button { showSearch = true } label: {
                Label("Search YouTube", systemImage: "magnifyingglass").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Color.cvPrimary, in: Capsule()).foregroundStyle(Color.cvOnPrimary)
            }.buttonStyle(.plain)
            Button { session.navigate(.subscriptions) } label: {
                Label("Go to subscriptions", systemImage: "play.rectangle.on.rectangle")
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Color.cvSurfaceContainerLow, in: Capsule()).foregroundStyle(Color.cvOnSurface)
            }.buttonStyle(.plain)
            Spacer(minLength: 30)
            Label(session.blocksShortVideos ? "Shorts are hidden" : "Your filters are active", systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(Color.cvOnSurfaceVariant).frame(maxWidth: .infinity)
        }.padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.cvBackground)
    }

    private var appTitle: some View {
        HStack(spacing: 7) {
            if session.showsAppNavigation {
                switch session.site {
                case .youtube:
                    YouTubeLogoMark().frame(width: 31, height: 22)
                case .facebook:
                    EmptyView()
                case .snapchat:
                    AppBrandMark(site: session.site, size: 25)
                case .google, .instagram, .web:
                    EmptyView()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.showsAppNavigation ? (session.site.usesAppShell ? session.site.name : "ClearView") : "Sign in")
                    .font(.system(size: session.site == .youtube ? 23 : 21, weight: .bold, design: session.site == .youtube ? .default : .rounded))
                    .fontWidth(session.site == .youtube ? .condensed : .standard).tracking(-0.7)
                    .foregroundStyle(facebookHeader ? Color.blue : headerForeground)
                    .accessibilityIdentifier("browser.title")
                // A branded app never shows its website address. Google and custom
                // websites keep the host so the person knows where they are.
                if !session.site.usesBrandedHeader && (!session.showsAppNavigation || !session.site.usesAppShell) {
                    Text(session.currentURL?.host ?? "Search the web").font(.caption2).foregroundStyle(Color.cvOnSurfaceVariant)
                        .accessibilityIdentifier("browser.host")
                }
            }
        }
    }

    private var browserToolbar: some View {
        HStack {
            Button { session.goBack() } label: { Image(systemName: "chevron.left").frame(maxWidth: .infinity, minHeight: 48) }
                .disabled(!session.canGoBack).accessibilityLabel("Back")
            Button { session.goForward() } label: { Image(systemName: "chevron.right").frame(maxWidth: .infinity, minHeight: 48) }
                .disabled(!session.canGoForward).accessibilityLabel("Forward")
            Button { session.goHome() } label: { Image(systemName: "house").frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel("Google home")
            Button { showSearch = true } label: { Image(systemName: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel("Search the web")
            Button { session.reload() } label: { Image(systemName: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel("Reload page")
        }.font(.system(size: 20)).buttonStyle(.plain).foregroundStyle(Color.cvOnSurface)
            .background(Color.cvSurfaceContainerLow)
            .overlay(alignment: .top) { Color.cvOutlineVariant.opacity(0.3).frame(height: 0.5) }
    }

    private var visibleDestinations: [AppDestination] {
        session.site.destinations.filter { $0 != .shortVideos || !session.blocksShortVideos }
    }

    private var youtubeNavigation: some View {
        glassNavigationSurface
            .frame(maxWidth: 440)
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("apps.youtube-floating-navigation")
    }

    @ViewBuilder private var glassNavigationSurface: some View {
        if #available(iOS 26.0, *) {
            youtubeNavigationItems.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            youtubeNavigationItems.background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
        }
    }

    private var youtubeNavigationItems: some View {
        HStack(spacing: 2) {
            ForEach(visibleDestinations) { destination in
                let selected = session.selectedDestination == destination
                Button { session.navigate(destination) } label: {
                    VStack(spacing: 3) {
                        youtubeTabIcon(destination, selected: selected).frame(width: 25, height: 25)
                        Text(destination.title(for: session.site))
                            .font(.system(size: 10, weight: selected ? .semibold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.75))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        if selected {
                            Capsule().fill(.white.opacity(0.16))
                                .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5) }
                                .matchedGeometryEffect(id: "youtube-selection", in: navigationSelection)
                        }
                    }
                    .contentShape(Capsule())
                }.buttonStyle(.plain)
                    .accessibilityLabel(destination.title(for: session.site))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("apps.navigation.\(destination.rawValue)")
            }
        }.padding(5)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: session.selectedDestination)
    }

    @ViewBuilder private func youtubeTabIcon(_ destination: AppDestination, selected: Bool) -> some View {
        if destination == .shortVideos {
            YouTubeShortsMark().stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                .overlay { Image(systemName: "play.fill").font(.system(size: 8, weight: .semibold)) }
        } else if destination == .subscriptions {
            ZStack {
                RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1.8).frame(width: 24, height: 16).offset(y: 3)
                Capsule().frame(width: 18, height: 1.7).offset(y: -9)
                Capsule().frame(width: 14, height: 1.7).offset(y: -12)
                Image(systemName: "play.fill").font(.system(size: 8)).offset(y: 3)
            }
        } else {
            Image(systemName: destination.symbol(selected: selected))
                .font(.system(size: 23, weight: selected ? .semibold : .regular))
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleDestinations) { destination in
                let selected = session.selectedDestination == destination
                Button { session.navigate(destination) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: destination.symbol(selected: selected)).font(.system(size: 21))
                        Text(destination.title(for: session.site)).font(.system(size: 10, weight: selected ? .semibold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                        .foregroundStyle(selected ? Color.cvPrimary : Color.cvOnSurfaceVariant)
                }.buttonStyle(.plain).accessibilityLabel(destination.title(for: session.site))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("apps.navigation.\(destination.rawValue)")
            }
        }.padding(.top, 4).background(Color.cvSurfaceContainerLow)
            .overlay(alignment: .top) { Color.cvOutlineVariant.opacity(0.3).frame(height: 0.5) }
    }

    private func browserState(symbol: String, title: String, message: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(Color.cvPrimary)
                .frame(width: 82, height: 82).background(Color.cvPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 25))
            Text(title).font(.title2.weight(.bold))
            Text(message).font(.subheadline).foregroundStyle(Color.cvOnSurfaceVariant).multilineTextAlignment(.center)
            Button(action, action: perform).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .tint(.cvPrimary).foregroundStyle(Color.cvOnPrimary).padding(.top, 4)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.cvBackground)
    }
}

private struct AppSearchSheet: View {
    let site: AppSite
    let search: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.cvPrimary)
                    TextField(site.usesAppShell ? "What do you want to find?" : "Search or enter website address", text: $query)
                        .focused($focused).submitLabel(.search).onSubmit(submit)
                        .accessibilityIdentifier("apps.search.query")
                }.padding(16).background(Color.cvSurfaceContainerLow, in: RoundedRectangle(cornerRadius: 16))
                Text(site.usesAppShell ? "Find something worth your time." : "ClearView protection applies to your searches and websites.").font(.subheadline).foregroundStyle(Color.cvOnSurfaceVariant)
                Button("Search", action: submit).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer(minLength: 0)
            }.padding(20).background(Color.cvBackground)
                .navigationTitle(site.usesAppShell ? "Search \(site.name)" : "Search the web").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .task { focused = true }
        }.tint(.cvPrimary).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func submit() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        search(value)
        dismiss()
    }
}

private struct AppWebsiteView: UIViewRepresentable {
    let session: AppBrowserSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.pauseAllMediaPlayback(completionHandler: nil)
    }
}

/// A compact ribbon silhouette distinguishes Shorts from ordinary videos.
private struct YouTubeShortsMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width / 24, y: rect.minY + y * rect.height / 24) }
        path.move(to: point(14.5, 2))
        path.addCurve(to: point(20, 7.8), control1: point(19.2, -0.5), control2: point(23, 5.1))
        path.addLine(to: point(15.8, 10.3))
        path.addLine(to: point(18.1, 11.5))
        path.addCurve(to: point(18.2, 18), control1: point(22, 13.7), control2: point(21.4, 16.2))
        path.addLine(to: point(9.4, 23))
        path.addCurve(to: point(4, 17.1), control1: point(4.9, 25.5), control2: point(0.9, 20.1))
        path.addLine(to: point(8.1, 14.7))
        path.addLine(to: point(5.9, 13.4))
        path.addCurve(to: point(5.8, 6.9), control1: point(2.2, 11.3), control2: point(2.5, 8.7))
        path.addLine(to: point(14.5, 2))
        path.closeSubpath()
        return path
    }
}
