import AppKit

/// Apple Music + Spotify. Track/state arrive as system notifications (no polling).
/// Controls and Apple Music artwork use AppleScript (needs Automation permission, asked on first use).
final class MusicManager: ObservableObject {
    enum Source {
        case appleMusic, spotify
        var appName: String { self == .appleMusic ? "Music" : "Spotify" }
        var bundleID: String { self == .appleMusic ? "com.apple.Music" : "com.spotify.client" }
    }
    struct Track: Equatable {
        var id: String; var title: String; var artist: String; var album: String; var duration: TimeInterval
        var isAd = false
    }

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    private(set) var source: Source?
    var onPlayingChanged: (() -> Void)?

    private var posValue: TimeInterval = 0
    private var posDate = Date()
    private var artworkCache: [String: NSImage] = [:]
    private var pollTimer: Timer?

    func start() {
        let dnc = DistributedNotificationCenter.default()
        for n in ["com.apple.Music.playerInfo", "com.apple.iTunes.playerInfo"] {
            dnc.addObserver(self, selector: #selector(appleMusicEvent(_:)), name: Notification.Name(n), object: nil)
        }
        dnc.addObserver(self, selector: #selector(spotifyEvent(_:)),
                        name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self,
                  let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self.source?.bundleID else { return }
            self.clear()
        }
    }

    @objc private func appleMusicEvent(_ n: Notification) { handle(n.userInfo, source: .appleMusic) }
    @objc private func spotifyEvent(_ n: Notification) { handle(n.userInfo, source: .spotify) }

    private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    private func handle(_ info: [AnyHashable: Any]?, source: Source) {
        guard Settings.shared.musicEnabled, let info else { return }
        let state = (info["Player State"] as? String) ?? ""
        if state == "Stopped" { if self.source == source { clear() }; return }

        let title = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        let ms = num(info["Total Time"]) ?? num(info["Duration"]) ?? 0
        let id = (info["Track ID"] as? String) ?? info["Persistent ID"].map { "\($0)" } ?? "\(title)|\(artist)|\(album)"
        let isAd = source == .spotify && (id.hasPrefix("spotify:ad") || (title.isEmpty && artist.isEmpty))
        let newTrack = Track(id: id, title: isAd ? "Advertisement" : title, artist: isAd ? "Spotify" : artist,
                             album: album, duration: ms / 1000, isAd: isAd)
        let changed = newTrack != track

        self.source = source
        track = newTrack
        if source == .spotify, let p = num(info["Playback Position"]) {
            posValue = p; posDate = Date()
        } else {
            if changed { posValue = 0 }
            posDate = Date()
        }
        setPlaying(state == "Playing")
        if source == .appleMusic { queryAppleMusicPosition() }
        if changed { loadArtwork(for: newTrack, source: source) }
    }

    private func setPlaying(_ v: Bool) {
        if isPlaying != v {
            isPlaying = v
            onPlayingChanged?()
        }
        updatePolling()
    }

    // Spotify does not always announce ads or track changes, so while Spotify is playing we ask it
    // directly every 4 seconds (a tiny local AppleScript call; stops as soon as playback stops).
    private func updatePolling() {
        let need = isPlaying && source == .spotify
        if need && pollTimer == nil {
            let t = Timer(timeInterval: 4, repeats: true) { [weak self] _ in self?.pollSpotify() }
            t.tolerance = 1
            RunLoop.main.add(t, forMode: .common)
            pollTimer = t
        } else if !need {
            pollTimer?.invalidate(); pollTimer = nil
        }
    }

    private func pollSpotify() {
        guard source == .spotify, isRunning(.spotify) else { return }
        let script = """
        tell application "Spotify"
            set sep to (ASCII character 31)
            set st to player state as string
            set t to current track
            return st & sep & (id of t) & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (duration of t) & sep & (player position)
        end tell
        """
        guard let raw = run(script)?.stringValue else { return }
        let p = raw.components(separatedBy: "\u{1F}")
        guard p.count >= 7 else { return }
        let id = p[1], name = p[2], artist = p[3], album = p[4]
        let dur = (Double(p[5]) ?? 0) / 1000
        let pos = Double(p[6].replacingOccurrences(of: ",", with: ".")) ?? 0
        let isAd = id.hasPrefix("spotify:ad") || (name.isEmpty && artist.isEmpty)
        let newTrack = Track(id: id, title: isAd ? "Advertisement" : name, artist: isAd ? "Spotify" : artist,
                             album: album, duration: dur, isAd: isAd)
        let changed = newTrack != track
        if changed { track = newTrack }
        posValue = pos; posDate = Date()
        setPlaying(p[0].lowercased() == "playing")
        if changed { loadArtwork(for: newTrack, source: .spotify) }
    }

    func clear() {
        track = nil; artwork = nil; source = nil
        setPlaying(false)
        onPlayingChanged?()
    }

    func currentPosition(at date: Date) -> TimeInterval {
        let p = isPlaying ? posValue + date.timeIntervalSince(posDate) : posValue
        let d = track?.duration ?? 0
        return d > 0 ? min(max(p, 0), d) : max(p, 0)
    }

    // MARK: Controls

    func playPause() {
        let pos = currentPosition(at: Date())
        send("playpause")
        posValue = pos; posDate = Date()
        setPlaying(!isPlaying)           // optimistic; the real state arrives as a notification
    }
    func next() { send("next track") }
    func previous() { send("previous track") }

    private func send(_ command: String) {
        guard let s = source, isRunning(s) else { return }
        _ = run("tell application \"\(s.appName)\" to \(command)")
    }

    // MARK: AppleScript helpers

    private func isRunning(_ s: Source) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: s.bundleID).isEmpty
    }

    @discardableResult
    private func run(_ script: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        let r = NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err { NSLog("DynamicIsland AppleScript error: \(err)") }
        return r
    }

    private func queryAppleMusicPosition() {
        guard let s = source, s == .appleMusic, isRunning(s) else { return }
        if let d = run("tell application \"Music\" to get player position"),
           let str = d.stringValue,
           let v = Double(str.replacingOccurrences(of: ",", with: ".")) {
            posValue = v; posDate = Date()
        }
    }

    private func loadArtwork(for t: Track, source: Source) {
        if t.isAd { artwork = nil; return }
        if let cached = artworkCache[t.id] { artwork = cached; return }
        artwork = nil
        switch source {
        case .appleMusic:
            guard isRunning(source),
                  let d = run("tell application \"Music\" to get data of artwork 1 of current track"),
                  let img = NSImage(data: d.data) else { return }
            setArtwork(img, id: t.id)
        case .spotify:
            guard isRunning(source),
                  let s = run("tell application \"Spotify\" to get artwork url of current track")?.stringValue,
                  let url = URL(string: s) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { self?.setArtwork(img, id: t.id) }
            }.resume()
        }
    }

    private func setArtwork(_ img: NSImage, id: String) {
        let small = img.resized(to: 160)           // keep RAM tiny
        if artworkCache.count > 8 { artworkCache.removeAll() }
        artworkCache[id] = small
        if track?.id == id { artwork = small }
    }
}

extension NSImage {
    func resized(to side: CGFloat) -> NSImage {
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}
