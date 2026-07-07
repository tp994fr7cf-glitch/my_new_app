# 引き継ぎノート（my_new_app / レッスン再生・ホワイトボード修正後）

最終更新: 2026-07-07
対象リポジトリ: https://github.com/tp994fr7cf-glitch/my_new_app
本番 Web: https://my-new-app-naona-20260523.web.app
Firebase プロジェクト: my-new-app-naona-20260523
Firebase Console: https://console.firebase.google.com/project/my-new-app-naona-20260523/overview

---

## 1. ユーザーについて

- GitHub アカウント: tp994fr7cf-glitch（メール: naonaonaoya70833@gmail.com）
- 日本人・Flutter/Firebase 初学者。専門用語は避け、小学生にもわかるくらい丁寧に説明する。
- 言語: 常に日本語で返答する。
- ローカル PC: Windows。いざとなれば PowerShell を使える。
- PowerShell でコマンドを実行するときは、**必ず最初に** 以下を実行する:

```powershell
cd C:\Users\naona\StudioProjects\my_new_app
```

- 作業フロー（ユーザー側）:
  1. Cloud Agent で修正 → PR マージ（エージェントが進める）
  2. Web（Firebase Hosting）とエミュレータで確認
  3. PC で git pull origin main
  4. 必要なら flutter pub get / flutter run

---

## 2. 開発・修正のスタイル（エージェント向け）

1. 最小限の diff — 依頼と無関係な変更をしない。
2. 既存の意図を壊さない — 読んでから直す。
3. 過剰設計しない（PR #50〜#57 で層を重ねすぎた反省あり）。
4. ユーザーが「調査のみ」と言ったら実装しない。
5. テスト — 意味のあるものだけ。フェイクだけ通るテストで安心しない（実機未検証の穴あり）。
6. 修正完了後は、ユーザーに許可を取らず PR 作成 → マージ → デプロイまで進める。

### Git / PR ルール（Cloud Agent）

- ブランチ名: `cursor/<説明的な名前>-c48f`（Cloud Agent 環境）
- main から分岐 → コミット → `git push -u origin <branch>` → PR 作成 → マージ
- Hosting は main マージで GitHub Actions が自動デプロイ
- **Storage / Firestore ルールは自動デプロイが失敗しやすい**。rules を変えたらユーザーに手動デプロイを案内

---

## 3. 現在の main の状態（2026-07-07）

**main 先端: c24f274（PR #57 マージ後）**

### ユーザー確認済み — 直っていること（回帰なし）

| 項目 | 状態 |
|------|------|
| 動画再生中に音声へ巻き戻し → 時間表示が止まる | **直っている**（#54） |
| 時間表示・スライダーのガタつき | **直っている**（#55） |
| レッスン開き直しの誤った「視聴完了」表示 | **直っている**（#55） |
| 動画パートのホワイトボード | **滑らか** |
| 一時停止 → シーク → 再生 | 問題なさそう |

### 未解決 — 最優先バグ

| 症状 | 詳細 |
|------|------|
| **音声パートのホワイトボードが1秒ごとにカクッと進む** | 動画パートは滑らか。PR #56・#57 後もエミュレータで **未改善**（ユーザー 2026-07-07 確認） |

テストレッスン: 音声 90秒（WAV）→ 動画 90秒（MP4）= 合計 3分

---

## 4. 再生・ホワイトボード問題の経緯（要約）

### 元の大きなバグ（解決済み）

- 動画再生中に音声へ巻き戻すと、音声は鳴るが **時間表示が止まる**
- 原因: 再生中の巻き戻しと、一時停止→巻き戻し→再生で **別の処理** になっていた
- 修正: パート切替時に pause → seek → play（#54）

### 副作用として入った制限

- 音声の位置通知を **1秒に1回** に制限（時間表示の安定化）
- その結果、ホワイトボードも1秒刻みに見えるようになった

### ホワイトボード修正の試行（未解決）

