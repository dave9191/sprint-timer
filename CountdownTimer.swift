import Cocoa
import AVFoundation
import Carbon

// MARK: - Config

struct HotkeyDef: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon modifier flags
}

struct TimerConfig: Codable {
    var buttons: [Int]
    var soundName: String
    var chimeEnabled: Bool
    var showCustomInput: Bool
    var hotkeys: [HotkeyDef?]

    static let `default` = TimerConfig(
        buttons: [5, 20, 30, 60],
        soundName: "Glass",
        chimeEnabled: true,
        showCustomInput: false,
        hotkeys: Array(repeating: nil, count: 6)
    )

    init(buttons: [Int], soundName: String = "Glass", chimeEnabled: Bool = true,
         showCustomInput: Bool = false, hotkeys: [HotkeyDef?] = Array(repeating: nil, count: 6)) {
        self.buttons        = buttons
        self.soundName      = soundName
        self.chimeEnabled   = chimeEnabled
        self.showCustomInput = showCustomInput
        self.hotkeys        = hotkeys
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buttons         = try  c.decode([Int].self,    forKey: .buttons)
        soundName       = (try? c.decode(String.self,  forKey: .soundName))       ?? "Glass"
        chimeEnabled    = (try? c.decode(Bool.self,    forKey: .chimeEnabled))    ?? true
        showCustomInput = (try? c.decode(Bool.self,    forKey: .showCustomInput)) ?? false
        let decoded     = (try? c.decode([HotkeyDef?].self, forKey: .hotkeys))    ?? []
        var hk: [HotkeyDef?] = Array(repeating: nil, count: 6)
        for (i, v) in decoded.prefix(6).enumerated() { hk[i] = v }
        hotkeys = hk
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

// MARK: - Global hotkey manager

private func carbonHotkeyDispatch(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event, let userData = userData else { return noErr }
    var hkID = EventHotKeyID()
    GetEventParameter(event,
                      EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().fire(id: hkID.id)
    return noErr
}

final class HotkeyManager {
    static let shared = HotkeyManager()
    private var handlerRef: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: () -> Void] = [:]

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyDispatch,
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    func registerAll(_ entries: [(keyCode: UInt32, modifiers: UInt32, action: () -> Void)]) {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        callbacks.removeAll()
        for (i, entry) in entries.enumerated() {
            let id = UInt32(i + 1)
            let hkID = EventHotKeyID(signature: OSType(0x53504854), id: id)
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(entry.keyCode, entry.modifiers, hkID,
                                   GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref = ref {
                refs[id] = ref
                callbacks[id] = entry.action
            }
        }
    }

    func fire(id: UInt32) {
        DispatchQueue.main.async { self.callbacks[id]?() }
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
    private var customTimerView     : CustomTimerView!
    private var customInputToggle   : NSButton!
    private var hotkeyFields        : [HotkeyField] = []

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
        registerHotkeys()
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        let btns = config.buttons
        let actions: [() -> Void] = [
            { [weak self] in self?.startTimer(btns[0]) },
            { [weak self] in self?.startTimer(btns[1]) },
            { [weak self] in self?.startTimer(btns[2]) },
            { [weak self] in self?.startTimer(btns[3]) },
            { [weak self] in self?.togglePause() },
            { [weak self] in self?.resetTimer() },
        ]
        let entries: [(keyCode: UInt32, modifiers: UInt32, action: () -> Void)] =
            config.hotkeys.enumerated().compactMap { (i, def) in
                guard let def = def else { return nil }
                return (keyCode: def.keyCode, modifiers: def.modifiers, action: actions[i])
            }
        HotkeyManager.shared.registerAll(entries)
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

        // Save button pinned to bottom
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveBtn.bezelStyle = .rounded
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        settingsOverlay.addSubview(saveBtn)
        NSLayoutConstraint.activate([
            saveBtn.bottomAnchor.constraint(equalTo: settingsOverlay.bottomAnchor, constant: -14),
            saveBtn.centerXAnchor.constraint(equalTo: settingsOverlay.centerXAnchor),
        ])

        // Scroll view fills overlay above save button
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        settingsOverlay.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: settingsOverlay.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: settingsOverlay.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: settingsOverlay.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: saveBtn.topAnchor, constant: -8),
        ])

        let docView = FlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = docView

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

        customInputToggle = NSButton(checkboxWithTitle: "Show custom input", target: self, action: #selector(customInputChanged))
        customInputToggle.state = config.showCustomInput ? .on : .off

        // Hotkeys section
        hotkeyFields = []
        let hotkeyLabels = ["Start Timer 1", "Start Timer 2", "Start Timer 3",
                            "Start Timer 4", "Pause / Resume", "Cancel"]
        let hotkeyRows = hotkeyLabels.enumerated().map { (i, lbl) -> NSView in
            let field = HotkeyField(def: config.hotkeys[i])
            hotkeyFields.append(field)
            return makeHotkeyRow(label: lbl, field: field)
        }

        let durHeader = sectionHeader("BUTTON DURATIONS")
        let sndHeader = sectionHeader("SOUND")
        let hkHeader  = sectionHeader("HOTKEYS")

        let contentStack = NSStackView(views:
            [durHeader] + buttonRows +
            [sndHeader, soundRow, chimeDefaultToggle, customInputToggle,
             hkHeader] + hotkeyRows
        )
        contentStack.orientation = .vertical
        contentStack.spacing = 6
        contentStack.alignment = .leading
        contentStack.setCustomSpacing(8,  after: durHeader)
        contentStack.setCustomSpacing(10, after: buttonRows.last!)
        contentStack.setCustomSpacing(6,  after: sndHeader)
        contentStack.setCustomSpacing(10, after: chimeDefaultToggle)
        contentStack.setCustomSpacing(10, after: customInputToggle)
        contentStack.setCustomSpacing(8,  after: hkHeader)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: docView.topAnchor, constant: 10),
            contentStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -10),
            docView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: title)
        lbl.font = .systemFont(ofSize: 10, weight: .semibold)
        lbl.textColor = dimText
        return lbl
    }

    private func makeHotkeyRow(label: String, field: HotkeyField) -> NSView {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12)
        lbl.textColor = bright
        lbl.widthAnchor.constraint(equalToConstant: 92).isActive = true

        field.widthAnchor.constraint(equalToConstant: 108).isActive = true
        field.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let row = NSStackView(views: [lbl, field])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    @objc private func chimeDefaultChanged() {
        chimeOn = chimeDefaultToggle.state == .on
        updateChimeIcon()
    }

    @objc private func customInputChanged() {
        customTimerView.isHidden = customInputToggle.state != .on
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
            customInputToggle.state  = config.showCustomInput ? .on : .off
            for (i, hf) in hotkeyFields.enumerated() { hf.hotkeyDef = config.hotkeys[i] }
            settingsOverlay.isHidden = false
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.openSettings(); return nil }
                return event
            }
        } else {
            hotkeyFields.forEach { $0.cancelRecording() }
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
            chimeEnabled: chimeDefaultToggle.state == .on,
            showCustomInput: customInputToggle.state == .on,
            hotkeys: hotkeyFields.map { $0.hotkeyDef }
        )
        ConfigManager.shared.save(config)
        refreshSelectButtons()
        registerHotkeys()
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

        customTimerView = CustomTimerView()
        customTimerView.translatesAutoresizingMaskIntoConstraints = false
        customTimerView.widthAnchor.constraint(equalToConstant: 176).isActive = true
        customTimerView.heightAnchor.constraint(equalToConstant: 44).isActive = true
        customTimerView.isHidden = !config.showCustomInput
        customField = customTimerView.field
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
        selectStack.addArrangedSubview(customTimerView)
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

