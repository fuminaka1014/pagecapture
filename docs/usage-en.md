# PageCapture

Capture displayed pages and combine them into an image PDF for printing. Browsers and desktop apps with a clickable next-page button are supported.

This is an alpha build targeting macOS 14 or later, with a Universal executable for Apple Silicon and Intel. Real capture and clicking, Intel execution, and macOS 14 execution have not yet been verified.

## First Launch

1. Put `PageCapture.app` in a permanent location and open it.
2. Use the **Allow** buttons to open System Settings and grant Screen Recording and Accessibility permissions.
3. Restart PageCapture if macOS requests it.

The app is ad-hoc signed, without Developer ID signing or notarization.

## Capture

1. Display the first page in your browser or desktop app. Set the window size and zoom first.
2. Click the capture-region icon and drag around the whole page. Exclude browser tabs and controls.
3. Click the next-page-position icon and select the target app's next-page button. This selection does not turn the page.
4. Use **Test capture** to check the crop.
5. Set the page count, wait time, and PDF paper size. Begin with two or three pages.
6. Click **Capture and save PDF**, then select a destination. The current page is captured first after a three-second countdown.
7. Use **Open PDF** to review and print the result.

Do not move, resize, zoom, or change tabs in the target window during capture. Avoid mouse and keyboard input. Other windows overlapping the region can appear in screenshots. Switching to another app stops the session; switching tabs or windows within the same app is not detected.

## Stopping and Saving

- Open the PageCapture menu-bar item and choose **Stop**.
- Esc also stops capture when Accessibility permission is enabled.
- If capture is stopped or an error occurs, captured pages are still exported as a PDF.
- Numbered PNG files remain in a `filename-pages-identifier` folder beside the PDF.
- If the page remains unchanged for about 15 seconds, capture stops. Check the next-page position or whether this is the last page.
- For repeated or subtly different pages, disable **Stop on unchanged pages**.
- Increase the wait time for slow page loading. The app cannot guarantee that loading has completed.

## PDF Paper Size

- **A4 Landscape:** horizontal slides.
- **A4 Portrait:** vertically oriented books and documents.
- **Image aspect ratio:** preserves the screenshot shape without added margins.

Resolution depends on the displayed image. Use the largest view that still fits the complete page, and inspect the PDF before printing. The PDF has no OCR, searchable text, or selectable text.

## Language

Japanese and English are supported. The app follows macOS's preferred language or its app-specific language setting and falls back to English for unsupported languages. Restart it after changing the language.

## Privacy

The app uses ScreenCaptureKit for screenshots, normal mouse-click events for page turns, and Core Graphics for PDFs. It does not collect credentials, browser traffic, or account information, and does not upload captured files.

## Build from Source

With Xcode Command Line Tools installed:

```bash
bash build.sh
ARCHS="arm64 x86_64" bash build.sh
```

The app is generated at `dist/PageCapture.app`. The implementation is in `PageCapture.swift` and `Localization.swift`, with language resources under `Resources/`.

MIT License. Copyright (c) 2026 fuminaka1014.