| PR | 内容 | 結果 |
|----|------|------|
| #56 | ホワイトボードだけ50msごとに更新（案B） | 実機で変化なし |
| #57 | 音声の壁時計アンカーを常時有効化 + プレイヤー isPlaying で更新 | 実機で変化なし |

### 調査で分かったこと

1. ホワイトボードは点ごとの時刻と再生位置を比べて線を伸ばす（`visibleWhiteboardStrokes`）
2. 動画は位置がこまめに来る → 滑らか
3. 音声は `positionStream` が1秒刻み（意図的）
4. #56/#57 は `liveGlobalPositionSec`（細かい位置のはず）を読む設計だが **実機では効いていない**
5. テストは `WallClockFakeLessonMediaPlayback` で通るが、**本物の just_audio + エミュレータでは未検証**
6. **追加の可能性**: 保存済みストロークの点タイムスタンプが1秒刻み（先生が音声パートで録画したとき `globalPositionStream` が粗い）

### 次の agent が疑うべきポイント

1. 実機で `liveGlobalPositionSec` が本当に sub-second で変わっているか（ログ or DevTools）
2. ホワイトボードレイヤーの `anchorType`（global / segment）と `segmentId` の組み合わせ
3. ストロークの `hasPointTimestamps` と各点の `timestampSec` の間隔（Firestore 上の実データ）
4. `LessonPlaybackSyncedWhiteboard` のタイマーが動いているか、`playback.isPlaying` の状態
5. 先生エディタ（`lesson_whiteboard_editor_panel.dart`）も `globalPositionStream` 依存 → 録画データが粗い可能性
6. フェイクテストだけでマージしない。エミュレータ or 実機確認を前提にする

---

## 5. 完了 PR（#49〜#57）

| PR | 内容 |
|----|------|
| #49 | プレイヤー保持・先読み・スライダーシーク改善 |
| #50 | シーク後表示同期・動画リセット |
| #51 | セグメント/一時停止同期 |
| #52 | 音声ポーリング・スライダー楽観更新 |
| #53 | pause-seek-play 準備・壁時計 |
| #54 | **巻き戻し時の時間表示フリーズ修正**（pause-seek-play） |
| #55 | 音声ジッター修正・レッスン開き直し表示 |
| #56 | ホワイトボード専用50ms更新ウィジェット |
| #57 | 音声壁時計アンカー常時有効化 |

---

## 6. 主要ファイル

| ファイル | 役割 |
|----------|------|
| `lib/services/lesson_media_playback.dart` | 音声/動画プレイヤー。音声の壁時計アンカー |
| `lib/services/lesson_media_playlist_playback.dart` | プレイリスト、`liveGlobalPositionSec` |
| `lib/screens/video_lesson_page.dart` | 受講者レッスン画面（表示は1秒刻み） |
| `lib/widgets/lesson_playback_synced_whiteboard.dart` | ホワイトボード専用更新（50ms） |
| `lib/widgets/lesson_whiteboard_canvas.dart` | 描画 |
| `lib/models/lesson_whiteboard.dart` | ストローク・点の時刻フィルタ |
| `lib/widgets/lesson_whiteboard_editor_panel.dart` | 先生の録画・編集 |

### テスト

- `test/lesson_media_playlist_playback_test.dart` — プレイリスト9件+live位置1件
- `test/lesson_media_playback_test.dart` — 壁時計フェイク
- `test/lesson_playback_synced_whiteboard_test.dart` — ウィジェット
- `lesson_questions_page_test.dart` — 元からハング・失敗（無関係）

---

## 7. Firebase / デプロイ

- Hosting: main マージで自動
- Storage/Firestore rules: CI 失敗しやすい。変更時は手動:

```powershell
cd C:\Users\naona\StudioProjects\my_new_app
firebase deploy --only storage,firestore:rules --project my-new-app-naona-20260523
```

- Web とエミュレータを同時操作すると activeRole がずれて保存エラーになりやすい