// MARK: - Scroll view document helper

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Hotkey recorder field

class HotkeyField: NSView {
    var hotkeyDef: HotkeyDef? { didSet { update() } }

    private let label    = NSTextField(labelWithString: "")
    private let clearBtn = NSButton()
    private var recording   = false
    private var keyMonitor  : Any?

    private let surface       = NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
    private let hoveredColor  = NSColor(red: 0.23, green: 0.23, blue: 0.25, alpha: 1)
    private let recordingBg   = NSColor(red: 0.12, green: 0.20, blue: 0.34, alpha: 1)
    private let dimText       = NSColor(red: 0.38, green: 0.38, blue: 0.40, alpha: 1)
    private let bright        = NSColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1)
    private let accentBorder  = NSColor(red: 0.30, green: 0.50, blue: 0.85, alpha: 1)

    // Modifier key codes — ignore these as standalone keypresses
    private let modifierCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    init(def: HotkeyDef? = nil) {
        self.hotkeyDef = def
        super.init(frame: .zero)
        setup()
        update()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.alignment = .center
        addSubview(label)

        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        clearBtn.isBordered = false
        clearBtn.bezelStyle = .regularSquare
        clearBtn.font = .systemFont(ofSize: 13, weight: .light)
        clearBtn.title = "×"
        clearBtn.contentTintColor = dimText
        clearBtn.target = self
        clearBtn.action = #selector(clear)
        addSubview(clearBtn)

        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            clearBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            clearBtn.widthAnchor.constraint(equalToConstant: 18),
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(startRecording)))
    }

    private func update() {
        if recording {
            label.stringValue = "Type shortcut…"
            label.textColor   = bright.withAlphaComponent(0.65)
            layer?.backgroundColor = recordingBg.cgColor
            layer?.borderColor = accentBorder.cgColor
        } else if let def = hotkeyDef {
            label.stringValue = hotkeyString(def)
            label.textColor   = bright
            layer?.backgroundColor = surface.cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        } else {
            label.stringValue = "—"
            label.textColor   = dimText
            layer?.backgroundColor = surface.cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        }
        clearBtn.isHidden = hotkeyDef == nil || recording
    }

    @objc private func startRecording() {
        guard !recording else { return }
        recording = true
        update()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil  // consume all keys while recording
        }
    }

    func cancelRecording() {
        guard recording else { return }
        stopRecording()
    }

    private func stopRecording() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        recording = false
        update()
    }

    private func handleKey(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)

        // Ignore bare modifier keypresses
        if modifierCodes.contains(keyCode) { return }

        // ESC cancels recording without changing the hotkey
        if keyCode == 53 {
            stopRecording()
            return
        }

        // Delete/Backspace with no modifier clears the hotkey
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if keyCode == 51 && flags.isEmpty {
            hotkeyDef = nil
            stopRecording()
            return
        }

        // Require at least Cmd, Opt, or Ctrl (shift-only combos are too collision-prone)
        let significant = event.modifierFlags.intersection([.command, .option, .control])
        guard !significant.isEmpty else { return }

        hotkeyDef = HotkeyDef(keyCode: keyCode,
                               modifiers: carbonMods(from: event.modifierFlags))
        stopRecording()
    }

    @objc private func clear() {
        hotkeyDef = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        guard !recording else { return }
        layer?.backgroundColor = hoveredColor.cgColor
    }
    override func mouseExited(with event: NSEvent) {
        guard !recording else { return }
        layer?.backgroundColor = surface.cgColor
    }

    private func hotkeyString(_ def: HotkeyDef) -> String {
        var s = ""
        if def.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if def.modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if def.modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if def.modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName(def.keyCode)
        return s
    }

    private func keyName(_ code: UInt32) -> String {
        let table: [UInt32: String] = [
             0:"A",  1:"S",  2:"D",  3:"F",  4:"H",  5:"G",  6:"Z",  7:"X",
             8:"C",  9:"V", 11:"B", 12:"Q", 13:"W", 14:"E", 15:"R",
            16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6",
            23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0",
            30:"]", 31:"O", 32:"U", 33:"[", 34:"I", 35:"P", 36:"↩",
            37:"L", 38:"J", 39:"'", 40:"K", 41:";", 42:"\\", 43:",",
            44:"/", 45:"N", 46:"M", 47:".", 48:"⇥", 49:"Spc", 50:"`",
            51:"⌫", 96:"F5", 97:"F6", 98:"F7", 99:"F3", 100:"F8",
            101:"F9", 103:"F11", 109:"F10", 111:"F12", 118:"F4",
            120:"F2", 122:"F1", 123:"←", 124:"→", 125:"↓", 126:"↑"
        ]
        return table[code] ?? "(\(code))"
    }

    private func carbonMods(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }
}
