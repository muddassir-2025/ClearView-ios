import XCTest
import UIKit
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
        try await waitForDocumentReady(web)
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

    func testYouTubeHeaderSpacingAndFullscreenPreserveCaptionLayer() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        web.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0}ytm-app{display:block;border-top:50px solid transparent}
        #player{position:relative;width:390px;height:220px;padding-bottom:56.25%;background:black}
        .captions{position:absolute;bottom:20px;left:20px;color:white}</style></head>
        <body><ytm-app><div style="height:50px"></div><div class="page-container"><div id="player" class="html5-video-player">
        <div class="html5-video-container"><video playsinline></video></div>
        <div class="captions">A caption above the video</div>
        <button class="ytp-fullscreen-button" aria-label="Full screen" onclick="window.videoOnlyFullscreen=true">Full screen</button>
        </div></div></ytm-app></body></html>
        """, baseURL: URL(string: "https://m.youtube.com/"))
        try await waitForDocumentReady(web)
        let scriptURL = try XCTUnwrap(Bundle(for: AppBrowserSession.self).url(forResource: "ClearViewApps", withExtension: "js"))
        let source = try String(contentsOf: scriptURL, encoding: .utf8)
        _ = try await web.evaluateJavaScript("""
        var clearViewInitial={site:'youtube',appShell:true,active:true};
        \(source)
        window.__clearviewApps.update(clearViewInitial);
        true;
        """)
        _ = try await web.evaluateJavaScript("window.__clearviewApps.update(clearViewInitial);true")
        let feedTop = try await web.evaluateJavaScript("document.querySelector('.page-container').getBoundingClientRect().top") as! Double
        XCTAssertEqual(feedTop, 0, accuracy: 0.5, "the hidden masthead must leave no reserved space after repeated scans")
        _ = try await web.evaluateJavaScript("window.playerInlineHeight=document.getElementById('player').getBoundingClientRect().height;window.__clearviewApps.updateViewport(390,500);document.querySelector('.ytp-fullscreen-button').click();true")
        let expanded = try await web.evaluateJavaScript("""
        (()=>{const p=document.getElementById('player').getBoundingClientRect();
        const c=document.querySelector('.captions').getBoundingClientRect();
        return p.width===390 && p.height===500 && c.top>=p.top && c.bottom<=p.bottom
          && !window.videoOnlyFullscreen
          && document.documentElement.getAttribute('data-cv-player-fullscreen')==='true';})()
        """) as? Bool
        XCTAssertEqual(expanded, true, "fullscreen must include the HTML captions and intercept video-only fullscreen")
        let noDoneButton = try await web.evaluateJavaScript("!document.getElementById('clearview-exit-fullscreen')") as? Bool
        XCTAssertEqual(noDoneButton, true, "fullscreen must not add a separate Done button over YouTube's controls")
        _ = try await web.evaluateJavaScript("document.querySelector('.ytp-fullscreen-button').click();true")
        let restored = try await web.evaluateJavaScript("!document.documentElement.hasAttribute('data-cv-player-fullscreen') && document.getElementById('player').getBoundingClientRect().height===window.playerInlineHeight") as? Bool
        XCTAssertEqual(restored, true, "YouTube's own fullscreen control must close the expanded player")
        _ = try await web.evaluateJavaScript("document.querySelector('.ytp-fullscreen-button').click();window.__clearviewApps.pause();true")
        let paused = try await web.evaluateJavaScript("!document.documentElement.hasAttribute('data-cv-player-fullscreen')") as? Bool
        XCTAssertEqual(paused, true, "leaving the app must exit the expanded player")
    }

    func testYouTubeFullscreenCaptionsAreCenteredAndLoweredInHorizontalPlayer() async throws {
        let web = try await youtubeFixture("""
        <div id="player-container-id"><div id="player"><video playsinline></video>
          <div class="ytp-caption-window-container">
            <div class="caption-window ytp-caption-window-bottom" style="left:100px;font-size:18px;text-align:left">
              <span class="caption-visual-line">
                <span class="ytp-caption-segment" style="font-size:18px">Captioned content line</span>
              </span>
            </div>
          </div>
          <div id="player-control-overlay" class="fadein"><button class="fullscreen-button" aria-label="Enter full screen">Expand</button></div>
        </div></div>
        """)
        let portraitAlign = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.caption-window')).textAlign") as? String
        let portraitSize = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.ytp-caption-segment')).fontSize") as? String
        XCTAssertEqual(portraitAlign, "left", "portrait captions must remain untouched")
        XCTAssertEqual(portraitSize, "18px", "portrait captions must keep default font size")

        _ = try await web.evaluateJavaScript("window.__clearviewApps.updateViewport(844,390);document.querySelector('.fullscreen-button').click();true")
        let landscapeAlign = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.caption-window')).textAlign") as? String
        let landscapeLineAlign = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.caption-visual-line')).textAlign") as? String
        let landscapeSize = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.ytp-caption-segment')).fontSize") as? String
        let transform = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.caption-window')).transform") as? String
        let bottom = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.caption-window')).bottom") as? String

        XCTAssertEqual(landscapeAlign, "center", "captions in horizontal player must be centered")
        XCTAssertEqual(landscapeLineAlign, "center", "caption visual lines in horizontal player must be centered")
        XCTAssertEqual(landscapeSize, "18px", "captions in horizontal player must retain their default font size")
        XCTAssertNotNil(transform, "caption window must have center transform")
        XCTAssertNotEqual(transform, "none", "caption window must be centered via transform")
        XCTAssertEqual(bottom, "6%", "captions must be lowered to 6% of the viewport")
    }

    func testYouTubeWatchPlayerConsumesReservedTopbarSlot() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        web.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0}ytm-app{display:block;padding-top:48px}
        .player-container{position:absolute;top:48px;left:0;right:0}
        #player{width:390px;height:220px;background:black}</style></head>
        <body><ytm-app><div class="page-container"><div class="player-container">
        <div id="player" class="html5-video-player"><div class="html5-video-container"><video playsinline></video></div></div>
        </div></div></ytm-app></body></html>
        """, baseURL: URL(string: "https://m.youtube.com/watch?v=abc123")!)
        try await waitForDocumentReady(web)
        let scriptURL = try XCTUnwrap(Bundle(for: AppBrowserSession.self).url(forResource: "ClearViewApps", withExtension: "js"))
        let source = try String(contentsOf: scriptURL, encoding: .utf8)
        _ = try await web.evaluateJavaScript("""
        var clearViewInitial={site:'youtube',appShell:true,active:true};
        \(source)
        window.__clearviewApps.update(clearViewInitial);
        true;
        """)
        let playerTop = try await web.evaluateJavaScript("document.querySelector('.player-container').getBoundingClientRect().top") as! Double
        XCTAssertEqual(playerTop, 0, accuracy: 0.5, "the native header must replace YouTube's 48px watch-page topbar slot")
        _ = try await web.evaluateJavaScript("window.__clearviewApps.update({site:'youtube',appShell:false,active:true});true")
        let restored = try await web.evaluateJavaScript("document.querySelector('.player-container').getBoundingClientRect().top") as! Double
        XCTAssertEqual(restored, 48, accuracy: 0.5, "disabling the app shell must restore YouTube's own topbar spacing")
        _ = try await web.evaluateJavaScript("window.__clearviewApps.update({site:'youtube',appShell:true,active:true});true")
        let reapplied = try await web.evaluateJavaScript("document.querySelector('.player-container').getBoundingClientRect().top") as! Double
        XCTAssertEqual(reapplied, 0, accuracy: 0.5, "re-enabling the app shell must consume the slot again")
    }

    func testPlayerFullscreenUsesLandscapeAndReturnsToPortrait() {
        XCTAssertEqual(AppOrientation.mask(fullscreen: true), .landscape,
                       "fullscreen must allow both landscape directions, never portrait")
        XCTAssertEqual(AppOrientation.mask(fullscreen: false), .portrait,
                       "closing the player must return the browser to portrait")
    }

    /// YouTube's watch-next feed shows a floating row of filter chips ("All",
    /// "From <channel>", "Related", "For you") while scrolling. Only the chip
    /// renderers are removed. A surrounding layout slot can also contain the
    /// watch title, action bar, and comments, so hiding a generic wrapper hid
    /// that metadata in some signed-in layouts.
    func testYouTubeRelatedChipBarsAreRemovedWithAppShell() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        web.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0}ytm-app,ytm-related-chip-cloud-renderer,ytm-chip-cloud-renderer,
        .related-chips-slot-wrapper,#filter-chip-bar,ytm-rich-item-renderer,
        ytm-slim-video-metadata-section-renderer,ytm-slim-video-action-bar-renderer,
        ytm-comments-section-renderer{display:block}.related-chips-slot-wrapper{min-height:52px}
        #filter-chip-bar{min-height:48px}</style></head>
        <body><ytm-app><div class="page-container">
          <div class="related-chips-slot-wrapper">
            <ytm-slim-video-metadata-section-renderer id="metadata">Secretly Building my Wife's Dream Patio</ytm-slim-video-metadata-section-renderer>
            <ytm-slim-video-action-bar-renderer id="likes">19M likes</ytm-slim-video-action-bar-renderer>
            <ytm-related-chip-cloud-renderer id="relatedChips" class="chips-fixed-positioning chips-visible"><ytm-chip-cloud-renderer class="chip-bar">All From Morley Kert Related For you</ytm-chip-cloud-renderer></ytm-related-chip-cloud-renderer>
            <ytm-comments-section-renderer id="comments">Comments</ytm-comments-section-renderer>
          </div>
          <div id="related-chips-sentinel" class="related-chips-sentinel">sentinel</div>
          <div id="filter-chip-bar">All From Morley Kert Related For you</div>
          <ytm-feed-filter-chip-bar-renderer id="homeChips"><ytm-chip-cloud-renderer class="chip-bar">Home chips</ytm-chip-cloud-renderer></ytm-feed-filter-chip-bar-renderer>
          <div class="feed-filter-chip-bar" id="feedChips">All Home Videos</div>
          <ytm-rich-item-renderer><a href="/watch?v=abc123">A related video</a></ytm-rich-item-renderer>
        </div></ytm-app></body></html>
        """, baseURL: URL(string: "https://m.youtube.com/watch?v=abc123")!)
        try await waitForDocumentReady(web)
        let scriptURL = try XCTUnwrap(Bundle(for: AppBrowserSession.self).url(forResource: "ClearViewApps", withExtension: "js"))
        let source = try String(contentsOf: scriptURL, encoding: .utf8)
        _ = try await web.evaluateJavaScript("""
        var clearViewInitial={site:'youtube',appShell:true,active:true};
        \(source)
        window.__clearviewApps.update(clearViewInitial);
        true;
        """)
        let display: (String) async throws -> String = { selector in
            try await web.evaluateJavaScript("getComputedStyle(document.querySelector('\(selector)')).display") as! String
        }
        let visibleHeight: (String) async throws -> Double = { selector in
            try await web.evaluateJavaScript("document.querySelector('\(selector)').getBoundingClientRect().height") as! Double
        }
        for selector in ["ytm-related-chip-cloud-renderer", "ytm-feed-filter-chip-bar-renderer",
                         ".feed-filter-chip-bar"] {
            let value = try await display(selector)
            XCTAssertEqual(value, "none", "\(selector) must disappear with the app shell")
        }
        for selector in [".related-chips-slot-wrapper", "#related-chips-sentinel", "#filter-chip-bar"] {
            let value = try await display(selector)
            XCTAssertNotEqual(value, "none", "\(selector) is a layout slot, not a chip bar, and must stay")
        }
        for selector in ["#metadata", "#likes", "#comments"] {
            let value = try await display(selector)
            XCTAssertNotEqual(value, "none", "\(selector) must stay visible on a watch page")
            let height = try await visibleHeight(selector)
            XCTAssertGreaterThan(height, 0, "\(selector) must keep its layout height")
        }
        let card = try await display("ytm-rich-item-renderer")
        XCTAssertNotEqual(card, "none", "a related video must remain visible")
        _ = try await web.evaluateJavaScript("window.__clearviewApps.update({site:'youtube',appShell:false,active:true});true")
        for selector in ["ytm-related-chip-cloud-renderer", "ytm-feed-filter-chip-bar-renderer",
                         ".feed-filter-chip-bar"] {
            let value = try await display(selector)
            XCTAssertNotEqual(value, "none", "\(selector) must return when the app shell is disabled")
        }
    }

    /// YouTube's home feed autoplay previews rewrite labels and counters inside
    /// the playing card. Re-checking an already approved card would hide the
    /// video for a native round trip, which looks like a black flicker.
    func testApprovedFeedCardIsNotRehiddenWhenPreviewTextChanges() async throws {
        let collector = MessageCollector()
        let controller = WKUserContentController()
        controller.add(collector, name: "appsFilter")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        web.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0}ytm-rich-item-renderer{display:block}</style></head>
        <body><ytm-app><div class="page-container">
          <ytm-rich-item-renderer id="card"><a href="/watch?v=abc123">Quiet video</a><span id="meta">1 view</span></ytm-rich-item-renderer>
        </div></ytm-app></body></html>
        """, baseURL: URL(string: "https://m.youtube.com/")!)
        try await waitForDocumentReady(web)
        let scriptURL = try XCTUnwrap(Bundle(for: AppBrowserSession.self).url(forResource: "ClearViewApps", withExtension: "js"))
        let source = try String(contentsOf: scriptURL, encoding: .utf8)
        _ = try await web.evaluateJavaScript("""
        var clearViewInitial={site:'youtube',appShell:true,active:true};
        \(source)
        window.__clearviewApps.update(clearViewInitial);
        true;
        """)
        var scan: [String: Any]?
        for _ in 0..<100 {
            scan = collector.bodies.first { ($0["kind"] as? String) == "scan" }
            if scan != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let message = try XCTUnwrap(scan, "the card should be sent for its first verdict")
        let document = try XCTUnwrap(message["document"] as? String)
        let items = try XCTUnwrap(message["items"] as? [[String: Any]])
        let replies: [[String: Any]] = items.compactMap { item in
            guard let id = item["id"] as? String, let revision = item["revision"] as? Int else { return nil }
            return ["id": id, "revision": revision, "blocked": false]
        }
        let replyData = try JSONSerialization.data(withJSONObject: replies)
        let replyJSON = try XCTUnwrap(String(data: replyData, encoding: .utf8))
        let tokenData = try JSONEncoder().encode(document)
        let tokenJSON = try XCTUnwrap(String(data: tokenData, encoding: .utf8))
        _ = try await web.evaluateJavaScript("window.__clearviewApps.resolve(\(replyJSON), \(tokenJSON));true")
        let approved = try await web.evaluateJavaScript("!document.getElementById('card').hasAttribute('data-cv-review')") as? Bool
        XCTAssertEqual(approved, true, "the native verdict must reveal the approved card")

        _ = try await web.evaluateJavaScript("document.getElementById('meta').textContent='2 views';true")
        try await Task.sleep(for: .milliseconds(600))
        let stillVisible = try await web.evaluateJavaScript("""
        (()=>{const card=document.getElementById('card');
        return !card.hasAttribute('data-cv-review') && !card.hasAttribute('data-cv-hidden');})()
        """) as? Bool
        XCTAssertEqual(stillVisible, true, "changing only the preview metadata must not hide or re-review the card")
    }

    private func waitForDocumentReady(_ web: WKWebView) async throws {
        for _ in 0..<100 {
            let ready = try? await web.evaluateJavaScript("document.readyState === 'complete' && location.protocol === 'https:'") as? Bool
            if ready == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func youtubeFixture(_ html: String, path: String = "watch?v=sample",
                                size: CGSize = CGSize(width: 390, height: 844)) async throws -> WKWebView {
        let web = WKWebView(frame: CGRect(origin: .zero, size: size))
        web.loadHTMLString("<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><title>Sample video - YouTube</title></head><body style='margin:0'>\(html)</body></html>", baseURL: URL(string: "https://m.youtube.com/\(path)"))
        try await waitForDocumentReady(web)
        let url = try XCTUnwrap(Bundle(for: AppBrowserSession.self).url(forResource: "ClearViewApps", withExtension: "js"))
        let source = try String(contentsOf: url, encoding: .utf8)
        _ = try await web.evaluateJavaScript("var clearViewInitial={site:'youtube',appShell:true,active:true};\n" + source + "\nwindow.__clearviewApps.update(clearViewInitial);true;")
        return web
    }

    func testYouTubeFullscreenKeepsTitleAndSettingsForTheSameVideo() async throws {
        let web = try await youtubeFixture("""
        <div id="player-container-id"><div id="player"><video playsinline></video></div>
        <div id="player-control-overlay" class="fadein"><button class="fullscreen-button" aria-label="Enter full screen">Expand</button>
        <button id="settings" onclick="history.pushState(null,'','#settings')">Playback Settings</button></div></div>
        <ytm-slim-video-metadata-renderer><h1>A useful video title</h1></ytm-slim-video-metadata-renderer>
        """)
        _ = try await web.evaluateJavaScript("window.__clearviewApps.updateViewport(844,390);document.querySelector('.fullscreen-button').click();true")
        let title = try await web.evaluateJavaScript("document.getElementById('clearview-player-title').textContent") as? String
        XCTAssertEqual(title, "A useful video title")
        _ = try await web.evaluateJavaScript("document.getElementById('settings').click();window.__clearviewApps.update(clearViewInitial);true")
        let stillFullscreen = try await web.evaluateJavaScript("document.documentElement.hasAttribute('data-cv-player-fullscreen') && document.querySelector('.fullscreen-button').getAttribute('aria-label')==='Exit full screen'") as? Bool
        XCTAssertEqual(stillFullscreen, true, "a settings fragment must not close fullscreen or request portrait")
        _ = try await web.evaluateJavaScript("document.getElementById('player-control-overlay').className='fadeout';true")
        try await Task.sleep(for: .milliseconds(50))
        let hidden = try await web.evaluateJavaScript("document.getElementById('clearview-player-title').hidden") as? Bool
        XCTAssertEqual(hidden, true)
        _ = try await web.evaluateJavaScript("document.getElementById('player-control-overlay').className='fadein';true")
        try await Task.sleep(for: .milliseconds(50))
        let shown = try await web.evaluateJavaScript("!document.getElementById('clearview-player-title').hidden") as? Bool
        XCTAssertEqual(shown, true, "a tap showing playback controls must also reveal the title")
        _ = try await web.evaluateJavaScript("document.getElementById('player-control-overlay').insertAdjacentHTML('beforeend', '<button id=\"reveal\" aria-label=\"Show player controls\">Reveal</button>');true")
        try await Task.sleep(for: .milliseconds(50))
        let hiddenDuringPlayback = try await web.evaluateJavaScript("document.getElementById('clearview-player-title').hidden") as? Bool
        XCTAssertEqual(hiddenDuringPlayback, true, "the title must hide when the current mobile player replaces controls with its reveal button")
        _ = try await web.evaluateJavaScript("document.getElementById('reveal').setAttribute('aria-label','Hide player controls');true")
        try await Task.sleep(for: .milliseconds(50))
        let shownWithControls = try await web.evaluateJavaScript("!document.getElementById('clearview-player-title').hidden") as? Bool
        XCTAssertEqual(shownWithControls, true)
        _ = try await web.evaluateJavaScript("document.querySelector('video').dispatchEvent(new Event('play'));true")
        try await Task.sleep(for: .milliseconds(50))
        let hiddenWhenPlaybackStarts = try await web.evaluateJavaScript("document.getElementById('clearview-player-title').hidden") as? Bool
        XCTAssertEqual(hiddenWhenPlaybackStarts, true, "starting playback must hide the title even while the controls are visible")
        _ = try await web.evaluateJavaScript("document.querySelector('video').dispatchEvent(new Event('pause'));true")
        try await Task.sleep(for: .milliseconds(50))
        let shownWhenPaused = try await web.evaluateJavaScript("!document.getElementById('clearview-player-title').hidden") as? Bool
        XCTAssertEqual(shownWhenPaused, true, "pausing should bring the title back with the controls")
        _ = try await web.evaluateJavaScript("history.pushState(null,'','/watch?v=another');window.__clearviewApps.update(clearViewInitial);true")
        let exited = try await web.evaluateJavaScript("!document.getElementById('clearview-player-title') && !document.documentElement.hasAttribute('data-cv-player-fullscreen')") as? Bool
        XCTAssertEqual(exited, true, "switching to a different video must restore the normal page")
    }

    /// YouTube renders the player settings inside its new bottom-sheet layout.
    /// That host collapses to the drag handle once the menu is positioned out
    /// of flow, and keeps `overflow:hidden`, which used to clip the settings to
    /// a strip at the bottom of a landscape player. Hit-testing the menu center
    /// is the honest check: a clipped menu can still exist in the document.
    func testYouTubeFullscreenSettingsEscapeTheCollapsedBottomSheetHost() async throws {
        let web = try await youtubeFixture("""
        <div id="player-container-id"><div id="player"><video playsinline></video></div>
        <div id="player-control-overlay" class="fadein"><button class="fullscreen-button" aria-label="Enter full screen">Expand</button></div></div>
        <bottom-sheet-container role="dialog" style="position:fixed;left:62px;top:0;width:750px;height:0">
          <div class="ytSpecBottomSheetLayoutHost ytSpecBottomSheetLayoutContainer ytSpecBottomSheetLayoutModern" style="position:fixed;left:237px;top:357px;width:400px;height:21px;overflow:hidden">
            <div class="ytSpecBottomSheetLayoutBottomSheetContent">
              <div class="ytSpecBottomSheetLayoutContentWrapper" style="overflow:auto">
                <player-settings-menu role="menu" style="position:static;width:400px;height:378px">
                  <button id="quality" style="position:absolute;inset:0;width:100%;height:100%">Quality 360p</button>
                </player-settings-menu>
              </div>
            </div>
          </div>
        </bottom-sheet-container>
        """, size: CGSize(width: 874, height: 402))
        _ = try await web.evaluateJavaScript("window.__clearviewApps.updateViewport(874,402);document.querySelector('.fullscreen-button').click();true")
        let hit = try await web.evaluateJavaScript("""
        (() => {
          const button = document.getElementById('quality');
          const rect = button.getBoundingClientRect();
          const atCenter = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
          return { hit: atCenter === button, rect: [rect.x, rect.y, rect.width, rect.height] };
        })()
        """) as? [String: Any]
        XCTAssertEqual(hit?["hit"] as? Bool, true,
                       "the settings menu must stay clickable when the fullscreen bottom-sheet host collapses")
    }

    func testYouTubeCommentsReachThePlayerAndSubscribedButtonHasALabel() async throws {
        let web = try await youtubeFixture("""
        <div id="player-container-id" style="height:220px"><video></video></div>
        <ytm-subscribe-button-renderer class="is-subscribed"><button id="subscribed" style="width:20px" onclick="window.notificationOpened=true"><svg width="16" height="16"></svg></button></ytm-subscribe-button-renderer>
        <ytm-engagement-panel id="comments" style="position:fixed;top:268px;height:400px;width:100%">
        <ytm-engagement-panel-section-list-renderer class="engagement-panel-comments-section">Comments</ytm-engagement-panel-section-list-renderer>
        </ytm-engagement-panel>
        """)
        let top = try await web.evaluateJavaScript("document.getElementById('comments').getBoundingClientRect().top") as! Double
        XCTAssertEqual(top, 220, accuracy: 0.5, "comments must start at the video's bottom, covering the metadata")
        let label = try await web.evaluateJavaScript("document.getElementById('subscribed').textContent.trim()") as? String
        XCTAssertEqual(label, "Subscribed")
        _ = try await web.evaluateJavaScript("window.__clearviewApps.update(clearViewInitial);document.getElementById('subscribed').click();true")
        let intact = try await web.evaluateJavaScript("window.notificationOpened===true && document.querySelectorAll('[data-cv-subscription-label]').length===1 && document.getElementById('subscribed').getBoundingClientRect().width>=104") as? Bool
        XCTAssertEqual(intact, true, "a readable subscribed control must retain its original notification action")
        _ = try await web.evaluateJavaScript("document.getElementById('comments').style.visibility='hidden';window.__clearviewApps.update(clearViewInitial);true")
        let closed = try await web.evaluateJavaScript("!document.getElementById('comments').hasAttribute('data-cv-comments-panel')") as? Bool
        XCTAssertEqual(closed, true)
    }

    func testYouTubeShortsMenuHidesOpenInAppOnly() async throws {
        let web = try await youtubeFixture("""
        <div role="dialog"><ytm-menu-navigation-item-renderer id="open"><button><span>Open in app</span></button></ytm-menu-navigation-item-renderer>
        <button id="share">Share</button><button id="report">Report</button></div>
        """, path: "shorts/sample")
        let hidden = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('open')).display==='none' && getComputedStyle(document.getElementById('share')).display!=='none' && getComputedStyle(document.getElementById('report')).display!=='none'") as? Bool
        XCTAssertEqual(hidden, true, "remove the app handoff without losing other Shorts menu actions")
    }

}

@MainActor
private final class MessageCollector: NSObject, WKScriptMessageHandler {
    var bodies: [[String: Any]] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { bodies.append(body) }
    }
}
