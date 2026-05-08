import Cocoa
import AVFoundation

// MARK: - Config

struct TimerConfig: Codable {
    var buttons: [Int]
    var soundName: String
    var chimeEnabled: Bool

    static let `default` = TimerConfig(buttons: [5, 20, 30, 60], soundName: "Glass", chimeEnabled: true)

    init(buttons: [Int], soundName: String = "Glass", chimeEnabled: Bool = true) {
        self.buttons = buttons
        self.soundName = soundName
        self.chimeEnabled = chimeEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buttons      = try  c.decode([Int].self,    forKey: .buttons)
        soundName    = (try? c.decode(String.self,  forKey: .soundName))    ?? "Glass"
        chimeEnabled = (try? c.decode(Bool.self,    forKey: .chimeEnabled)) ?? true
    }
}

final class ConfigManager {
    static let shared = ConfigManager()
    private init() {}

    private var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sprint-timer/config.json")
    }

    func load() -> TimerConfig {
        guard let data = try? Data(contentsOf: url),
              let cfg  = try? JSONDecoder().decode(TimerConfig.self, from: data),
              cfg.buttons.count == 4
        else { return .default }
        return cfg
    }

    func save(_ cfg: TimerConfig) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(cfg) { try? data.write(to: url) }
    }
}

// MARK: - App entry

private class SprintPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.setActivationPolicy(.accessory)
        let rect = NSRect(x: 0, y: 0, width: 300, height: 340)
        window = SprintPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.delegate = self
        window.setFrameAutosaveName("SprintTimerMainWindow")
        if !window.setFrameUsingName("SprintTimerMainWindow") {
            window.center()
        }
        window.contentViewController = TimerViewController()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

// MARK: - Custom dark button

class DarkButton: NSView {
    private let label   = NSTextField(labelWithString: "")
    private let surface = NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
    private let hovered = NSColor(red: 0.23, green: 0.23, blue: 0.25, alpha: 1)
    private let bright  = NSColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1)
    var action: (() -> Void)?

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    var minutes: Int = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let fraction = min(Double(minutes), 60.0) / 60.0
        guard fraction > 0 else { return }
        NSColor(white: 0, alpha: 0.25).setFill()
        if fraction >= 1.0 {
            NSBezierPath(ovalIn: bounds).fill()
        } else {
            let c = CGPoint(x: bounds.midX, y: bounds.midY)
            let r = min(bounds.width, bounds.height) / 2
            let pie = NSBezierPath()
            pie.move(to: c)
            pie.appendArc(withCenter: c, radius: r,
                          startAngle: 90, endAngle: CGFloat(90 - fraction * 360),
                          clockwise: true)
            pie.close()
            pie.fill()
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = surface.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        label.stringValue = title
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = bright
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = hovered.cgColor }
    override func mouseExited(with event: NSEvent)  { layer?.backgroundColor = surface.cgColor }
    @objc private func tapped() { action?() }
}

// MARK: - Chime engine

class ChimePlayer {
    private var players: [AVAudioPlayer] = []

    func playDoubleChime(sound: String) {
        let url = Bundle.main.url(forResource: sound, withExtension: "aiff")
            ?? URL(fileURLWithPath: "/System/Library/Sounds/\(sound).aiff")
        playAt(url, delay: 0)
        playAt(url, delay: 0.55)
    }

    private func playAt(_ url: URL, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
            player.volume = 0.8
            player.play()
            self?.players.append(player)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.players.removeAll { !$0.isPlaying }
            }
        }
    }
}

// MARK: - State

enum TimerPhase { case select, running, overtime }

// MARK: - ViewController

class TimerViewController: NSViewController {

    private let titleLabel   = NSTextField(labelWithString: "")
    private let ringView     = RingView()
    private let timeLabel    = NSTextField(labelWithString: "00:00")
    private let overLabel    = NSTextField(labelWithString: "")
    private let pauseBtn     = NSButton()
    private let resetBtn     = NSButton()
    private let chimeToggle  = NSButton()
    private let settingsBtn  = NSButton()
    private let selectStack  = NSStackView()
    private let timerStack   = NSStackView()

    private var phase       : TimerPhase = .select
    private var totalSecs   = 0
    private var remaining   = 0
    private var overtime    = 0
    private var isPaused    = false
    private lazy var chimeOn: Bool = config.chimeEnabled
    private var ticker      : Timer?
    private var pulseTimer  : Timer?
    private var pulsePhase  = false

