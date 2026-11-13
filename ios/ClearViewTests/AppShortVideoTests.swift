import XCTest
import WebKit
@testable import ClearView

/// Short-form blocking for the four apps that have a vertical feed.
///
/// The browser only ever sees a URL, so the app is decided from the host and the
/// switch from that app's preferences. These checks pin the routes each site uses
/// — including the two Facebook share formats — and that one app's switch can
/// never hide another app's content.
@MainActor
final class AppShortVideoTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppShortVideoTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func url(_ value: String) -> URL {
        URL(string: value)!
    }

    // MARK: - Naming

    /// Each app's own word for its vertical feed, and the two sites that have none.
    func testEachAppNamesItsVerticalFeed() {
        XCTAssertEqual(AppSite.youtube.shortVideoName, "Shorts")
        XCTAssertEqual(AppSite.instagram.shortVideoName, "Reels")
        XCTAssertEqual(AppSite.facebook.shortVideoName, "Reels")
        XCTAssertEqual(AppSite.snapchat.shortVideoName, "Spotlight")
        XCTAssertEqual(AppSite.google.shortVideoName, "")
        XCTAssertEqual(AppSite.web.shortVideoName, "")

        XCTAssertTrue(AppSite.youtube.supportsShortVideoBlocking)
        XCTAssertTrue(AppSite.instagram.supportsShortVideoBlocking)
        XCTAssertTrue(AppSite.snapchat.supportsShortVideoBlocking)
        XCTAssertTrue(AppSite.facebook.supportsShortVideoBlocking)
        XCTAssertFalse(AppSite.google.supportsShortVideoBlocking)
        XCTAssertFalse(AppSite.web.supportsShortVideoBlocking)
    }

    /// All four apps use the native shell; only Snapchat and Facebook replace the
    /// website header with a brand mark and app name.
    func testTheShortVideoAppsUseTheNativeShell() {
        for site in [AppSite.youtube, .instagram, .snapchat, .facebook] {
            XCTAssertTrue(site.usesAppShell, "\(site.name) should use the native shell")
        }
        XCTAssertFalse(AppSite.google.usesAppShell)
        XCTAssertFalse(AppSite.web.usesAppShell)

        XCTAssertTrue(AppSite.snapchat.usesBrandedHeader)
        XCTAssertTrue(AppSite.facebook.usesBrandedHeader)
        XCTAssertFalse(AppSite.youtube.usesBrandedHeader)
        XCTAssertFalse(AppSite.instagram.usesBrandedHeader)
    }

    /// Each branded app gets native tabs that point at its real routes, so the
    /// browser chrome is never shown for them.
    func testSnapchatAndFacebookNativeTabs() {
        XCTAssertEqual(AppSite.snapchat.destinations, [.home, .shortVideos, .account])
        XCTAssertEqual(AppSite.facebook.destinations, [.home, .shortVideos, .explore, .account])

        XCTAssertEqual(AppSite.snapchat.home.absoluteString, "https://www.snapchat.com/discover")
        XCTAssertEqual(AppSite.snapchat.destinationURL(.home).absoluteString, "https://www.snapchat.com/discover")
        XCTAssertEqual(AppSite.snapchat.destinationURL(.shortVideos).absoluteString, "https://www.snapchat.com/spotlight")
        XCTAssertEqual(AppSite.snapchat.destinationURL(.account).absoluteString, "https://accounts.snapchat.com/accounts/login")
        XCTAssertEqual(AppSite.facebook.destinationURL(.home).absoluteString, "https://m.facebook.com/")
        XCTAssertEqual(AppSite.facebook.destinationURL(.shortVideos).absoluteString, "https://m.facebook.com/reels/")
        XCTAssertEqual(AppSite.facebook.destinationURL(.explore).absoluteString, "https://m.facebook.com/search/top/")
        XCTAssertEqual(AppSite.facebook.destinationURL(.account).absoluteString, "https://m.facebook.com/me")
    }

    // MARK: - Routes

    /// YouTube Shorts and Instagram Reels keep their original behaviour.
    func testYouTubeAndInstagramRoutes() {
        for value in [
            "https://m.youtube.com/shorts",
            "https://m.youtube.com/shorts/abcdefghijk",
            "https://www.youtube.com/shorts/abcdefghijk?feature=share",
        ] {
            XCTAssertTrue(AppSite.youtube.isShortVideo(url(value)), value)
        }
        for value in [
            "https://www.youtube.com/watch?v=abcdefghijk",
            "https://m.youtube.com/",
            "https://www.youtube.com/results?search_query=shorts",
        ] {
            XCTAssertFalse(AppSite.youtube.isShortVideo(url(value)), value)
        }

        for value in [
            "https://www.instagram.com/reel/C1abc/",
            "https://www.instagram.com/reels/C1abc/",
            "https://www.instagram.com/reels/",
            "https://www.instagram.com/reel/",
        ] {
            XCTAssertTrue(AppSite.instagram.isShortVideo(url(value)), value)
        }
        for value in [
            "https://www.instagram.com/p/C1abc/",
            "https://www.instagram.com/",
            "https://www.instagram.com/explore/",
        ] {
            XCTAssertFalse(AppSite.instagram.isShortVideo(url(value)), value)
        }
    }

    /// Spotlight is Snapchat's short-form surface, on both web hosts.
    func testSnapchatSpotlightRoutes() {
        for value in [
            "https://web.snapchat.com/spotlight",
            "https://web.snapchat.com/spotlight/",
            "https://www.snapchat.com/spotlight",
            "https://www.snapchat.com/spotlight/abc123?share=1",
            "https://www.snapchat.com/web/spotlight/",
            "https://www.snapchat.com/web/spotlight/abc123",
        ] {
            XCTAssertTrue(AppSite.snapchat.isShortVideo(url(value)), value)
        }
        for value in [
            "https://web.snapchat.com/",
            "https://www.snapchat.com/",
            "https://www.snapchat.com/web/",
            "https://web.snapchat.com/stories/abc123",
            "https://www.snapchat.com/@someone",
        ] {
            XCTAssertFalse(AppSite.snapchat.isShortVideo(url(value)), value)
        }
    }

    /// Facebook calls them Reels and serves them from /reel and /reels, with the
    /// Share sheet's /share/reel and /share/r links landing on the same player.
    func testFacebookReelRoutes() {
        for value in [
            "https://www.facebook.com/reel/1234567890",
            "https://www.facebook.com/reels/",
            "https://m.facebook.com/reel/1234567890/",
            "https://web.facebook.com/reels/1234567890",
            "https://www.facebook.com/share/reel/abc123/",
            "https://www.facebook.com/share/r/abc123/",
        ] {
            XCTAssertTrue(AppSite.facebook.isShortVideo(url(value)), value)
        }
        for value in [
            "https://www.facebook.com/",
            "https://m.facebook.com/",
            "https://www.facebook.com/watch/?v=123",
            "https://www.facebook.com/stories/123/",
            "https://www.facebook.com/groups/123/",
        ] {
            XCTAssertFalse(AppSite.facebook.isShortVideo(url(value)), value)
        }
    }

    /// A short route on one app's domain is never another app's short route.
    func testShortRoutesDoNotLeakAcrossApps() {
        XCTAssertFalse(AppSite.facebook.isShortVideo(url("https://www.instagram.com/reel/C1abc/")))
        XCTAssertFalse(AppSite.instagram.isShortVideo(url("https://www.facebook.com/reel/1234567890")))
        XCTAssertFalse(AppSite.snapchat.isShortVideo(url("https://www.youtube.com/shorts/abcdefghijk")))
        XCTAssertFalse(AppSite.youtube.isShortVideo(url("https://web.snapchat.com/spotlight")))
    }

    /// Host lookup, including subdomains and the two domains that are not the app's
    /// own canonical one.
    func testHostMappingCoversSubdomains() {
        XCTAssertEqual(AppSite.shortVideoSite(for: "m.youtube.com"), .youtube)
        XCTAssertEqual(AppSite.shortVideoSite(for: "youtu.be"), .youtube)
        XCTAssertEqual(AppSite.shortVideoSite(for: "www.instagram.com"), .instagram)
        XCTAssertEqual(AppSite.shortVideoSite(for: "web.snapchat.com"), .snapchat)
        XCTAssertEqual(AppSite.shortVideoSite(for: "accounts.snapchat.com"), .snapchat)
        XCTAssertEqual(AppSite.shortVideoSite(for: "m.facebook.com"), .facebook)
        XCTAssertEqual(AppSite.shortVideoSite(for: "web.facebook.com"), .facebook)
        XCTAssertNil(AppSite.shortVideoSite(for: "example.com"))
        XCTAssertNil(AppSite.shortVideoSite(for: nil))
    }

    // MARK: - Switches

    /// Blocking is off until the user asks for it, and it is stored per app.
    func testSwitchesStartOffAndPersistPerApp() {
        let library = AppsLibrary(defaults: defaults)
        for site in [AppSite.youtube, .instagram, .snapchat, .facebook] {
            XCTAssertFalse(library.blocksShortVideos(for: site), "\(site.name) should start allowed")
        }

        library.update(.snapchat) { $0.blockShortVideos = true }
        library.update(.facebook) { $0.blockShortVideos = true }

        XCTAssertTrue(library.blocksShortVideos(for: .snapchat))
        XCTAssertTrue(library.blocksShortVideos(for: .facebook))
        XCTAssertFalse(library.blocksShortVideos(for: .youtube), "one app's switch is not another's")
        XCTAssertFalse(library.blocksShortVideos(for: .instagram))

        let reopened = AppsLibrary(defaults: defaults)
        XCTAssertTrue(reopened.blocksShortVideos(for: .snapchat), "the switch survives a relaunch")
        XCTAssertTrue(reopened.blocksShortVideos(for: .facebook))
    }

    /// The address bar decides which switch applies, so a link reached through the
    /// shared browser is covered without opening that app from the launcher.
    func testTheHostInTheAddressBarSelectsTheSwitch() {
        let library = AppsLibrary(defaults: defaults)
        library.update(.facebook) { $0.blockShortVideos = true }

        XCTAssertTrue(library.blocksShortVideos(at: url("https://www.facebook.com/reel/1234567890")))
        XCTAssertTrue(library.blocksShortVideos(at: url("https://m.facebook.com/reels/")))
        XCTAssertFalse(library.blocksShortVideos(at: url("https://www.facebook.com/watch/?v=123")))
        XCTAssertFalse(library.blocksShortVideos(at: url("https://www.instagram.com/reel/C1abc/")),
                       "Facebook's switch must not hide Instagram")

        library.update(.snapchat) { $0.blockShortVideos = true }
        XCTAssertTrue(library.blocksShortVideos(at: url("https://web.snapchat.com/spotlight")))
        XCTAssertTrue(library.blocksShortVideos(at: url("https://www.snapchat.com/spotlight/abc")))
        XCTAssertTrue(library.blocksShortVideos(at: url("https://www.snapchat.com/web/spotlight/")))
        XCTAssertFalse(library.blocksShortVideos(at: url("https://www.snapchat.com/web/")))
    }

    /// Google and the shared browser have no vertical feed of their own. A stale
    /// preference on either must not turn into a block.
    func testSitesWithoutAShortSurfaceNeverBlock() {
        let library = AppsLibrary(defaults: defaults)
        library.update(.web) { $0.blockShortVideos = true }
        library.update(.google) { $0.blockShortVideos = true }

        XCTAssertFalse(library.blocksShortVideos(for: .web))
        XCTAssertFalse(library.blocksShortVideos(for: .google))
        XCTAssertFalse(library.blocksShortVideos(at: url("https://www.google.com/search?q=reels")))
    }

    /// Each app keeps its own domain, while Google and the browser keep HTTPS links
    /// in their session — the browser can still be pointed at any of the four.
    func testEachAppOwnsItsDomain() {
        XCTAssertTrue(AppSite.snapchat.owns(url("https://web.snapchat.com/")))
        XCTAssertTrue(AppSite.snapchat.owns(url("https://accounts.snapchat.com/accounts/login")))
        XCTAssertFalse(AppSite.snapchat.owns(url("https://www.facebook.com/")))

        XCTAssertTrue(AppSite.facebook.owns(url("https://m.facebook.com/")))
        XCTAssertTrue(AppSite.facebook.owns(url("https://web.facebook.com/")))
        XCTAssertFalse(AppSite.facebook.owns(url("https://www.instagram.com/")))

        XCTAssertTrue(AppSite.web.owns(url("https://www.facebook.com/reels/")))
        XCTAssertTrue(AppSite.google.owns(url("https://example.com/")))
    }
    func testFacebookChromeAndReelsToggleInWebKit() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        web.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="margin:0">
          <header><div id="wordmark" style="height:48px;display:flex"><div role="button" aria-label="Facebook logo"><svg width="110" height="30"></svg></div><button>Search</button><button aria-label="Facebook Menu" onclick="window.menuOpened=true">Menu</button></div>
          <nav id="tabs" style="height:48px"><a id="friends" href="/friends/">Friends</a><a id="watch" href="/watch/?ref=tab">Video</a><a id="reels" href="/reels/">Reels</a><button id="icon" aria-label="Videos">Icon</button><div id="reelsSlot" style="width:65px;height:48px;background:grey"><div role="button" id="countedReels" aria-label="reels, 100 new, 4 of 6"><svg width="24" height="24"></svg></div></div></nav></header>
          <div id="fixedTabs" role="tablist" style="height:50px;width:390px;background:grey">
            <div role="tab" id="feedTab" aria-label="feed, 1 of 6" style="height:50px;width:65px">Home</div>
            <div role="tab" id="friendsTab" aria-label="friends, 2 of 6" style="height:50px;width:65px;margin-top:-50px;margin-left:65px">Friends</div>
            <div role="tab" id="messagesTab" aria-label="messages, 3 of 6" style="height:50px;width:65px;margin-top:-50px;margin-left:130px">Messages</div>
            <div role="tab" id="fixedReels" aria-label="reels, 100 new, 4 of 6" style="height:50px;width:65px;margin-top:-50px;margin-left:195px">Reels</div>
            <div role="tab" id="notificationsTab" aria-label="notifications, 5 of 6" style="height:50px;width:65px;margin-top:-50px;margin-left:260px">Notifications</div>
            <div role="tab" id="marketplaceTab" aria-label="marketplace, 6 of 6" style="height:50px;width:65px;margin-top:-50px;margin-left:325px">Marketplace</div>
          </div>
          <article id="post"><p>A normal post</p><a id="postVideo" href="/watch/?v=123">Watch video</a></article>
          <div id="promo" style="position:fixed;bottom:0;width:100%;height:80px;background:white"><button style="background:blue;width:100%;height:44px"><span><a href="https://apps.apple.com/app/facebook/id284882215">Open app</a></span></button></div>
        </body></html>
        """, baseURL: URL(string: "https://m.facebook.com/"))
        for _ in 0..<100 {
            if !web.isLoading { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let scriptURL = try XCTUnwrap(Bundle(for: AppBrowserSession.self).url(forResource: "ClearViewApps", withExtension: "js"))
        let source = try String(contentsOf: scriptURL, encoding: .utf8)
        _ = try await web.evaluateJavaScript("""
        var clearViewInitial = {site:'facebook',appShell:true,active:true,blockFacebookReels:true};
        \(source)
        window.__clearviewApps.update(clearViewInitial);
        true;
        """)
        let hidden: (String) async throws -> Bool = { id in
            try await web.evaluateJavaScript("getComputedStyle(document.getElementById('\(id)')).display === 'none'") as! Bool
        }
        for id in ["wordmark", "promo", "watch", "reels", "icon", "reelsSlot", "fixedReels"] {
            let result = try await hidden(id)
            XCTAssertTrue(result, "\(id) should disappear")
        }
        for id in ["tabs", "friends", "post", "postVideo"] {
            let result = try await hidden(id)
            XCTAssertFalse(result, "\(id) must remain available")
        }
        let rowFlows = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('notificationsTab')).marginLeft === '240.5px' && getComputedStyle(document.getElementById('notificationsTab')).marginTop === '-50px'") as? Bool
        XCTAssertEqual(rowFlows, true, "fixed-position tabs must close the gap left by Reels")
        _ = try await web.evaluateJavaScript("clearViewInitial.blockFacebookReels=false;window.__clearviewApps.update(clearViewInitial);true")
        for id in ["watch", "reels", "icon", "reelsSlot", "fixedReels"] {
            let result = try await hidden(id)
            XCTAssertFalse(result, "\(id) must return when blocking is disabled")
        }
        let restoredMargin = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('notificationsTab')).marginLeft") as? String
        XCTAssertEqual(restoredMargin, "260px", "disabling blocking must restore the site's layout")
        let menuOpened = try await web.evaluateJavaScript("window.__clearviewApps.openSiteMenu() && window.menuOpened === true") as? Bool
        XCTAssertEqual(menuOpened, true, "Facebook's menu must stay available through the native header")
        let promoStillHidden = try await hidden("promo")
        XCTAssertTrue(promoStillHidden, "repeat scans must not leave the promo background behind")
    }

}
