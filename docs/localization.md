# Localization / 翻訳

PageCapture uses macOS bundle localization. Japanese and English translations are stored outside the Swift UI and capture code.

| File | Purpose |
| --- | --- |
| `Resources/ja.lproj/Localizable.strings` | Japanese UI, statuses, tooltips, and errors |
| `Resources/en.lproj/Localizable.strings` | English UI, statuses, tooltips, and errors |
| `Resources/en.lproj/Localizable.stringsdict` | English singular and plural page counts |
| `Resources/*/InfoPlist.strings` | Localized display name and capture-permission explanation |
| `Localization.swift` | Typed translation keys and Foundation lookup helpers |

Normally, macOS selects the app language. English is the development language and fallback. Restart the app after changing the app-specific language in macOS.

## Editing Translations

Keep the same keys in both `Localizable.strings` files. Preserve format arguments and their order: `%ld` for integers, `%.1f` for the wait time, and `%@` for text such as a folder path or an underlying error. Do not concatenate translated sentence fragments in Swift.

Add new UI keys to `L10n.Key`, then provide both translations. English page-count messages use the `one` and `other` variants in `Localizable.stringsdict`.

```bash
ARCHS="arm64 x86_64" bash build.sh
RENDER_UI=1 bash scripts/test.sh
```

Tests check key parity, format arguments, localized metadata, plural forms, and fallback behavior. UI renders are saved in `.build/ui/ja` and `.build/ui/en`. Each contains initial, completed, running, and long-error states. Inspect both languages for clipping and wrapping.

For repeatable developer checks, `PAGECAPTURE_LANGUAGE=ja` or `PAGECAPTURE_LANGUAGE=en` temporarily overrides the language for that process. It does not save or change macOS settings.

## 日本語

文言の修正は`Resources/ja.lproj`と`Resources/en.lproj`で行います。日本語・英語で同じキーを用意し、差し込み値の個数・型・順序を合わせてください。新しいキーは`Localization.swift`の`L10n.Key`にも追加します。

通常の表示言語はmacOSに従います。翻訳が見つからない言語では英語を使います。画面、エラー、ツールチップ、進捗、保存ファイル名、権限の説明を翻訳対象にしています。

`RENDER_UI=1 bash scripts/test.sh`で両言語の画面を生成し、文字のはみ出しや改行を確認します。翻訳だけの変更でも、差し込み値と単数・複数表現のテストを実行してください。
