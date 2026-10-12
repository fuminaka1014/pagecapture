import AppKit
import ApplicationServices
import ImageIO
import PDFKit
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum CaptureError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): return text
    }
  }
}

enum Paper: String, CaseIterable, Identifiable {
  case landscape = "A4 横"
  case portrait = "A4 縦"
  case original = "画像と同じ比率"
  var id: String { rawValue }
  func size(for image: CGImage) -> CGSize {
    switch self {
    case .landscape: return CGSize(width: 841.89, height: 595.28)
    case .portrait: return CGSize(width: 595.28, height: 841.89)
    case .original:
      return CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
    }
  }
}

struct Region {
  let displayID: CGDirectDisplayID
  let localRect: CGRect
  let quartzRect: CGRect
  let scale: CGFloat

  init(cocoaRect: CGRect, screen: NSScreen) {
    displayID =
      (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
    localRect = CGRect(
      x: cocoaRect.minX - screen.frame.minX,
      y: screen.frame.maxY - cocoaRect.maxY,
      width: cocoaRect.width, height: cocoaRect.height)
    let top = NSScreen.screens[0].frame.maxY
    quartzRect = CGRect(
      x: cocoaRect.minX, y: top - cocoaRect.maxY,
      width: cocoaRect.width, height: cocoaRect.height)
    scale = screen.backingScaleFactor
  }
}

enum ImageTools {
  static func save(_ image: CGImage, to url: URL) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
      throw CaptureError.message("画像ファイルを作成できませんでした。")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw CaptureError.message("画像を保存できませんでした。空き容量を確認してください。")
    }
  }

  static func load(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw CaptureError.message("保存済み画像を読み込めませんでした。")
    }
    return image
  }

  static func fingerprint(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 64 * 64)
    bytes.withUnsafeMutableBytes { pointer in
      let context = CGContext(
        data: pointer.baseAddress, width: 64, height: 64,
        bitsPerComponent: 8, bytesPerRow: 64,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
      context.interpolationQuality = .medium
      context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    return bytes
  }

  static func difference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
    return Double(zip(lhs, rhs).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(lhs.count)
  }
}

enum PDFExporter {
  static func write(images: [URL], to url: URL, paper: Paper) throws {
    guard !images.isEmpty else { throw CaptureError.message("撮影済みのページがありません。") }
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard
      let context = CGContext(
        temporary as CFURL, mediaBox: nil,
        [
          kCGPDFContextTitle as String: url.deletingPathExtension().lastPathComponent,
          kCGPDFContextCreator as String: "PageCapture",
        ] as CFDictionary)
    else {
      throw CaptureError.message("PDFを作成できませんでした。保存先を確認してください。")
    }
    do {
      for imageURL in images {
        try autoreleasepool {
          let image = try ImageTools.load(imageURL)
          let size = paper.size(for: image)
          var mediaBox = CGRect(origin: .zero, size: size)
          let data = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
          context.beginPDFPage([kCGPDFContextMediaBox as String: data] as CFDictionary)
          context.setFillColor(NSColor.white.cgColor)
          context.fill(mediaBox)
          let margin: CGFloat = paper == .original ? 0 : 18
          let available = mediaBox.insetBy(dx: margin, dy: margin)
          let scale = min(
            available.width / CGFloat(image.width), available.height / CGFloat(image.height))
          let rect = CGRect(
            x: (size.width - CGFloat(image.width) * scale) / 2,
            y: (size.height - CGFloat(image.height) * scale) / 2,
            width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
          context.interpolationQuality = .high
          context.draw(image, in: rect)
          context.endPDFPage()
        }
      }
      context.closePDF()
    } catch {
      context.closePDF()
      throw error
    }
    if FileManager.default.fileExists(atPath: url.path) {
      _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: url)
    }
  }
}

struct FrameGate {
  let previous: [UInt8]?
  private var candidate: [UInt8]?
  private(set) var changed: Bool

  init(previous: [UInt8]?) {
    self.previous = previous
    changed = previous == nil
  }

  mutating func accepts(_ fingerprint: [UInt8]) -> Bool {
    let differs = previous.map { ImageTools.difference(fingerprint, $0) > 0.5 } ?? true
    changed = changed || differs
    defer { candidate = fingerprint }
    return differs && candidate.map { ImageTools.difference(fingerprint, $0) <= 0.4 } == true
  }
}

@MainActor
final class SelectionWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