    private let chime = ChimePlayer()

    private let bg         = NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
    private let pulseBg    = NSColor(red: 0.28, green: 0.06, blue: 0.06, alpha: 1)
    private let accent     = NSColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1)
    private let dimText    = NSColor(red: 0.38, green: 0.38, blue: 0.40, alpha: 1)
    private let bright     = NSColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1)

    private var config              = ConfigManager.shared.load()
    private var selBtns             : [DarkButton] = []
    private var settingsOverlay     : NSView!
    private var settingsFields      : [NSTextField] = []
    private var soundPopup          : NSPopUpButton!
    private var chimeDefaultToggle  : NSButton!
    private var previewPlayer       : AVAudioPlayer?
    private var escMonitor          : Any?
    private var customField         : NSTextField!

    private let systemSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
                                 "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
                                 "Submarine", "Tink"]

    override func loadView() {
        view = ContentView(frame: NSRect(x: 0, y: 0, width: 300, height: 340))
        view.wantsLayer = true
        view.layer?.backgroundColor = bg.cgColor
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildSelectView()
        buildTimerView()
        buildChimeToggle()
        buildSettingsButton()
        buildSettingsOverlay()

        [titleLabel, selectStack, timerStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = dimText
        titleLabel.alignment = .center

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            timerStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 10),
        ])

        // overlay above main content; controls always on top of overlay
        view.addSubview(settingsOverlay)
        view.addSubview(chimeToggle)
        view.addSubview(settingsBtn)

        showSelect()
    }

    // MARK: - Chime toggle

    private func buildChimeToggle() {
        chimeToggle.translatesAutoresizingMaskIntoConstraints = false
        chimeToggle.isBordered = false
        chimeToggle.bezelStyle = .regularSquare
        chimeToggle.wantsLayer = true
        chimeToggle.layer?.backgroundColor = NSColor.clear.cgColor
        chimeToggle.title = ""
        chimeToggle.imagePosition = .imageOnly
        chimeToggle.target = self
        chimeToggle.action = #selector(toggleChime)
        chimeToggle.widthAnchor.constraint(equalToConstant: 22).isActive = true
        chimeToggle.heightAnchor.constraint(equalToConstant: 22).isActive = true
        view.addSubview(chimeToggle)
        NSLayoutConstraint.activate([
            chimeToggle.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            chimeToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
        updateChimeIcon()
    }

    private func updateChimeIcon() {
        let sfName = chimeOn ? "bell.fill" : "bell.slash.fill"
        if let img = NSImage(systemSymbolName: sfName, accessibilityDescription: chimeOn ? "Chime on" : "Chime off") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .light)
            chimeToggle.image = img.withSymbolConfiguration(cfg)
            chimeToggle.contentTintColor = chimeOn ? dimText.withAlphaComponent(1) : dimText.withAlphaComponent(0.4)
        }
        chimeToggle.toolTip = chimeOn ? "Chime on" : "Chime off"
    }

    @objc private func toggleChime() {
        chimeOn = !chimeOn
        updateChimeIcon()
    }

    // MARK: - Settings button

    private func buildSettingsButton() {
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false
        settingsBtn.isBordered = false
        settingsBtn.bezelStyle = .regularSquare
        settingsBtn.wantsLayer = true
        settingsBtn.layer?.backgroundColor = NSColor.clear.cgColor
        settingsBtn.title = ""
        settingsBtn.imagePosition = .imageOnly
        settingsBtn.target = self
        settingsBtn.action = #selector(openSettings)
        settingsBtn.widthAnchor.constraint(equalToConstant: 22).isActive = true
        settingsBtn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        if let img = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .light)
            settingsBtn.image = img.withSymbolConfiguration(cfg)
            settingsBtn.contentTintColor = dimText
        }
        settingsBtn.toolTip = "Settings"
        view.addSubview(settingsBtn)
        NSLayoutConstraint.activate([
            settingsBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            settingsBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        ])
    }

    private func buildSettingsOverlay() {
        settingsOverlay = NSView()
        settingsOverlay.wantsLayer = true
        settingsOverlay.layer?.backgroundColor = bg.cgColor
        settingsOverlay.appearance = NSAppearance(named: .darkAqua)
        settingsOverlay.alphaValue = 0
        settingsOverlay.isHidden = true
        settingsOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(settingsOverlay)
        NSLayoutConstraint.activate([
            settingsOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            settingsOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            settingsOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            settingsOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Button durations section
        settingsFields = []
        let buttonRows = (0..<4).map { makeSettingsRow(index: $0) }

        // Sound section
        let soundLbl = NSTextField(labelWithString: "Sound")
        soundLbl.font = .systemFont(ofSize: 13)
        soundLbl.textColor = bright
        soundLbl.widthAnchor.constraint(equalToConstant: 64).isActive = true

        soundPopup = NSPopUpButton()
        soundPopup.addItems(withTitles: systemSounds)
        soundPopup.selectItem(withTitle: config.soundName)
        soundPopup.target = self
        soundPopup.action = #selector(previewSound)
        soundPopup.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let soundRow = NSStackView(views: [soundLbl, soundPopup])
        soundRow.orientation = .horizontal
        soundRow.spacing = 8

        chimeDefaultToggle = NSButton(checkboxWithTitle: "On by default", target: self, action: #selector(chimeDefaultChanged))
        chimeDefaultToggle.state = chimeOn ? .on : .off

        let contentStack = NSStackView(views:
            [sectionHeader("BUTTON DURATIONS")] + buttonRows +
            [sectionHeader("SOUND"), soundRow, chimeDefaultToggle]
        )
        contentStack.orientation = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .leading
        contentStack.setCustomSpacing(10, after: contentStack.arrangedSubviews[0])
        contentStack.setCustomSpacing(14, after: buttonRows.last!)
        contentStack.setCustomSpacing(8,  after: contentStack.arrangedSubviews[5])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        settingsOverlay.addSubview(contentStack)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveBtn.bezelStyle = .rounded
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        settingsOverlay.addSubview(saveBtn)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: settingsOverlay.topAnchor, constant: 30),
            contentStack.centerXAnchor.constraint(equalTo: settingsOverlay.centerXAnchor),
            saveBtn.topAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: 14),
            saveBtn.centerXAnchor.constraint(equalTo: settingsOverlay.centerXAnchor),
        ])
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: title)
        lbl.font = .systemFont(ofSize: 10, weight: .semibold)
        lbl.textColor = dimText
        return lbl
    }

    @objc private func chimeDefaultChanged() {
        chimeOn = chimeDefaultToggle.state == .on
        updateChimeIcon()
    }

    @objc private func previewSound() {
        guard let name = soundPopup.titleOfSelectedItem else { return }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        previewPlayer = try? AVAudioPlayer(contentsOf: url)
        previewPlayer?.volume = 0.8
        previewPlayer?.play()
    }

    private func makeSettingsRow(index: Int) -> NSView {
        let lbl = NSTextField(labelWithString: "Button \(index + 1)")
        lbl.font = .systemFont(ofSize: 13)
        lbl.textColor = bright
        lbl.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let field = NSTextField()
        field.stringValue = "\(config.buttons[index])"
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.alignment = .center
        field.widthAnchor.constraint(equalToConstant: 48).isActive = true
        settingsFields.append(field)

        let unit = NSTextField(labelWithString: "min")
        unit.font = .systemFont(ofSize: 13)
        unit.textColor = dimText

        let row = NSStackView(views: [lbl, field, unit])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    @objc private func openSettings() {
        let opening = settingsOverlay.isHidden
        if opening {
            for (i, f) in settingsFields.enumerated() { f.stringValue = "\(config.buttons[i])" }
            chimeDefaultToggle.state = chimeOn ? .on : .off
            settingsOverlay.isHidden = false
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.openSettings(); return nil }
                return event
            }
        } else {
            if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            settingsOverlay.animator().alphaValue = opening ? 1 : 0
        } completionHandler: { [weak self] in
            if !opening { self?.settingsOverlay.isHidden = true }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if !settingsOverlay.isHidden { openSettings() }
    }

    @objc private func saveSettings() {
        var newButtons: [Int] = []
        for field in settingsFields {
            guard let v = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), v > 0 else {
                NSSound.beep()
                return
            }
            newButtons.append(v)
        }
        config = TimerConfig(
            buttons: newButtons,
            soundName: soundPopup.titleOfSelectedItem ?? config.soundName,
            chimeEnabled: chimeDefaultToggle.state == .on
        )
        ConfigManager.shared.save(config)
        refreshSelectButtons()
        openSettings()
    }

    // MARK: - Select grid

    private func buildSelectView() {
        selBtns = config.buttons.map { mins in
            let btn = DarkButton(title: "\(mins)")
            btn.minutes = mins
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 80).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 80).isActive = true
            btn.action = { [weak self] in self?.startTimer(mins) }
            return btn
        }
        let row1 = hrow(selBtns[0], selBtns[1])
        let row2 = hrow(selBtns[2], selBtns[3])

        let customView = CustomTimerView()
        customView.translatesAutoresizingMaskIntoConstraints = false
        // match the width of the two-button rows exactly
        customView.widthAnchor.constraint(equalToConstant: 176).isActive = true
        customView.heightAnchor.constraint(equalToConstant: 44).isActive = true
        customField = customView.field
        customField.textColor = bright
        customField.font = .systemFont(ofSize: 17, weight: .medium)
        customField.alignment = .center
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        customField.placeholderAttributedString = NSAttributedString(
            string: "custom",
            attributes: [.foregroundColor: dimText,
                         .font: NSFont.systemFont(ofSize: 17, weight: .medium),
                         .paragraphStyle: para]
        )
        customField.target = self
        customField.action = #selector(runCustomTimer)

        selectStack.orientation = .vertical
        selectStack.spacing = 16
        selectStack.addArrangedSubview(row1)
        selectStack.addArrangedSubview(row2)
        selectStack.addArrangedSubview(customView)
    }

    @objc private func runCustomTimer() {
        guard let mins = Int(customField.stringValue.trimmingCharacters(in: .whitespaces)),
              mins > 0 else {
            NSSound.beep()
            return
        }
        customField.stringValue = ""
        view.window?.makeFirstResponder(nil)
        startTimer(mins)
    }

    private func hrow(_ a: NSView, _ b: NSView) -> NSStackView {
        let s = NSStackView(views: [a, b])
        s.orientation = .horizontal
        s.spacing = 16
        return s
    }

    private func refreshSelectButtons() {
        for (i, btn) in selBtns.enumerated() {
            let mins = config.buttons[i]
            btn.title = "\(mins)"
            btn.minutes = mins
            btn.action = { [weak self] in self?.startTimer(mins) }
        }
    }

    // MARK: - Timer view

    private func buildTimerView() {
        ringView.translatesAutoresizingMaskIntoConstraints = false
        ringView.accentColor = accent
        ringView.widthAnchor.constraint(equalToConstant: 230).isActive = true
        ringView.heightAnchor.constraint(equalToConstant: 230).isActive = true

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 44, weight: .thin)
        timeLabel.textColor = bright
        timeLabel.alignment = .center

        overLabel.font = .systemFont(ofSize: 11, weight: .medium)
        overLabel.textColor = accent
        overLabel.alignment = .center
        overLabel.stringValue = ""

        buildIconBtn(pauseBtn, sfName: "pause.fill", tip: "Pause")
        pauseBtn.target = self
        pauseBtn.action = #selector(togglePause)

        buildIconBtn(resetBtn, sfName: "arrow.counterclockwise", tip: "Reset")
        resetBtn.target = self
        resetBtn.action = #selector(resetTimer)

        let btnRow = NSStackView(views: [pauseBtn, resetBtn])
        btnRow.orientation = .horizontal
        btnRow.spacing = 20

        let inner = NSStackView(views: [timeLabel, overLabel, btnRow])
        inner.orientation = .vertical
        inner.spacing = 10
        inner.alignment = .centerX
        inner.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(ringView)
        container.addSubview(inner)

        NSLayoutConstraint.activate([
            ringView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            ringView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ringView.topAnchor.constraint(equalTo: container.topAnchor),
            ringView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            inner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        container.widthAnchor.constraint(equalToConstant: 230).isActive = true
        container.heightAnchor.constraint(equalToConstant: 230).isActive = true

        timerStack.orientation = .vertical
        timerStack.spacing = 0
        timerStack.alignment = .centerX
        timerStack.addArrangedSubview(container)
    }

    private func buildIconBtn(_ btn: NSButton, sfName: String, tip: String) {
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.clear.cgColor
        btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        btn.title = ""
        btn.imagePosition = .imageOnly
        applyIcon(btn, sfName: sfName, tip: tip)
    }

    private func applyIcon(_ btn: NSButton, sfName: String, tip: String) {
        if let img = NSImage(systemSymbolName: sfName, accessibilityDescription: tip) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .light)
            btn.image = img.withSymbolConfiguration(cfg)
            btn.contentTintColor = dimText
        }
        btn.toolTip = tip
    }

    // MARK: - Actions

    private func startTimer(_ mins: Int) {
        totalSecs = mins * 60
        remaining = totalSecs
        overtime  = 0
        isPaused  = false
        phase     = .running

        stopPulse()
        view.layer?.backgroundColor = bg.cgColor

        titleLabel.stringValue = "\(mins) MINUTE TIMER"
        timeLabel.stringValue  = fmt(remaining)
        overLabel.stringValue  = ""
        ringView.setProgress(1.0, overtime: false)
        applyIcon(pauseBtn, sfName: "pause.fill", tip: "Pause")

        showTimer()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    @objc private func togglePause() {
        isPaused = !isPaused
        applyIcon(pauseBtn,
                  sfName: isPaused ? "play.fill" : "pause.fill",
                  tip:    isPaused ? "Resume"    : "Pause")
    }

    @objc private func resetTimer() {
        ticker?.invalidate()
        ticker = nil
        stopPulse()
        view.layer?.backgroundColor = bg.cgColor
        phase = .select
        titleLabel.stringValue = ""
        showSelect()
    }

    private func tick() {
        guard !isPaused else { return }
        if phase == .running {
            remaining -= 1
            timeLabel.stringValue = fmt(remaining)
            ringView.setProgress(Double(remaining) / Double(totalSecs), overtime: false)
            if remaining <= 0 {
                phase = .overtime
                overtime = 0
                ringView.setProgress(0, overtime: true)
                overLabel.stringValue = "+00:00 OVER"
                onExpiry()
            }
        } else if phase == .overtime {
            overtime += 1
            overLabel.stringValue = "+\(fmt(overtime)) OVER"
        }
    }

    private func onExpiry() {
        if chimeOn { chime.playDoubleChime(sound: config.soundName) }
        startPulse()
    }

    // MARK: - Pulse

    private func startPulse() {
        pulsePhase = false
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pulseTick()
        }
        pulseTick()
    }

    private func pulseTick() {
        pulsePhase = !pulsePhase
        let target = pulsePhase ? pulseBg : bg
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.8
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.view.animator().layer?.backgroundColor = target.cgColor
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulsePhase = false
    }

    // MARK: - Helpers

    private func fmt(_ s: Int) -> String {
        String(format: "%02d:%02d", abs(s) / 60, abs(s) % 60)
    }

    private func showSelect() {
        selectStack.isHidden = false
        timerStack.isHidden = true
        view.window?.makeFirstResponder(nil)
    }
    private func showTimer()  { selectStack.isHidden = true;  timerStack.isHidden = false }
}

