import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

final class CommandTextView: NSTextView {
    var onCommandReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let usesShift = event.modifierFlags.contains(.shift)

        if isReturn, !usesShift {
            onCommandReturn?()
            return
        }

        super.keyDown(with: event)
    }
}

final class ResizeHandleView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var lastWindowY: CGFloat?
    private let lineColor: NSColor
    private let hoverColor: NSColor
    private var isHovering = false

    init(lineColor: NSColor) {
        self.lineColor = lineColor
        self.hoverColor = lineColor.withAlphaComponent(0.62)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        lineColor = .separatorColor
        hoverColor = .separatorColor
        super.init(coder: coder)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        lastWindowY = screenY(for: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let currentY = screenY(for: event)
        guard let lastWindowY else {
            self.lastWindowY = currentY
            return
        }
        let deltaY = currentY - lastWindowY
        self.lastWindowY = currentY
        onDrag?(deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        lastWindowY = nil
    }

    private func screenY(for event: NSEvent) -> CGFloat {
        guard let window else { return event.locationInWindow.y }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        return screenPoint.y
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = isHovering ? hoverColor : lineColor
        color.setFill()

        let centerY = bounds.midY
        let pillWidth: CGFloat = isHovering ? 72 : 54
        let pillHeight: CGFloat = 4
        let pill = NSRect(
            x: bounds.midX - pillWidth / 2,
            y: centerY - pillHeight / 2,
            width: pillWidth,
            height: pillHeight
        )
        NSBezierPath(roundedRect: pill, xRadius: 2, yRadius: 2).fill()
    }
}

final class HermesRunner: NSObject {
    private var process: Process?
    private var outputPipe: Pipe?

    private let hermesCandidates: [String] = [
        "/Users/cereal/.local/bin/hermes",
        "/opt/homebrew/bin/hermes",
        "/usr/local/bin/hermes",
        "/usr/bin/hermes"
    ]

    var isRunning: Bool { process?.isRunning == true }

    func resolveHermesPath() -> String? {
        let fm = FileManager.default
        for candidate in hermesCandidates where fm.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Users/cereal/.local/bin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = String(dir) + "/hermes"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    func runOneShot(prompt: String, workingDirectory: String? = nil, onOutput: @escaping (String) -> Void, onFinish: @escaping (Int32) -> Void) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        runHermes(arguments: ["chat", "-q", prompt], workingDirectory: workingDirectory, onOutput: onOutput, onFinish: onFinish)
    }

    func runHermes(arguments: [String], workingDirectory: String? = nil, onOutput: @escaping (String) -> Void, onFinish: @escaping (Int32) -> Void) {
        guard !isRunning else {
            onOutput("\n[HermesBar] Ya hay una ejecución activa. Cancélala o espera a que termine.\n")
            return
        }
        guard let hermesPath = resolveHermesPath() else {
            onOutput("[HermesBar] No encontré el ejecutable hermes. Instala Hermes o ajusta hermesCandidates en main.swift.\n")
            onFinish(127)
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: hermesPath)
        task.arguments = arguments
        task.environment = mergedEnvironment()
        if let workingDirectory, FileManager.default.fileExists(atPath: workingDirectory) {
            task.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        outputPipe = pipe
        process = task

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { onOutput(text) }
        }

        task.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                onOutput("\n[HermesBar] Proceso terminado con código \(proc.terminationStatus).\n")
                onFinish(proc.terminationStatus)
                self?.process = nil
                self?.outputPipe = nil
            }
        }

        do {
            try task.run()
        } catch {
            onOutput("[HermesBar] Error ejecutando Hermes: \(error.localizedDescription)\n")
            process = nil
            outputPipe = nil
            onFinish(1)
        }
    }

    func cancel(onOutput: @escaping (String) -> Void) {
        guard let process, process.isRunning else { return }
        process.terminate()
        onOutput("\n[HermesBar] Cancelando proceso...\n")
    }

    private func mergedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let additions = [
            "/Users/cereal/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let current = env["PATH"] ?? ""
        env["PATH"] = (additions + [current]).filter { !$0.isEmpty }.joined(separator: ":")
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        return env
    }
}