@MainActor
final class SelectionView: NSView {
  var pointMode = false
  var start: CGPoint?
  var current: CGPoint?
  var onSelect: ((CGRect) -> Void)?
  var onCancel: (() -> Void)?
  override var acceptsFirstResponder: Bool { true }

  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.withAlphaComponent(0.20).setFill()
    bounds.fill()
    if let start, let current, !pointMode {
      let rect = selection(start, current)
      NSColor.white.withAlphaComponent(0.12).setFill()
      rect.fill()
      NSColor.systemMint.setStroke()
      let path = NSBezierPath(rect: rect)
      path.lineWidth = 2
      path.stroke()
    }
    let text = pointMode ? "次ページのボタンをクリック   ·   Escでキャンセル" : "撮影範囲をドラッグ   ·   Escでキャンセル"
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
      .foregroundColor: NSColor.white,
    ]
    let textSize = (text as NSString).size(withAttributes: attrs)
    let box = CGRect(
      x: (bounds.width - textSize.width) / 2 - 20,
      y: bounds.height - 110, width: textSize.width + 40, height: 50)
    NSColor.black.withAlphaComponent(0.8).setFill()
    NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
    (text as NSString).draw(at: CGPoint(x: box.minX + 20, y: box.minY + 14), withAttributes: attrs)
  }

  func selection(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
      .intersection(bounds).integral
  }

  override func mouseDown(with event: NSEvent) {
    start = convert(event.locationInWindow, from: nil)
    current = start
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    current = convert(event.locationInWindow, from: nil)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    guard let start else { return }
    let end = convert(event.locationInWindow, from: nil)
    let rect = pointMode ? CGRect(origin: end, size: .zero) : selection(start, end)
    if pointMode || (rect.width >= 40 && rect.height >= 40) { onSelect?(rect) }
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { onCancel?() }
  }
}

@MainActor
final class ScreenSelector {
  private var windows: [NSWindow] = []
  private var completion: ((CGRect?, NSScreen?) -> Void)?

  func select(point: Bool, completion: @escaping (CGRect?, NSScreen?) -> Void) {
    self.completion = completion
    for screen in NSScreen.screens {
      let window = SelectionWindow(
        contentRect: screen.frame, styleMask: .borderless,
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.level = .screenSaver
      window.backgroundColor = .clear
      window.isOpaque = false
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
      view.pointMode = point
      view.onSelect = { [weak self, weak window] rect in
        guard let window else { return }
        self?.finish(window.convertToScreen(rect), screen)
      }
      view.onCancel = { [weak self] in self?.finish(nil, nil) }
      window.contentView = view
      window.makeKeyAndOrderFront(nil)
      window.makeFirstResponder(view)
      windows.append(window)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  private func finish(_ rect: CGRect?, _ screen: NSScreen?) {
    windows.forEach { $0.close() }
    windows.removeAll()
    let callback = completion
    completion = nil
    callback?(rect, screen)
  }
}

@MainActor
final class CaptureModel: ObservableObject {
  @Published var region: Region?
  @Published var nextPoint: CGPoint?
  @Published var pageCount = 10
  @Published var delay = 1.5
  @Published var paper: Paper = .landscape
  @Published var stopOnDuplicate = true
  @Published var isRunning = false
  @Published var completed = 0
  @Published var status = "待機中"
  @Published var error: String?
  @Published var preview: NSImage?
  @Published var outputURL: URL?
  @Published var screenAllowed = false
  @Published var clickAllowed = false
  var mainWindow: NSWindow?
  private let selector = ScreenSelector()
  private var task: Task<Void, Never>?
  private var globalKeyMonitor: Any?
  private var localKeyMonitor: Any?
  private var statusItem: NSStatusItem?
  private var targetApp: NSRunningApplication?
  private var timer: Timer?

  init(observePermissions: Bool = true) {
    guard observePermissions else { return }
    refreshPermissions()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshPermissions() }
    }
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { Task { @MainActor in self?.stop() } }
      return event
    }
  }