// MARK: - Segmented Ring

class RingView: NSView {
    var accentColor = NSColor.systemRed
    private var progress: Double = 1.0
    private var isOvertime = false

    override var isFlipped: Bool { true }

    func setProgress(_ p: Double, overtime: Bool) {
        progress   = max(0, min(1, p))
        isOvertime = overtime
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let center    = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius    = min(bounds.width, bounds.height) / 2 - 14
        let lineWidth : CGFloat = 11
        let segments  = 36
        let gapDeg    : CGFloat = 7.0
        let segDeg    = 360.0 / CGFloat(segments)
        let drawDeg   = segDeg - gapDeg

        let filledCount = isOvertime ? 0 : Int(round(progress * Double(segments)))
        let trackColor  = NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1)

        for i in 0..<segments {
            let startDeg = -90.0 + CGFloat(i) * segDeg + gapDeg / 2
            let endDeg   = startDeg + drawDeg
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius,
                           startAngle: startDeg, endAngle: endDeg, clockwise: false)
            path.lineWidth = lineWidth
            path.lineCapStyle = .butt
            if i < filledCount {
                let t = Double(i) / Double(max(filledCount - 1, 1))
                accentColor.withAlphaComponent(0.35 + 0.65 * t).setStroke()
            } else {
                trackColor.setStroke()
            }
            path.stroke()
        }
    }
}

// MARK: - Custom timer input

class CustomTimerView: NSView {
    let field = NSTextField()
    private let surface = NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
    private let hovered = NSColor(red: 0.23, green: 0.23, blue: 0.25, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = surface.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor

        field.drawsBackground = false
        field.isBezeled = false
        field.isBordered = false
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = hovered.cgColor }
    override func mouseExited(with event: NSEvent)  { layer?.backgroundColor = surface.cgColor }
}

// MARK: - Content view

private class ContentView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)
        super.mouseDown(with: event)
    }
}
