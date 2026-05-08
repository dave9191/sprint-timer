import Cocoa
import AVFoundation

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.setActivationPolicy(.accessory)
        let rect = NSRect(x: 0, y: 0, width: 300, height: 340)
        window = NSPanel(
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
        window.center()
        window.contentViewController = TimerViewController()
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Custom dark button

class DarkButton: NSView {
    private let label   = NSTextField(labelWithString: "")
    private let surface = NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
    private let hovered = NSColor(red: 0.23, green: 0.23, blue: 0.25, alpha: 1)
    private let bright  = NSColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1)
    var action: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = surface.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        label.stringValue = title
        label.font = .systemFont(ofSize: 15, weight: .semibold)
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

    func playDoubleChime() {
        guard let url = Bundle.main.url(forResource: "Glass", withExtension: "aiff",
                                        subdirectory: nil)
            ?? URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff") as URL? else { return }
        playAt(url, delay: 0)
        playAt(url, delay: 0.55)
    }

    private func playAt(_ url: URL, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
            player.volume = 0.8
            player.play()
            self?.players.append(player)
            // clean up after playback
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
    private let selectStack  = NSStackView()
    private let timerStack   = NSStackView()

    private var phase       : TimerPhase = .select
    private var totalSecs   = 0
    private var remaining   = 0
    private var overtime    = 0
    private var isPaused    = false
    private var chimeOn     = true
    private var ticker      : Timer?
    private var pulseTimer  : Timer?
    private var pulsePhase  = false

    private let chime = ChimePlayer()

    private let bg         = NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
    private let pulseBg    = NSColor(red: 0.28, green: 0.06, blue: 0.06, alpha: 1)
    private let accent     = NSColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1)
    private let dimText    = NSColor(red: 0.38, green: 0.38, blue: 0.40, alpha: 1)
    private let bright     = NSColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 340))
        view.wantsLayer = true
        view.layer?.backgroundColor = bg.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildSelectView()
        buildTimerView()
        buildChimeToggle()

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

    // MARK: - Select grid

    private func buildSelectView() {
        let pairs: [(Int, String)] = [(5,"5 MIN"),(20,"20 MIN"),(30,"30 MIN"),(60,"60 MIN")]
        let row1 = hrow(pairs[0], pairs[1])
        let row2 = hrow(pairs[2], pairs[3])
        selectStack.orientation = .vertical
        selectStack.spacing = 10
        selectStack.addArrangedSubview(row1)
        selectStack.addArrangedSubview(row2)
    }

    private func hrow(_ a: (Int,String), _ b: (Int,String)) -> NSStackView {
        let s = NSStackView(views: [makeSelBtn(a.0, a.1), makeSelBtn(b.0, b.1)])
        s.orientation = .horizontal
        s.spacing = 10
        return s
    }

    private func makeSelBtn(_ mins: Int, _ label: String) -> NSView {
        let btn = DarkButton(title: label)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 118).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 60).isActive = true
        btn.action = { [weak self] in self?.startTimer(mins) }
        return btn
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
        if chimeOn { chime.playDoubleChime() }
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

    private func showSelect() { selectStack.isHidden = false; timerStack.isHidden = true }
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