  func refreshPermissions() {
    screenAllowed = CGPreflightScreenCaptureAccess()
    clickAllowed = AXIsProcessTrusted()
    if clickAllowed, globalKeyMonitor == nil {
      globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
        [weak self] event in
        if event.keyCode == 53 { Task { @MainActor in self?.stop() } }
      }
    } else if !clickAllowed, let globalKeyMonitor {
      NSEvent.removeMonitor(globalKeyMonitor)
      self.globalKeyMonitor = nil
    }
  }

  func allowScreen() {
    CGRequestScreenCaptureAccess()
    openSettings("Privacy_ScreenCapture")
  }

  func allowClick() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    openSettings("Privacy_Accessibility")
  }

  private func openSettings(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
      NSWorkspace.shared.open(url)
    }
  }

  func chooseRegion() {
    mainWindow?.orderOut(nil)
    selector.select(point: false) { [weak self] rect, screen in
      guard let self else { return }
      if let rect, let screen {
        region = Region(cocoaRect: rect, screen: screen)
        preview = nil
      }
      showMainWindow()
    }
  }

  func chooseNext() {
    mainWindow?.orderOut(nil)
    selector.select(point: true) { [weak self] rect, _ in
      guard let self else { return }
      if let rect {
        nextPoint = CGPoint(x: rect.minX, y: NSScreen.screens[0].frame.maxY - rect.minY)
        targetApp = application(at: nextPoint!)
      }
      showMainWindow()
    }
  }

  private func application(at point: CGPoint) -> NSRunningApplication? {
    guard
      let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    for item in list {
      guard let pid = item[kCGWindowOwnerPID as String] as? Int32,
        pid != ProcessInfo.processInfo.processIdentifier,
        let bounds = item[kCGWindowBounds as String] as? [String: Any],
        let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(point),
        let layer = item[kCGWindowLayer as String] as? Int, layer == 0
      else { continue }
      return NSRunningApplication(processIdentifier: pid)
    }
    return nil
  }

  private func makeCapture() async throws -> (SCContentFilter, SCStreamConfiguration) {
    guard let region else { throw CaptureError.message("撮影範囲を選択してください。") }
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
      throw CaptureError.message("選択した画面が見つかりません。撮影範囲を選び直してください。")
    }
    guard
      CGRect(x: 0, y: 0, width: display.width, height: display.height).contains(region.localRect)
    else {
      throw CaptureError.message("画面の配置が変わっています。撮影範囲を選び直してください。")
    }
    let ownApp = content.applications.filter {
      $0.processID == ProcessInfo.processInfo.processIdentifier
    }
    let filter = SCContentFilter(
      display: display, excludingApplications: ownApp, exceptingWindows: [])
    let config = SCStreamConfiguration()
    config.sourceRect = region.localRect
    config.width = Int(region.localRect.width * region.scale)
    config.height = Int(region.localRect.height * region.scale)
    config.showsCursor = false
    config.scalesToFit = true
    config.captureResolution = .best
    return (filter, config)
  }

  func testCapture() {
    guard !isRunning else { return }
    isRunning = true
    error = nil
    status = "テスト撮影中"
    task = Task {
      do {
        let (filter, config) = try await makeCapture()
        mainWindow?.orderOut(nil)
        try await Task.sleep(for: .milliseconds(400))
        let image = try await SCScreenshotManager.captureImage(
          contentFilter: filter, configuration: config)
        preview = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        status = "テスト撮影完了"
      } catch is CancellationError { status = "テスト撮影を中止しました" } catch {
        self.error = error.localizedDescription
        status = "撮影できませんでした"
      }
      isRunning = false
      showMainWindow()
    }
  }

  func start() {
    guard !isRunning, region != nil, pageCount > 0, pageCount <= 5000,
      pageCount == 1 || nextPoint != nil
    else { return }
    refreshPermissions()
    guard screenAllowed else {
      error = "「画面収録」を許可してから実行してください。"
      return
    }
    guard pageCount == 1 || clickAllowed else {
      error = "「アクセシビリティ」を許可してから実行してください。"
      return
    }
    guard pageCount == 1 || targetApp != nil else {
      error = "次ページのボタンがあるアプリを確認できませんでした。位置を選び直してください。"
      return
    }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = "ページキャプチャ.pdf"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    let count = pageCount
    let wait = delay
    let paper = paper
    let detectDuplicates = stopOnDuplicate
    let clickPoint = nextPoint
    outputURL = nil
    completed = 0
    error = nil
    isRunning = true
    showStatusItem()
    task = Task {
      await run(
        destination: destination, count: count, wait: wait,
        paper: paper, detectDuplicates: detectDuplicates, clickPoint: clickPoint)
    }
  }

  private func run(
    destination: URL, count: Int, wait: Double, paper: Paper,
    detectDuplicates: Bool, clickPoint: CGPoint?
  ) async {
    var images: [URL] = []
    var failure: String?
    var cancelled = false
    let activeTarget = count > 1 ? targetApp : nil
    let imageFolder = destination.deletingLastPathComponent().appendingPathComponent(
      "\(destination.deletingPathExtension().lastPathComponent)-pages-\(UUID().uuidString.prefix(8))",
      isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
      let (filter, config) = try await makeCapture()
      mainWindow?.orderOut(nil)
      activeTarget?.activate(options: [])
      for second in stride(from: 3, through: 1, by: -1) {
        status = "\(second)秒後に開始"
        updateStatusItem()
        try await Task.sleep(for: .seconds(1))
      }
      var previous: [UInt8]?
      for page in 1...count {
        try Task.checkCancellation()
        try validateTarget(activeTarget)
        status = "\(page) / \(count) ページを撮影中"
        updateStatusItem()
        let image = try await stableImage(
          filter: filter, config: config,
          previous: detectDuplicates ? previous : nil, target: activeTarget)
        try Task.checkCancellation()
        let path = imageFolder.appendingPathComponent(String(format: "page-%05d.png", page))
        try ImageTools.save(image, to: path)
        images.append(path)
        completed = images.count
        previous = ImageTools.fingerprint(image)
        preview = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        if page < count, let clickPoint {
          try Task.checkCancellation()
          guard AXIsProcessTrusted() else { throw CaptureError.message("操作の許可が取り消されました。") }
          try await Task.sleep(for: .milliseconds(100))
          try Task.checkCancellation()
          try validateTarget(activeTarget, at: clickPoint)
          try click(at: clickPoint)
          try await Task.sleep(for: .seconds(wait))
        }
      }
    } catch is CancellationError { cancelled = true } catch { failure = error.localizedDescription }
    if !images.isEmpty {
      status = "PDFを保存中"
      updateStatusItem()
      do {
        // The writer opens one PNG at a time, so long captures do not retain every full-size image.
        try await Task.detached(priority: .userInitiated) {
          try PDFExporter.write(images: images, to: destination, paper: paper)
        }.value
        outputURL = destination
        status =
          cancelled
          ? "停止しました · \(completed)ページ保存済み"
          : failure == nil ? "完了 · \(completed)ページ保存済み" : "\(completed)ページまで保存しました"
      } catch {
        failure = "PDFの保存に失敗しました。撮影画像は \(imageFolder.path) に残っています。\n\(error.localizedDescription)"
        status = "PDFを保存できませんでした"
      }
    } else {
      try? FileManager.default.removeItem(at: imageFolder)
      status = cancelled ? "中止しました" : "撮影できませんでした"
    }
    error = failure
    isRunning = false
    if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    statusItem = nil
    showMainWindow()
  }

  private func validateTarget(_ target: NSRunningApplication?, at point: CGPoint? = nil) throws {
    guard let target else { return }
    guard !target.isTerminated else {
      throw CaptureError.message("ページを表示していたアプリが終了しました。")
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    else {
      throw CaptureError.message("別のアプリが前面になったため停止しました。対象アプリを表示して再実行してください。")
    }
    if let point, application(at: point)?.processIdentifier != target.processIdentifier {
      throw CaptureError.message("ページ送り位置に対象アプリがないため停止しました。位置を選び直してください。")
    }
  }

  private func stableImage(
    filter: SCContentFilter, config: SCStreamConfiguration,
    previous: [UInt8]?, target: NSRunningApplication?
  ) async throws -> CGImage {
    let deadline = Date().addingTimeInterval(15)
    var gate = FrameGate(previous: previous)
    while Date() < deadline {
      try Task.checkCancellation()
      try validateTarget(target)
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: config)
      try Task.checkCancellation()
      try validateTarget(target)
      let fingerprint = ImageTools.fingerprint(image)
      if gate.accepts(fingerprint) { return image }
      try await Task.sleep(for: .milliseconds(400))
    }
    throw CaptureError.message(
      gate.changed
        ? "画面が安定しないため停止しました。待ち時間を増やして再実行してください。"
        : "ページが変わらなかったため停止しました。最終ページ、または次ページのボタン位置を確認してください。")
  }

  private func click(at point: CGPoint) throws {
    guard let source = CGEventSource(stateID: .hidSystemState),
      let down = CGEvent(
        mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point,
        mouseButton: .left),
      let up = CGEvent(
        mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point,
        mouseButton: .left)
    else {
      throw CaptureError.message("クリック操作を作成できませんでした。")
    }
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    up.setIntegerValueField(.mouseEventClickState, value: 1)
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }

  func stop() { if isRunning { task?.cancel() } }

  private func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    mainWindow?.makeKeyAndOrderFront(nil)
  }

  private func showStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let item = NSMenuItem(title: "撮影を停止", action: #selector(stopFromMenu), keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    statusItem?.menu = menu
    updateStatusItem()
  }

  @objc private func stopFromMenu() { stop() }
  private func updateStatusItem() {
    statusItem?.button?.title = "  \(status)"
    statusItem?.button?.image = NSImage(
      systemSymbolName: "camera", accessibilityDescription: "ページキャプチャ")
  }

  func openPDF() { if let outputURL { NSWorkspace.shared.open(outputURL) } }
  func revealPDF() {
    if let outputURL { NSWorkspace.shared.activateFileViewerSelecting([outputURL]) }
  }
}

