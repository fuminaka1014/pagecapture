# PageCapture v0.1.0-alpha

画面のページを順番に撮影して、印刷用PDFにまとめるmacOS向けツールの初期公開版です。

撮影範囲・次ページボタン・ページ数・待ち時間を設定できます。A4横、A4縦、元画像の比率でPDFを保存し、連番PNGも残します。

## 対応環境

- macOS 14以降。
- 配布ビルドはApple Silicon / IntelのUniversalバイナリ。
- 画面収録と、自動クリック用のアクセシビリティ許可が必要。

## 検証と制限

合成画像でのPNG・PDF保存、安定フレームと重複画面の判定、部分保存、失敗時の既存PDF保持を自動検証しています。実アプリでの連続撮影・クリックとIntel Mac・macOS 14での実行は未検証です。最初は合成資料で少数ページを試してください。

画像PDFのため、OCRと文字検索には対応していません。ページ送りはクリックのみです。配布アプリはアドホック署名で、Developer ID署名とAppleの公証は行っていません。

日本語・英語の画面表示に対応し、macOSの言語設定に従います。ZIPにはアプリ、日本語・英語の使い方、MIT Licenseを含めています。

---

## English

PageCapture captures displayed pages and combines them into print-ready image PDFs on macOS. Select a capture region, next-page button, page count, and wait time. PDFs support A4 landscape, A4 portrait, and the original image aspect ratio; numbered PNGs are retained alongside the PDF.

The Universal build targets macOS 14 or later on Apple Silicon and Intel. Japanese and English interfaces follow the app's macOS language setting. Screen Recording and Accessibility permissions are required for automatic capture and clicking.

This is an alpha release. Synthetic-image and localization tests pass, but real capture and clicking, Intel execution, and macOS 14 execution remain unverified. Try a few synthetic pages first. PDFs do not include OCR or searchable text. The app is ad-hoc signed, without Developer ID signing or Apple notarization.

The ZIP includes the app, Japanese and English usage guides, and the MIT License. A SHA-256 checksum is provided separately.