final class HermesPopoverController: NSViewController, NSTextViewDelegate {
    private let runner = HermesRunner()
    private let hermesBackground = NSColor(calibratedRed: 0.075, green: 0.055, blue: 0.018, alpha: 1.0)
    private let hermesPanel = NSColor(calibratedRed: 0.125, green: 0.092, blue: 0.025, alpha: 1.0)
    private let hermesYellow = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.16, alpha: 1.0)
    private let hermesText = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.72, alpha: 1.0)
    private let inputTextView = CommandTextView()
    private let outputTextView = NSTextView()
    private weak var outputScrollView: NSScrollView?
    private var outputBuffer = ""
    private var outputRenderScheduled = false
    private var outputHeightConstraint: NSLayoutConstraint?
    private var outputFontSize: CGFloat = 12
    private var inputFontSize: CGFloat = 13
    private let minFontSize: CGFloat = 9
    private let maxFontSize: CGFloat = 22
    private let defaultOutputHeight: CGFloat = 340
    private let minOutputHeight: CGFloat = 180
    private let maxOutputHeight: CGFloat = 620
    private let popoverChromeHeight: CGFloat = 220
    private let runButton = NSButton(title: "Run ↩", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let terminalButton = NSButton(title: "Terminal", target: nil, action: nil)
    private let configButton = NSButton(title: "Config", target: nil, action: nil)
    private let quitButton = NSButton(title: "Salir", target: nil, action: nil)
    private let slashButton = NSButton(title: "/", target: nil, action: nil)
    private let topBarLabel = NSTextField(labelWithString: "")
    private let toolbarLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Listo")
    private var sessionGeneration = 1
    private var turnCount = 0
    private var topBarState = "Listo"
    private var currentProjectPath: String?
    private let defaults = UserDefaults.standard
    private let outputHeightDefaultsKey = "HermesBar.outputHeight"
    private let outputFontSizeDefaultsKey = "HermesBar.outputFontSize"
    private let projectPathDefaultsKey = "HermesBar.projectPath"

    override func loadView() {
        loadUISettings()
        let initialOutputHeight = restoredOutputHeight()
        preferredContentSize = NSSize(width: 560, height: popoverChromeHeight + initialOutputHeight)
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: popoverChromeHeight + initialOutputHeight))
        view.wantsLayer = true
        view.layer?.backgroundColor = hermesBackground.cgColor

        let topBar = NSView()
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = hermesPanel.cgColor
        topBar.layer?.cornerRadius = 8
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.heightAnchor.constraint(equalToConstant: 32).isActive = true

        topBarLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        topBarLabel.textColor = hermesYellow
        topBarLabel.lineBreakMode = .byTruncatingTail
        topBarLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(topBarLabel)
        NSLayoutConstraint.activate([
            topBarLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 10),
            topBarLabel.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -10),
            topBarLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])
        updateTopBar(status: "Listo")

        inputTextView.font = .monospacedSystemFont(ofSize: inputFontSize, weight: .regular)
        inputTextView.string = ""
        inputTextView.textColor = hermesText
        inputTextView.insertionPointColor = hermesYellow
        inputTextView.backgroundColor = .clear
        inputTextView.drawsBackground = false
        inputTextView.selectedTextAttributes = [
            .backgroundColor: hermesYellow.withAlphaComponent(0.35),
            .foregroundColor: hermesText
        ]
        inputTextView.minSize = NSSize(width: 0, height: 64)
        inputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.autoresizingMask = [.width]
        inputTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.textContainerInset = NSSize(width: 12, height: 9)
        inputTextView.onCommandReturn = { [weak self] in self?.runPrompt() }

        let inputScroll = NSScrollView()
        inputScroll.borderType = .noBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.scrollerStyle = .overlay
        inputScroll.backgroundColor = .clear
        inputScroll.drawsBackground = false
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.autoresizesSubviews = true
        inputScroll.documentView = inputTextView

        let inputHint = NSTextField(labelWithString: "Enter para enviar · Shift+Enter nueva línea")
        inputHint.font = .systemFont(ofSize: 11, weight: .medium)
        inputHint.textColor = hermesText.withAlphaComponent(0.55)
        inputHint.alignment = .right
        inputHint.translatesAutoresizingMaskIntoConstraints = false

        slashButton.bezelStyle = .rounded
        slashButton.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        slashButton.contentTintColor = hermesYellow
        slashButton.toolTip = "Listar comandos slash de Hermes"
        slashButton.target = self
        slashButton.action = #selector(showSlashCommandsAction)
        slashButton.translatesAutoresizingMaskIntoConstraints = false

        let inputContainer = NSView()
        inputContainer.wantsLayer = true
        inputContainer.layer?.backgroundColor = hermesPanel.cgColor
        inputContainer.layer?.cornerRadius = 14
        inputContainer.layer?.cornerCurve = .continuous
        inputContainer.layer?.borderWidth = 1
        inputContainer.layer?.borderColor = hermesYellow.withAlphaComponent(0.38).cgColor
        inputContainer.layer?.shadowColor = NSColor.black.cgColor
        inputContainer.layer?.shadowOpacity = 0.22
        inputContainer.layer?.shadowRadius = 10
        inputContainer.layer?.shadowOffset = NSSize(width: 0, height: -1)
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inputContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        inputContainer.heightAnchor.constraint(equalToConstant: 92).isActive = true
        inputContainer.addSubview(inputScroll)
        inputContainer.addSubview(slashButton)
        inputContainer.addSubview(inputHint)
        NSLayoutConstraint.activate([
            inputScroll.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 8),
            inputScroll.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -8),
            inputScroll.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 8),
            inputScroll.bottomAnchor.constraint(equalTo: inputHint.topAnchor, constant: -2),
            slashButton.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            slashButton.centerYAnchor.constraint(equalTo: inputHint.centerYAnchor),
            slashButton.widthAnchor.constraint(equalToConstant: 34),
            slashButton.heightAnchor.constraint(equalToConstant: 22),
            inputHint.leadingAnchor.constraint(equalTo: slashButton.trailingAnchor, constant: 8),
            inputHint.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -14),
            inputHint.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -7),
            inputHint.heightAnchor.constraint(equalToConstant: 15)
        ])

        outputTextView.font = .monospacedSystemFont(ofSize: outputFontSize, weight: .regular)
        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.allowsUndo = false
        outputTextView.isRichText = false
        outputTextView.importsGraphics = false
        outputTextView.usesFontPanel = false
        outputTextView.textContainerInset = NSSize(width: 14, height: 12)
        outputTextView.textContainer?.lineFragmentPadding = 0
        outputTextView.textContainer?.widthTracksTextView = true
        outputTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputTextView.isVerticallyResizable = true
        outputTextView.isHorizontallyResizable = false
        outputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputTextView.string = "Salida de Hermes. Escribe abajo y presiona Enter. Shift+Enter agrega una línea.\n"
        outputTextView.textColor = hermesText
        outputTextView.backgroundColor = .clear
        outputTextView.drawsBackground = false
        outputTextView.insertionPointColor = hermesYellow
        outputTextView.selectedTextAttributes = [
            .backgroundColor: hermesYellow.withAlphaComponent(0.35),
            .foregroundColor: hermesText
        ]

        let outputScroll = NSScrollView()
        outputScroll.borderType = .noBorder
        outputScroll.hasVerticalScroller = true
        outputScroll.scrollerStyle = .overlay
        outputScroll.backgroundColor = .clear
        outputScroll.drawsBackground = false
        outputScroll.translatesAutoresizingMaskIntoConstraints = false
        outputScroll.autoresizesSubviews = true
        outputScroll.usesPredominantAxisScrolling = true
        outputScroll.verticalScrollElasticity = .allowed
        outputScroll.horizontalScrollElasticity = .none
        outputScroll.automaticallyAdjustsContentInsets = true
        outputScroll.documentView = outputTextView
        outputScrollView = outputScroll

        let outputContainer = NSVisualEffectView()
        outputContainer.material = .hudWindow
        outputContainer.blendingMode = .withinWindow
        outputContainer.state = .active
        outputContainer.wantsLayer = true
        outputContainer.layer?.backgroundColor = hermesPanel.withAlphaComponent(0.72).cgColor
        outputContainer.layer?.cornerRadius = 14
        outputContainer.layer?.cornerCurve = .continuous
        outputContainer.layer?.borderWidth = 1
        outputContainer.layer?.borderColor = hermesYellow.withAlphaComponent(0.24).cgColor
        outputContainer.layer?.shadowColor = NSColor.black.cgColor
        outputContainer.layer?.shadowOpacity = 0.18
        outputContainer.layer?.shadowRadius = 10
        outputContainer.layer?.shadowOffset = NSSize(width: 0, height: 1)
        outputContainer.translatesAutoresizingMaskIntoConstraints = false
        outputContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        outputContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        outputHeightConstraint = outputContainer.heightAnchor.constraint(equalToConstant: initialOutputHeight)
        outputHeightConstraint?.isActive = true
        outputContainer.addSubview(outputScroll)
        NSLayoutConstraint.activate([
            outputScroll.leadingAnchor.constraint(equalTo: outputContainer.leadingAnchor, constant: 8),
            outputScroll.trailingAnchor.constraint(equalTo: outputContainer.trailingAnchor, constant: -8),
            outputScroll.topAnchor.constraint(equalTo: outputContainer.topAnchor, constant: 8),
            outputScroll.bottomAnchor.constraint(equalTo: outputContainer.bottomAnchor, constant: -8)
        ])

        let outputResizeHandle = ResizeHandleView(lineColor: hermesYellow.withAlphaComponent(0.32))
        outputResizeHandle.heightAnchor.constraint(equalToConstant: 14).isActive = true
        outputResizeHandle.onDrag = { [weak self] deltaY in
            self?.resizeOutput(by: deltaY)
        }

        let utilityBar = NSStackView()
        utilityBar.orientation = .horizontal
        utilityBar.alignment = .centerY
        utilityBar.distribution = .gravityAreas
        utilityBar.spacing = 6
        utilityBar.translatesAutoresizingMaskIntoConstraints = false
        utilityBar.heightAnchor.constraint(equalToConstant: 28).isActive = true

        toolbarLabel.font = .systemFont(ofSize: 11, weight: .medium)
        toolbarLabel.textColor = hermesText.withAlphaComponent(0.62)
        toolbarLabel.lineBreakMode = .byTruncatingMiddle
        toolbarLabel.translatesAutoresizingMaskIntoConstraints = false
        updateToolbarLabel()

        let copyButton = makeToolbarButton("Copiar", action: #selector(copyOutputAction))
        let saveButton = makeToolbarButton("Guardar", action: #selector(saveOutputAction))
        let clearButton = makeToolbarButton("Limpiar", action: #selector(clearSessionAction))
        let clipboardButton = makeToolbarButton("Clipboard", action: #selector(useClipboardAction))
        let fileButton = makeToolbarButton("Archivo", action: #selector(attachFileAction))
        let projectButton = makeToolbarButton("Proyecto", action: #selector(selectProjectAction))
        let doctorButton = makeToolbarButton("Doctor", action: #selector(runDoctorAction))

        utilityBar.addArrangedSubview(toolbarLabel)
        utilityBar.addArrangedSubview(copyButton)
        utilityBar.addArrangedSubview(saveButton)
        utilityBar.addArrangedSubview(clearButton)
        utilityBar.addArrangedSubview(clipboardButton)
        utilityBar.addArrangedSubview(fileButton)
        utilityBar.addArrangedSubview(projectButton)
        utilityBar.addArrangedSubview(doctorButton)

        let stack = NSStackView(views: [topBar, utilityBar, outputContainer, outputResizeHandle, inputContainer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            topBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            utilityBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            outputContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            outputResizeHandle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            outputScroll.widthAnchor.constraint(equalTo: outputContainer.widthAnchor, constant: -16),
            inputContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            inputScroll.widthAnchor.constraint(equalTo: inputContainer.widthAnchor, constant: -16)
        ])
    }

    private func loadUISettings() {
        let savedFontSize = defaults.double(forKey: outputFontSizeDefaultsKey)
        if savedFontSize > 0 {
            outputFontSize = max(minFontSize, min(maxFontSize, CGFloat(savedFontSize)))
            inputFontSize = outputFontSize + 1
        }
        let savedProject = defaults.string(forKey: projectPathDefaultsKey)
        if let savedProject, FileManager.default.fileExists(atPath: savedProject) {
            currentProjectPath = savedProject
        }
    }

    private func restoredOutputHeight() -> CGFloat {
        let savedHeight = defaults.double(forKey: outputHeightDefaultsKey)
        guard savedHeight > 0 else { return defaultOutputHeight }
        return max(minOutputHeight, min(maxOutputHeight, CGFloat(savedHeight)))
    }

    private func saveUISettings() {
        defaults.set(Double(outputHeightConstraint?.constant ?? defaultOutputHeight), forKey: outputHeightDefaultsKey)
        defaults.set(Double(outputFontSize), forKey: outputFontSizeDefaultsKey)
        if let currentProjectPath {
            defaults.set(currentProjectPath, forKey: projectPathDefaultsKey)
        } else {
            defaults.removeObject(forKey: projectPathDefaultsKey)
        }
    }

    private func updateToolbarLabel() {
        let project = currentProjectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "sin proyecto"
        toolbarLabel.stringValue = "Proyecto: \(project)"
    }

    private func notify(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func makeToolbarButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = hermesYellow
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func resizeOutput(by deltaY: CGFloat) {
        guard let outputHeightConstraint else { return }
        // El tirador está debajo de la salida: al arrastrarlo hacia abajo,
        // `deltaY` baja y la caja debe crecer.
        let nextHeight = max(minOutputHeight, min(maxOutputHeight, outputHeightConstraint.constant - deltaY))
        guard nextHeight != outputHeightConstraint.constant else { return }
        outputHeightConstraint.constant = nextHeight

        let nextSize = NSSize(width: preferredContentSize.width, height: popoverChromeHeight + nextHeight)
        preferredContentSize = nextSize
        view.setFrameSize(nextSize)
        view.window?.setContentSize(nextSize)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        saveUISettings()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(inputTextView)
    }

    @objc private func runPromptAction() { runPrompt() }

    private func runPrompt() {
        let prompt = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        if handleLocalSlashCommand(prompt) {
            return
        }

        setRunning(true)
        setOutput("[HermesBar] Ejecutando: hermes chat -q ...\nProyecto: \(currentProjectPath ?? "sin proyecto")\n\n")
        runner.runOneShot(prompt: prompt, workingDirectory: currentProjectPath, onOutput: { [weak self] text in
            self?.appendOutput(text)
        }, onFinish: { [weak self] status in
            guard let self else { return }
            self.turnCount += 1
            self.setRunning(false)
            self.notify(title: "HermesBar", message: status == 0 ? "Consulta terminada" : "Hermes terminó con código \(status)")
        })
    }

    private func handleLocalSlashCommand(_ prompt: String) -> Bool {
        let command = prompt.split(separator: " ").first.map(String.init) ?? prompt
        switch command {
        case "/copy":
            copyOutputAction()
            inputTextView.string = ""
            return true
        case "/save":
            saveOutputAction()
            inputTextView.string = ""
            return true
        case "/paste":
            useClipboardAction()
            return true
        case "/doctor":
            inputTextView.string = ""
            runDoctorAction()
            return true
        case "/project":
            inputTextView.string = ""
            selectProjectAction()
            return true
        case "/clear", "/new", "/reset":
            sessionGeneration += 1
            turnCount = 0
            outputBuffer = ""
            inputTextView.string = ""
            setOutput("[HermesBar] Sesión limpia. Indicador superior actualizado.\n\nEscribe abajo y presiona Enter para empezar una nueva consulta.\n")
            updateTopBar(status: "Sesión limpia")
            view.window?.makeFirstResponder(inputTextView)
            return true
        case "/help", "/commands":
            inputTextView.string = ""
            showSlashCommandsAction()
            updateTopBar(status: "Ayuda")
            return true
        default:
            return false
        }
    }

    private func updateTopBar(status: String? = nil) {
        if let status {
            topBarState = status
        }

        let progress = runner.isRunning ? "[████░░░░░░]" : "[██░░░░░░░░]"
        let percent = runner.isRunning ? "42%" : "18%"
        let project = currentProjectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "sin proyecto"
        topBarLabel.stringValue = "⚕ gpt-5.5 │ \(project) │ sesión \(sessionGeneration) │ turno \(turnCount) │ \(progress) \(percent) │ \(topBarState)"
    }

    @objc func cancelAction() {
        runner.cancel { [weak self] text in
            self?.appendOutput(text)
            self?.updateTopBar(status: "Cancelando")
        }
    }

    @objc func copyOutputAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputBuffer.isEmpty ? outputTextView.string : outputBuffer, forType: .string)
        updateTopBar(status: "Copiado")
    }

    @objc func saveOutputAction() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HermesBar-\(Int(Date().timeIntervalSince1970)).md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try (self.outputBuffer.isEmpty ? self.outputTextView.string : self.outputBuffer).write(to: url, atomically: true, encoding: .utf8)
                self.appendOutput("\n[HermesBar] Conversación guardada en: \(url.path)\n")
                self.updateTopBar(status: "Guardado")
            } catch {
                self.appendOutput("\n[HermesBar] No pude guardar: \(error.localizedDescription)\n")
            }
        }
    }

    @objc func clearSessionAction() {
        _ = handleLocalSlashCommand("/clear")
    }

    @objc func useClipboardAction() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendOutput("\n[HermesBar] El portapapeles no contiene texto.\n")
            return
        }
        inputTextView.string = text
        updateTopBar(status: "Clipboard")
        view.window?.makeFirstResponder(inputTextView)
    }

    @objc func attachFileAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let paths = panel.urls.map { $0.path }
            let addition = paths.map { "\nArchivo: \($0)" }.joined()
            self.inputTextView.string += addition
            self.updateTopBar(status: "Archivo adjunto")
            self.view.window?.makeFirstResponder(self.inputTextView)
        }
    }

    @objc func selectProjectAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar proyecto"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.currentProjectPath = url.path
            self.saveUISettings()
            self.updateTopBar(status: "Proyecto")
            self.updateToolbarLabel()
            self.appendOutput("\n[HermesBar] Proyecto activo: \(url.path)\n")
        }
    }

    @objc func runDoctorAction() {
        setRunning(true)
        setOutput("[HermesBar] Ejecutando: hermes doctor\n\n")
        runner.runHermes(arguments: ["doctor"], workingDirectory: currentProjectPath, onOutput: { [weak self] text in
            self?.appendOutput(text)
        }, onFinish: { [weak self] status in
            guard let self else { return }
            self.setRunning(false)
            self.updateTopBar(status: status == 0 ? "Doctor OK" : "Doctor error")
            self.notify(title: "Hermes doctor", message: status == 0 ? "Doctor terminó OK" : "Doctor terminó con código \(status)")
        })
    }

    @objc func openTerminalAction() {
        let hermesPath = runner.resolveHermesPath() ?? "hermes"
        let cdCommand = currentProjectPath.map { "cd \(shellEscaped($0)) && " } ?? ""
        let script = """
        tell application "Terminal"
            activate
            do script "\(cdCommand)\(shellEscaped(hermesPath))"
        end tell
        """
        runAppleScript(script)
    }

    @objc func openContinueTerminalAction() {
        let hermesPath = runner.resolveHermesPath() ?? "hermes"
        let cdCommand = currentProjectPath.map { "cd \(shellEscaped($0)) && " } ?? ""
        let script = """
        tell application "Terminal"
            activate
            do script "\(cdCommand)\(shellEscaped(hermesPath)) --continue"
        end tell
        """
        runAppleScript(script)
    }

    @objc func openSessionsTerminalAction() {
        let hermesPath = runner.resolveHermesPath() ?? "hermes"
        let script = """
        tell application "Terminal"
            activate
            do script "\(shellEscaped(hermesPath)) sessions browse"
        end tell
        """
        runAppleScript(script)
    }

    @objc func openConfigAction() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let config = home + "/.hermes/config.yaml"
        NSWorkspace.shared.open(URL(fileURLWithPath: config))
    }

    @objc func showSlashCommandsAction() {
        setOutput(slashCommandsText())
        updateTopBar(status: "Comandos slash")
        view.window?.makeFirstResponder(inputTextView)
    }

    private func slashCommandsText() -> String {
        return """
        # Comandos slash de Hermes

        ## Sesión
        - /new o /reset — iniciar una sesión nueva.
        - /clear — limpiar pantalla y empezar sesión nueva.
        - /retry — reenviar el último mensaje.
        - /undo — quitar el último intercambio.
        - /title [nombre] — poner nombre a la sesión.
        - /compress — comprimir contexto manualmente.
        - /stop — detener procesos en segundo plano.
        - /rollback [N] — restaurar checkpoint de archivos.
        - /snapshot [sub] — crear/restaurar snapshots de estado.
        - /background <prompt> — ejecutar prompt en segundo plano.
        - /queue <prompt> — encolar prompt para el próximo turno.
        - /steer <prompt> — inyectar instrucción después del próximo tool call.
        - /agents o /tasks — ver agentes/tareas activos.
        - /resume [nombre] — reanudar sesión.
        - /goal [texto|sub] — definir objetivo persistente.
        - /redraw — repintar la UI.

        ## Configuración
        - /config — mostrar configuración.
        - /model [nombre] — ver o cambiar modelo.
        - /personality [nombre] — cambiar personalidad.
        - /reasoning [nivel] — cambiar nivel de razonamiento.
        - /verbose — alternar verbosidad.
        - /voice [on|off|tts] — modo voz.
        - /yolo — alternar aprobación automática.
        - /busy [sub] — controlar Enter cuando Hermes está trabajando.
        - /indicator [style] — cambiar indicador de actividad.
        - /footer [on|off] — metadata footer en gateway.
        - /skin [nombre] — cambiar tema.
        - /statusbar — alternar barra de estado.

        ## Herramientas y skills
        - /tools — administrar herramientas.
        - /toolsets — listar toolsets.
        - /skills — buscar/instalar skills.
        - /skill <nombre> — cargar skill en la sesión.
        - /reload-skills — re-escanear skills locales.
        - /reload — recargar variables .env.
        - /reload-mcp — recargar servidores MCP.
        - /cron — administrar cron jobs.
        - /curator [sub] — mantenimiento de skills.
        - /kanban [sub] — tablero multi-agente.
        - /plugins — listar plugins.

        ## Gateway
        - /approve — aprobar comando pendiente.
        - /deny — denegar comando pendiente.
        - /restart — reiniciar gateway.
        - /sethome — fijar chat actual como home.
        - /update — actualizar Hermes.
        - /topic [sub] — sesiones por topic en Telegram.
        - /platforms o /gateway — estado de plataformas.

        ## Utilidad
        - /copy — copiar la salida de HermesBar al portapapeles.
        - /save — guardar la salida de HermesBar como archivo.
        - /paste — pegar el texto del portapapeles en el input.
        - /doctor — ejecutar hermes doctor dentro del wrapper.
        - /project — seleccionar carpeta de proyecto para ejecutar Hermes.
        - /branch o /fork — ramificar sesión.
        - /fast — alternar procesamiento rápido.
        - /browser — abrir conexión browser/CDP.
        - /history — historial de conversación.
        - /save — guardar conversación.
        - /copy [N] — copiar última respuesta.
        - /paste — adjuntar imagen del clipboard.
        - /image — adjuntar imagen local.

        ## Info
        - /help — mostrar ayuda.
        - /commands [page] — navegar comandos.
        - /usage — uso de tokens.
        - /insights [days] — analíticas.
        - /gquota — cuota de Gemini Code Assist.
        - /status — info de sesión.
        - /profile — perfil activo.
        - /debug — generar reporte de debug.

        ## Salir
        - /quit, /exit o /q — salir de Hermes CLI.
        """
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    private func setRunning(_ running: Bool) {
        runButton.isEnabled = !running
        cancelButton.isEnabled = running
        statusLabel.stringValue = running ? "Ejecutando..." : "Listo"
        updateTopBar(status: running ? "Ejecutando" : "Listo")
    }

    @objc func increaseTextSize() {
        setTextSize(outputFontSize + 1)
    }

    @objc func decreaseTextSize() {
        setTextSize(outputFontSize - 1)
    }

    @objc func resetTextSize() {
        setTextSize(12)
    }

    private func setTextSize(_ size: CGFloat) {
        outputFontSize = max(minFontSize, min(maxFontSize, size))
        inputFontSize = outputFontSize + 1
        inputTextView.font = .monospacedSystemFont(ofSize: inputFontSize, weight: .regular)
        outputTextView.font = .monospacedSystemFont(ofSize: outputFontSize, weight: .regular)
        saveUISettings()
        updateTopBar()
        renderOutputBuffer()
    }

    private func setOutput(_ text: String) {
        outputBuffer = sanitizeOutput(text)
        renderOutputBuffer()
    }

    private func appendOutput(_ text: String) {
        outputBuffer += sanitizeOutput(text)
        scheduleOutputRender()
    }

    private func scheduleOutputRender() {
        guard !outputRenderScheduled else { return }
        outputRenderScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            guard let self else { return }
            self.outputRenderScheduled = false
            self.renderOutputBuffer()
        }
    }

    private func renderOutputBuffer() {
        let shouldStickToBottom = isOutputScrolledNearBottom()
        outputTextView.textStorage?.beginEditing()
        outputTextView.textStorage?.setAttributedString(formattedOutput(from: outputBuffer))
        outputTextView.textStorage?.endEditing()
        if shouldStickToBottom {
            scrollOutputToBottom(animated: true)
        }
    }

    private func isOutputScrolledNearBottom() -> Bool {
        guard let scrollView = outputScrollView else { return true }
        let visibleMaxY = scrollView.contentView.bounds.maxY
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        return documentHeight - visibleMaxY < 36
    }

    private func scrollOutputToBottom(animated: Bool) {
        let range = NSRange(location: outputTextView.string.utf16.count, length: 0)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.allowsImplicitAnimation = true
                outputTextView.scrollRangeToVisible(range)
            }
        } else {
            outputTextView.scrollRangeToVisible(range)
        }
    }

    private func sanitizeOutput(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(of: "\r", with: "\n")
        cleaned = cleaned.replacingOccurrences(
            of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        return cleaned
    }

    private func formattedOutput(from text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var inCodeBlock = false
        let lines = text.components(separatedBy: "\n")

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .newlines)
            let renderedLine: String
            var attributes: [NSAttributedString.Key: Any]

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                renderedLine = "────────────────────────────────────────"
                attributes = outputAttributes(color: hermesYellow.withAlphaComponent(0.70), weight: .regular)
            } else if inCodeBlock {
                renderedLine = rawLine.isEmpty ? " " : "  " + rawLine
                attributes = outputAttributes(color: NSColor(calibratedRed: 0.74, green: 0.95, blue: 0.62, alpha: 1.0), weight: .regular, lineSpacing: 2)
                attributes[.backgroundColor] = hermesBackground.withAlphaComponent(0.75)
            } else if line.hasPrefix("### ") || line.hasPrefix("## ") || line.hasPrefix("# ") {
                renderedLine = line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
                attributes = outputAttributes(color: hermesYellow, weight: .bold, fontSize: 13, lineSpacing: 5)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                renderedLine = "  • " + String(line.dropFirst(2))
                attributes = outputAttributes(color: hermesText, weight: .regular, lineSpacing: 3)
            } else if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                renderedLine = "  " + line
                attributes = outputAttributes(color: hermesText, weight: .regular, lineSpacing: 3)
            } else if line.hasPrefix("[HermesBar]") {
                renderedLine = line
                attributes = outputAttributes(color: hermesYellow.withAlphaComponent(0.82), weight: .medium, lineSpacing: 4)
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                renderedLine = ""
                attributes = outputAttributes(color: hermesText.withAlphaComponent(0.75), weight: .regular, lineSpacing: 5)
            } else {
                renderedLine = rawLine
                attributes = outputAttributes(color: hermesText, weight: .regular, lineSpacing: 3)
            }

            result.append(NSAttributedString(string: renderedLine, attributes: attributes))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        return result
    }

    private func outputAttributes(
        color: NSColor? = nil,
        weight: NSFont.Weight = .regular,
        fontSize: CGFloat = 12,
        lineSpacing: CGFloat = 3
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping

        let effectiveFontSize = max(minFontSize, min(maxFontSize + 2, fontSize + (outputFontSize - 12)))

        return [
            .foregroundColor: color ?? hermesText,
            .font: NSFont.monospacedSystemFont(ofSize: effectiveFontSize, weight: weight),
            .paragraphStyle: paragraph
        ]
    }

    private func shellEscaped(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runAppleScript(_ source: String) {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
        }
        if let error {
            appendOutput("\n[HermesBar] AppleScript error: \(error)\n")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let controller = HermesPopoverController()
    private let actionsMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⚚ Hermes"
            button.target = self
            button.action = #selector(statusIconClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        addMenuItem(actionsMenu, title: "Abrir chat", action: #selector(showPopoverFromMenu), key: "h")
        addMenuItem(actionsMenu, title: "Comandos slash", action: #selector(showSlashCommandsFromMenu), key: "/")
        actionsMenu.addItem(NSMenuItem.separator())
        addMenuItem(actionsMenu, title: "Cancelar ejecución", action: #selector(cancelFromMenu), key: ".")
        addMenuItem(actionsMenu, title: "Copiar salida", action: #selector(copyOutputFromMenu), key: "c")
        addMenuItem(actionsMenu, title: "Guardar salida", action: #selector(saveOutputFromMenu), key: "s")
        addMenuItem(actionsMenu, title: "Limpiar sesión", action: #selector(clearSessionFromMenu), key: "l")
        addMenuItem(actionsMenu, title: "Usar clipboard", action: #selector(useClipboardFromMenu), key: "v")
        addMenuItem(actionsMenu, title: "Adjuntar archivo", action: #selector(attachFileFromMenu), key: "a")
        addMenuItem(actionsMenu, title: "Seleccionar proyecto", action: #selector(selectProjectFromMenu), key: "p")
        addMenuItem(actionsMenu, title: "Hermes doctor", action: #selector(runDoctorFromMenu), key: "d")
        actionsMenu.addItem(NSMenuItem.separator())
        addMenuItem(actionsMenu, title: "Abrir Hermes en Terminal", action: #selector(openHermesTerminal), key: "t")
        addMenuItem(actionsMenu, title: "Continuar última sesión en Terminal", action: #selector(openContinueTerminal), key: "r")
        addMenuItem(actionsMenu, title: "Buscar sesiones en Terminal", action: #selector(openSessionsTerminal), key: "b")
        addMenuItem(actionsMenu, title: "Abrir configuración", action: #selector(openConfigFromMenu), key: ",")
        actionsMenu.addItem(NSMenuItem.separator())
        addMenuItem(actionsMenu, title: "Agrandar texto", action: #selector(increaseTextSizeFromMenu), key: "+")
        addMenuItem(actionsMenu, title: "Reducir texto", action: #selector(decreaseTextSizeFromMenu), key: "-")
        addMenuItem(actionsMenu, title: "Texto normal", action: #selector(resetTextSizeFromMenu), key: "0")
        actionsMenu.addItem(NSMenuItem.separator())
        addMenuItem(actionsMenu, title: "Salir", action: #selector(quit), key: "q")
        // No asignamos statusItem.menu directamente porque macOS abre el menú
        // tanto con click izquierdo como derecho. Manejo ambos clicks manualmente:
        // izquierdo = abrir chat, derecho = lista de acciones.
    }

    private func addMenuItem(_ menu: NSMenu, title: String, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func statusIconClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            showActionsMenu()
            return
        }

        if event.type == .rightMouseUp {
            showActionsMenu()
        } else {
            showPopoverFromMenu()
        }
    }

    private func showActionsMenu() {
        guard let button = statusItem.button else { return }
        statusItem.menu = actionsMenu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func showPopoverFromMenu() {
        togglePopover(statusItem.button)
    }

    @objc private func showSlashCommandsFromMenu() {
        ensurePopoverShown()
        controller.showSlashCommandsAction()
    }

    private func ensurePopoverShown() {
        if !popover.isShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func cancelFromMenu() {
        controller.cancelAction()
    }

    @objc private func copyOutputFromMenu() {
        controller.copyOutputAction()
    }

    @objc private func saveOutputFromMenu() {
        controller.saveOutputAction()
    }

    @objc private func clearSessionFromMenu() {
        controller.clearSessionAction()
    }

    @objc private func useClipboardFromMenu() {
        ensurePopoverShown()
        controller.useClipboardAction()
    }

    @objc private func attachFileFromMenu() {
        ensurePopoverShown()
        controller.attachFileAction()
    }

    @objc private func selectProjectFromMenu() {
        ensurePopoverShown()
        controller.selectProjectAction()
    }

    @objc private func runDoctorFromMenu() {
        ensurePopoverShown()
        controller.runDoctorAction()
    }

    @objc private func openConfigFromMenu() {
        controller.openConfigAction()
    }

    @objc private func increaseTextSizeFromMenu() {
        controller.increaseTextSize()
    }

    @objc private func decreaseTextSizeFromMenu() {
        controller.decreaseTextSize()
    }

    @objc private func resetTextSizeFromMenu() {
        controller.resetTextSize()
    }

    @objc private func openHermesTerminal() {
        controller.openTerminalAction()
    }

    @objc private func openContinueTerminal() {
        controller.openContinueTerminalAction()
    }

    @objc private func openSessionsTerminal() {
        controller.openSessionsTerminalAction()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@main
struct HermesBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        _ = delegate
    }
}