struct ContentView: View {
  @ObservedObject var model: CaptureModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "doc.viewfinder").font(.system(size: 28)).foregroundStyle(.mint)
        Text("ページキャプチャ").font(.system(size: 22, weight: .semibold))
        Spacer()
        Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
      }.padding(22)
      Divider()
      ScrollView(.vertical) {
        HStack(alignment: .top, spacing: 24) {
          VStack(alignment: .leading, spacing: 19) {
            setting("撮影範囲", icon: "crop") {
              HStack {
                Text(
                  model.region.map { "\(Int($0.localRect.width)) × \(Int($0.localRect.height)) pt" }
                    ?? "未選択"
                )
                .foregroundStyle(model.region == nil ? .secondary : .primary)
                Spacer()
                Button(action: model.chooseRegion) { Image(systemName: "viewfinder") }
                  .help("撮影範囲を選択").accessibilityLabel("撮影範囲を選択")
              }
            }
            setting("次ページの位置", icon: "arrow.right") {
              HStack {
                Text(model.nextPoint.map { "X \(Int($0.x))  /  Y \(Int($0.y))" } ?? "未選択")
                  .foregroundStyle(model.nextPoint == nil ? .secondary : .primary)
                Spacer()
                Button(action: model.chooseNext) { Image(systemName: "cursorarrow.click") }
                  .help("次ページのボタン位置を選択").accessibilityLabel("次ページのボタン位置を選択")
              }
            }
            Divider()
            HStack {
              Text("ページ数")
              Spacer()
              TextField("", value: $model.pageCount, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(width: 72)
                .accessibilityLabel("ページ数")
              Stepper("", value: $model.pageCount, in: 1...5000).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("ページ切替後の待ち時間")
                Spacer()
                Text(String(format: "%.1f 秒", model.delay)).monospacedDigit().foregroundStyle(
                  .secondary)
              }
              Slider(value: $model.delay, in: 0.5...10, step: 0.5)
                .accessibilityLabel("ページ切替後の待ち時間")
            }
            Picker("PDFの用紙", selection: $model.paper) {
              ForEach(Paper.allCases) { Text($0.rawValue).tag($0) }
            }
            Toggle("同じ画面が続いたら停止", isOn: $model.stopOnDuplicate)
            Divider()
            permission("画面収録", granted: model.screenAllowed, action: model.allowScreen)
            permission("アクセシビリティ", granted: model.clickAllowed, action: model.allowClick)
          }.frame(width: 285).disabled(model.isRunning)

          VStack(spacing: 12) {
            ZStack {
              RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor))
              if let preview = model.preview {
                Image(nsImage: preview).resizable().scaledToFit().padding(8)
              } else {
                Image(systemName: "photo").font(.system(size: 40, weight: .ultraLight))
                  .foregroundStyle(.tertiary)
              }
            }.frame(width: 350, height: 270)
              .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.18)))
            HStack {
              Text("プレビュー").font(.system(size: 12)).foregroundStyle(.secondary)
              Spacer()
              Button(action: model.testCapture) { Label("テスト撮影", systemImage: "camera") }
                .disabled(model.region == nil || model.isRunning || !model.screenAllowed)
            }
            if model.isRunning {
              ProgressView(value: Double(model.completed), total: Double(max(model.pageCount, 1)))
              Text("\(model.completed) / \(model.pageCount) ページ").font(.system(size: 12))
                .monospacedDigit()
            }
            if model.outputURL != nil {
              HStack {
                Button(action: model.openPDF) { Label("PDFを開く", systemImage: "doc") }
                Button(action: model.revealPDF) { Image(systemName: "folder") }.help("Finderで表示")
              }
            }
          }.frame(width: 350)
        }.padding(22)
      }
      if let error = model.error {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Text(error).font(.system(size: 12)).textSelection(.enabled)
          Spacer()
        }.padding(.horizontal, 22).padding(.bottom, 14)
      }
      Divider()
      HStack {
        if model.isRunning {
          Button(role: .destructive, action: model.stop) { Label("停止", systemImage: "stop.fill") }
        }
        Spacer()
        Button(action: model.start) { Label("撮影してPDFに保存", systemImage: "play.fill") }
          .buttonStyle(.borderedProminent).tint(.teal)
          .disabled(
            model.isRunning || model.region == nil || model.pageCount < 1 || model.pageCount > 5000
              || (model.pageCount > 1 && model.nextPoint == nil))
      }.padding(18)
    }.frame(width: 725, height: 620).background(Color(nsColor: .windowBackgroundColor))
  }

  private func setting<Content: View>(
    _ title: String, icon: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(
        .secondary)
      content()
    }
  }

  private func permission(_ name: String, granted: Bool, action: @escaping () -> Void) -> some View
  {
    HStack {
      Image(systemName: granted ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(granted ? Color.teal : Color.secondary)
      Text(name).font(.system(size: 12))
      Spacer()
      if !granted { Button("許可", action: action).controlSize(.small) }
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var model: CaptureModel!
  var window: NSWindow!

  func applicationDidFinishLaunching(_ notification: Notification) {
    model = CaptureModel()
    let hosting = NSHostingView(rootView: ContentView(model: model))
    window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 725, height: 620),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "ページキャプチャ"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = hosting
    window.center()
    model.mainWindow = window
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "ページキャプチャを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    NSApp.mainMenu = menu
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if model.isRunning {
      model.stop()
      return false
    }
    NSApp.terminate(nil)
    return true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if model.isRunning {
      model.stop()
      return .terminateCancel
    }
    return .terminateNow
  }
}

@main
enum EntryPoint {
  @MainActor static func main() {
    if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--render-ui" {
      do {
        try SelfTest.renderUI(
          directory: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
      } catch {
        fputs("UI RENDER FAILED: \(error)\n", stderr)
        exit(1)
      }
      return
    }
    if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--self-test" {
      do {
        try SelfTest.run(
          directory: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
      } catch {
        fputs("SELF TEST FAILED: \(error)\n", stderr)
        exit(1)
      }
      return
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
  }
}

enum SelfTest {
  static func fixture(index: Int) -> CGImage {
    let context = CGContext(
      data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
    context.setFillColor([NSColor.systemRed, .systemTeal, .systemYellow][index].cgColor)
    context.fill(CGRect(x: 80, y: 80, width: 1040, height: 640))
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 100, y: 620, width: 150 + index * 120, height: 70))
    return context.makeImage()!
  }

  @MainActor static func renderUI(directory: URL) throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for populated in [false, true] {
      let model = CaptureModel(observePermissions: false)
      if populated {
        model.preview = NSImage(cgImage: fixture(index: 0), size: CGSize(width: 1200, height: 800))
        model.status = "完了 · 3ページ保存済み"
        model.completed = 3
        model.outputURL = directory.appendingPathComponent("example.pdf")
        model.error = "ページが変わらなかったため停止しました。最終ページ、または次ページのボタン位置を確認してください。"
      }
      let view = NSHostingView(rootView: ContentView(model: model))
      view.frame = CGRect(x: 0, y: 0, width: 725, height: 620)
      let window = NSWindow(
        contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.contentView = view
      window.appearance = NSAppearance(named: .aqua)
      view.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw CaptureError.message("UI bitmap unavailable")
      }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CaptureError.message("UI PNG unavailable")
      }
      try data.write(
        to: directory.appendingPathComponent(populated ? "completed.png" : "initial.png"))
    }
    print("PASS: offscreen UI rendered")
  }

  static func run(directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var urls: [URL] = []
    for index in 0..<3 {
      let image = fixture(index: index)
      let url = directory.appendingPathComponent("test-\(index).png")
      try ImageTools.save(image, to: url)
      let reread = try ImageTools.load(url)
      guard reread.width == 1200, reread.height == 800,
        ImageTools.difference(ImageTools.fingerprint(image), ImageTools.fingerprint(reread)) == 0
      else {
        throw CaptureError.message("PNG roundtrip failed")
      }
      urls.append(url)
    }
    guard
      ImageTools.difference(
        ImageTools.fingerprint(try ImageTools.load(urls[0])),
        ImageTools.fingerprint(try ImageTools.load(urls[1]))) > 0.5
    else {
      throw CaptureError.message("Page difference detection failed")
    }
    let a = ImageTools.fingerprint(try ImageTools.load(urls[0]))
    let b = ImageTools.fingerprint(try ImageTools.load(urls[1]))
    var gate = FrameGate(previous: a)
    guard !gate.accepts(a), !gate.accepts(a), !gate.accepts(b), gate.accepts(b), !gate.accepts(a)
    else {
      throw CaptureError.message("Stable-frame / duplicate gate failed")
    }
    var firstPage = FrameGate(previous: nil)
    guard !firstPage.accepts(a), firstPage.accepts(a) else {
      throw CaptureError.message("Initial-page stability failed")
    }
    for paper in Paper.allCases {
      let url = directory.appendingPathComponent("\(paper.id).pdf")
      try PDFExporter.write(images: urls, to: url, paper: paper)
      // Exercise replacement as well as first creation.
      try PDFExporter.write(images: urls, to: url, paper: paper)
      guard let pdf = PDFDocument(url: url), pdf.pageCount == 3 else {
        throw CaptureError.message("PDF page count failed")
      }
      let expected = paper.size(for: try ImageTools.load(urls[0]))
      guard let first = pdf.page(at: 0),
        abs(first.bounds(for: .mediaBox).width - expected.width) < 0.1,
        abs(first.bounds(for: .mediaBox).height - expected.height) < 0.1
      else {
        throw CaptureError.message("PDF page dimensions failed")
      }
      for index in 0..<urls.count {
        let page = pdf.page(at: index)!.thumbnail(
          of: CGSize(width: 900, height: 900), for: .mediaBox)
        guard let rendered = page.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
          throw CaptureError.message("PDF page render failed")
        }
        let actual = ImageTools.fingerprint(rendered)[32 * 64 + 32]
        let expected = ImageTools.fingerprint(try ImageTools.load(urls[index]))[32 * 64 + 32]
        guard abs(Int(actual) - Int(expected)) <= 6 else {
          throw CaptureError.message("PDF page order / content failed")
        }
      }
      let thumbnail = first.thumbnail(of: CGSize(width: 1000, height: 1000), for: .mediaBox)
      guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw CaptureError.message("PDF rendering failed")
      }
      try ImageTools.save(image, to: directory.appendingPathComponent("\(paper.id)-render.png"))
    }
    let partial = directory.appendingPathComponent("partial.pdf")
    try PDFExporter.write(images: [urls[0]], to: partial, paper: .landscape)
    guard PDFDocument(url: partial)?.pageCount == 1 else {
      throw CaptureError.message("Partial PDF save failed")
    }
    let originalData = try Data(contentsOf: partial)
    let missing = directory.appendingPathComponent("missing-\(UUID().uuidString).png")
    var failed = false
    do { try PDFExporter.write(images: [urls[0], missing], to: partial, paper: .landscape) } catch {
      failed = true
    }
    guard failed, try Data(contentsOf: partial) == originalData else {
      throw CaptureError.message("Failed export replaced existing PDF")
    }
    failed = false
    do { try PDFExporter.write(images: [], to: partial, paper: .landscape) } catch { failed = true }
    guard failed, try Data(contentsOf: partial) == originalData else {
      throw CaptureError.message("Empty export replaced existing PDF")
    }
    if let screen = NSScreen.screens.first {
      let rect = CGRect(
        x: screen.frame.minX + 25, y: screen.frame.maxY - 125, width: 80, height: 100)
      let region = Region(cocoaRect: rect, screen: screen)
      guard region.localRect == CGRect(x: 25, y: 25, width: 80, height: 100) else {
        throw CaptureError.message("Screen coordinate conversion failed")
      }
    }
    print(
      "PASS: PNG roundtrip, stable-frame and duplicate gates, PDF formats / page order / overwrite / render / partial save / failure preservation; screen coordinates checked when a display is available"
    )
  }
}
