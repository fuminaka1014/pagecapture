# Contributing

小さな修正、再現手順、動作確認の報告を歓迎します。

## ローカル確認

```bash
bash build.sh
bash scripts/test.sh
RENDER_UI=1 bash scripts/test.sh
```

撮影・クリック・停止に関わる変更では、`docs/manual-testing.md`の手順も確認します。自動テストは画面を撮影せず、実際のクリックも送信しません。

## IssueとPull Request

- macOSのバージョンとApple Silicon / Intelの区別を記載してください。
- 再現手順と、期待する結果・実際の結果を記載してください。
- スクリーンショットは個人情報を含まない合成資料で撮影してください。
- 撮影範囲内の書籍や教材、認証URL、認証情報を添付しないでください。
- Pull Requestは目的を絞り、動作の変更と検証結果を説明してください。

このプロジェクトへのコードや文書のコントリビューションは、別途合意がない限りプロジェクトと同じMIT Licenseで提供するものとして扱います。
