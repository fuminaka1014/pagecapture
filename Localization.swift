import Foundation

enum L10n {
  enum Key: String, CaseIterable {
    case appName = "app.name"
    case paperLandscape = "paper.landscape"
    case paperPortrait = "paper.portrait"
    case paperOriginal = "paper.original"
    case imageCreateError = "error.image.create"
    case imageSaveError = "error.image.save"
    case imageLoadError = "error.image.load"
    case noPagesError = "error.no_pages"
    case pdfCreateError = "error.pdf.create"
    case regionRequiredError = "error.region.required"
    case displayMissingError = "error.display.missing"
    case displayChangedError = "error.display.changed"
    case screenPermissionError = "error.permission.screen"
    case clickPermissionError = "error.permission.click"
    case targetMissingError = "error.target.missing"
    case clickPermissionRevokedError = "error.permission.revoked"
    case pdfSaveError = "error.pdf.save"
    case targetExitedError = "error.target.exited"
    case targetChangedError = "error.target.changed"
    case clickPointChangedError = "error.click_point.changed"
    case screenUnstableError = "error.screen.unstable"
    case pageUnchangedError = "error.page.unchanged"
    case clickCreateError = "error.click.create"
    case selectorNext = "selector.next"
    case selectorRegion = "selector.region"
    case idle = "status.idle"
    case testCapturing = "status.test.capturing"
    case testComplete = "status.test.complete"
    case testCancelled = "status.test.cancelled"
    case captureFailed = "status.capture.failed"
    case countdown = "status.countdown"
    case capturing = "status.capturing"
    case pdfSaving = "status.pdf.saving"
    case stoppedSaved = "status.stopped.saved"
    case complete = "status.complete"
    case partialSaved = "status.partial.saved"
    case pdfSaveFailed = "status.pdf.failed"
    case cancelled = "status.cancelled"
    case defaultFileName = "file.default_name"
    case captureRegion = "label.capture_region"
    case nextPagePosition = "label.next_page_position"
    case notSelected = "label.not_selected"
    case regionSize = "format.region_size"
    case pointCoordinates = "format.point_coordinates"
    case chooseRegion = "action.choose_region"
    case chooseNext = "action.choose_next"
    case pageCount = "label.page_count"
    case waitAfterTurn = "label.wait_after_turn"
    case waitValue = "format.wait_value"
    case pdfPaper = "label.pdf_paper"
    case stopOnDuplicate = "label.stop_on_duplicate"
    case screenPermission = "permission.screen"
    case accessibilityPermission = "permission.accessibility"
    case preview = "label.preview"
    case testCapture = "action.test_capture"
    case progressPages = "format.progress_pages"
    case openPDF = "action.open_pdf"
    case revealPDF = "action.reveal_pdf"
    case stop = "action.stop"
    case captureAndSave = "action.capture_and_save"
    case grantPermission = "action.grant_permission"
    case quitApp = "action.quit"
  }

  static var language: String {
    // The override is for repeatable tests; normal launches use macOS's app language.
    resolvedLanguage(ProcessInfo.processInfo.environment["PAGECAPTURE_LANGUAGE"])
  }

  private static func resolvedLanguage(_ requested: String?) -> String {
    if let requested {
      return Bundle.preferredLocalizations(from: ["en", "ja"], forPreferences: [requested]).first
        ?? "en"
    }
    return Bundle.main.preferredLocalizations.first ?? "en"
  }

  private static func bundle(language: String?) -> Bundle {
    let selected = resolvedLanguage(
      language ?? ProcessInfo.processInfo.environment["PAGECAPTURE_LANGUAGE"])
    guard let path = Bundle.main.path(forResource: selected, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else { return Bundle.main }
    return bundle
  }

  static func text(_ key: Key, language: String? = nil) -> String {
    bundle(language: language).localizedString(
      forKey: key.rawValue, value: nil, table: "Localizable")
  }

  static func format(_ key: Key, language: String? = nil, _ arguments: CVarArg...) -> String {
    String(
      format: text(key, language: language),
      locale: Locale(
        identifier: resolvedLanguage(
          language ?? ProcessInfo.processInfo.environment["PAGECAPTURE_LANGUAGE"])),
      arguments: arguments)
  }
}
