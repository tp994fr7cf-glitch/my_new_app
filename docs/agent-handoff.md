# 引き継ぎノート（my_new_app / 質問・引用メモ機能）

最終更新: 2026-06-30
対象リポジトリ: tp994fr7cf-glitch/my_new_app
本番 Web: https://my-new-app-naona-20260523.web.app
Firebase プロジェクト: my-new-app-naona-20260523

---

## 1. ユーザーについて

- 日本人・Flutter/Firebase 初学者。専門用語は噛み砕いて説明する。
- 説明スタイル: 小学生にもわかるくらい丁寧に、ステップごとに。ただし技術的な正確さは維持する。
- 言語: 常に日本語で返答する（英語に切り替えない）。
- 作業フロー（ユーザー側）:
  1. iPhone Cursor / Cloud Agent で修正 → PR マージ
  2. Web（Firebase Hosting）で挙動確認
  3. PC で git pull origin main
  4. エミュレータ再起動（必要時）
- PowerShell コマンドはコピペ用にそのまま渡すと喜ぶ。

---

## 2. 開発・修正のスタイル（エージェント向け）

### 基本方針

1. 最小限の diff — 依頼と無関係な変更をしない。
2. 既存の意図を壊さない — 特に以下は変更禁止の前提で読む:
   - 無題メモ: quotedNoteTitle / quotedNoteBody は 空なら null で保存（Firestore rules 用。意図的）。
   - 表示は quotedNoteId の有無で判定（PR #3）。
3. 過剰設計しない — 1〜2行で済むならヘルパー化しない。
4. 調査 → 修正 — ユーザーが「調査のみ」と言ったら実装しない。
5. テスト — 意味のあるものだけ。自明なテストは増やさない。

### Git / PR ルール（Cloud Agent）

- ブランチ名: cursor/<説明的な名前>-206d
- main から分岐 → コミット → git push -u origin <branch> → PR 作成
- firestore.rules を変えたら ユーザーに firebase deploy --only firestore:rules を案内（自動デプロイされない）
- Hosting は main マージで GitHub Actions デプロイ。CI が赤 × でもビルド成功＋FAILED_PRECONDITION（同一バージョン再リリース）のことが多い

### ローカル確認（ユーザー PC）

cd C:\Users\naona\StudioProjects\my_new_app
git checkout main
git pull origin main
flutter pub get
flutter test test/quoted_note_citation_validation_test.dart test/lesson_question_answer_write_preflight_test.dart test/lesson_interaction_service_test.dart

Firestore rules デプロイ（rules 変更時のみ）:

firebase use my-new-app-naona-20260523
firebase deploy --only firestore:rules

---

## 3. 今回までに完了した PR と状態

| PR | 内容 | ユーザー確認 |
|---|---|---|
| #3 | 無題メモ引用の表示修正（quotedNoteId 基準） | Web OK |
| #4 | 「返信先を解除」で引用が消えないよう分離 | Web OK |
| #5 | 他人メモ引用の preflight + 400ms リトライ | 部分改善のみ |
| #6 | 回答投稿の全文 preflight + rules 整合 + リトライ 500/1000/1500ms | ほぼ改善 |
| #7 | 1回目投稿後 UI が固まる問題（ボタン灰色・一覧未反映） | Web OK（最終確認済） |

現在の main 先端: 3f44463（PR #7 マージ）

---

## 4. 引用メモ・回答投稿の技術概要

### アーキテクチャ

- 保存: users/{uid}/lessonQuestionAnswers + 条件付きで publicLessonQuestionAnswers（ミラー）
- 検証: Firestore rules が最終判定。アプリ側 preflight で permission-denied を減らす
- 引用 preflight: lib/utils/quoted_note_citation_validation.dart
- 回答投稿 preflight: lib/utils/lesson_question_answer_write_preflight.dart
- UI: lib/screens/lesson_questions_page.dart

### PR #6

- 親質問の公開状態・lessonQuestionsPublicEnabled・投稿者/質問者の制限も server read で preflight
- 引用スナップショットは Firestore 生の title/body から生成（空は null）
- firestore.rules: title/body フィールド欠落も空扱い
- commit 失敗時 最大4回（0 + 500 + 1000 + 1500 ms）リトライ

### PR #7（UI）

- 保存成功時 _locallySavedAnswers に即時マージ → stream 反映前でも表示
- _isSaving を finally で必ず false
- 引用ドロップダウンに ValueKey('quoted-note-$_quotedNoteId')
- _saveAnswer 戻り値: Future<LessonQuestionAnswer?>

### 絶対に壊さないこと

- 無題メモ: 空タイトル → quotedNoteTitle: null で保存
- 表示: quotedNoteId があれば引用 UI（title の isNotEmpty では判定しない）

### 既知の落とし穴

1. preflight と rules のタイミング差 → リトライで緩和（PR #6）
2. DropdownButtonFormField の initialValue → Key で再構築（PR #7）
3. const Duration x = list.first → Web ビルド失敗（49b3848 で修正）
4. GitHub Actions Hosting 赤 × でもアップロード済みのことがある

---

## 5. 主要ファイル

| ファイル | 役割 |
|---|---|
| lib/screens/lesson_questions_page.dart | 質問・回答 UI、保存、stream |
| lib/utils/quoted_note_citation_validation.dart | 引用 preflight |
| lib/utils/lesson_question_answer_write_preflight.dart | 回答 preflight |
| firestore.rules | 引用 snapshot、親質問、公開ミラー |
| docs/quotable-notes-fallback-memo.md | 引用候補 stream の legacy 意図 |

---

## 6. ユーザー最終確認（2026-06-30）

Web で確認しました。直っていました。
（他人メモ引用 → 親質問へ回答 → 1回投稿 → ボタン復帰 & 一覧即反映 OK）

---

## 7. 新エージェントへの最初の一手

1. git pull origin main — 3f44463 以降か確認
2. 引用・回答系 → preflight + rules + UI ローカルマージの3層を疑う
3. rules 変更 → Firestore deploy をユーザーに案内
4. 修正後 → PR → マージ → Web 確認手順を日本語で渡す