---

## 8. 引き継ぎ用コピペブロック（次の agent へ）

**以下を1つのブロックとしてそのままコピーすること。ブロックを分割しないこと。**

```
【引き継ぎ】my_new_app Flutter/Firebase 学習アプリ（2026-07-07）

■ リポジトリ / 環境
- GitHub: https://github.com/tp994fr7cf-glitch/my_new_app
- ユーザー: tp994fr7cf-glitch（naonaonaoya70833@gmail.com）
- ローカル: C:\Users\naona\StudioProjects\my_new_app（Windows、PowerShell 使用可）
- Firebase: my-new-app-naona-20260523
- 本番 Web: https://my-new-app-naona-20260523.web.app
- main 先端: c24f274（PR #57 マージ後）
- ブランチ名ルール（Cloud Agent）: cursor/<名前>-c48f

■ ユーザー preferences（必読）
- 常に日本語。プログラミング初心者向けに専門用語を避ける
- 小学生にでもわかるやさしい言葉で、背景を補足しつつ説明する
- 「調査のみ」と言われたら実装しない
- 修正完了後は PR→マージ→デプロイまで agent が進める（許可不要）
- PowerShell で何か実行するときは必ず最初に:
  cd C:\Users\naona\StudioProjects\my_new_app

■ いま直っていること（ユーザー 2026-07-07 確認・回帰なし）
- 動画再生中に音声へ巻き戻しても時間表示が止まらない（#54）
- 時間表示・スライダーのガタつきなし（#55）
- 視聴完了後のレッスン開き直し表示（#55）
- 動画パートのホワイトボードは滑らか

■ 未解決・最優先バグ
- 音声パートのホワイトボードが1秒ごとにカクッと進む（動画は滑らか）
- PR #56（ホワイトボード50ms更新）も #57（音声壁時計アンカー）もエミュレータで未改善
- テストレッスン: 音声90秒+動画90秒

■ 技術メモ（次がハマりどころ）
- ホワイトボードは点の timestampSec <= 再生位置 で線を伸ばす（lib/models/lesson_whiteboard.dart）
- 音声 positionStream は意図的に1秒刻み（表示安定化）。細かい位置は liveGlobalPositionSec / 壁時計アンカー想定
- #56: lib/widgets/lesson_playback_synced_whiteboard.dart（50msで liveGlobalPositionSec を読む）
- #57: lib/services/lesson_media_playback.dart（_ensurePlaybackAnchor、playing:true でアンカー）
- テストは WallClockFakeLessonMediaPlayback で通るが実機 just_audio では未確認 → フェイクだけ信頼しない
- 疑うべき: (1)実機で liveGlobalPositionSec が本当に細かく変わるか (2)ストローク点のタイムスタンプが1秒刻みで保存されていないか (3)レイヤー anchorType/segmentId (4)先生エディタの録画時位置が粗い（lesson_whiteboard_editor_panel.dart は globalPositionStream 依存）

■ 完了 PR（再生関連）
#49 seek/preload / #50 display sync / #51 segment sync / #52 audio poll / #53 playing rewind / #54 pause-seek-play（時間表示フリーズ修正）/ #55 jitter+reopen / #56 whiteboard widget / #57 wall clock anchor

■ 開発スタイル
- 最小 diff、過剰設計しない、既存意図を壊さない
- PR #50-57 は層を重ねすぎた反省。根本原因を先に実機で確認してから直す

■ ローカル確認（ユーザー PC）
cd C:\Users\naona\StudioProjects\my_new_app
git pull origin main
flutter pub get
flutter test
flutter run

■ Firebase rules（変更時のみ・手動）
cd C:\Users\naona\StudioProjects\my_new_app
firebase deploy --only storage,firestore:rules --project my-new-app-naona-20260523
（Hosting は main マージで自動。rules は CI 失敗しやすい）

■ 詳細ドキュメント
docs/agent-handoff.md
```
