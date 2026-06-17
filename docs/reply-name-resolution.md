# 学習記録 回答コメント 判定表（仕様固定版）

## 目的
- `learning_records` の回答コメント一覧で、返信先表示名とコメント欄遷移の挙動を統一する。
- いまの機能だけでなく、将来の「講座削除/非公開」「受講停止」にも対応できる土台を先に固定する。
- 判定があいまいなときは、安全側（リンクしない、遷移しない）に倒す。

## この仕様で確定した方針
- 非公開化された「自分の回答コメント」は、現行どおり遷移可能を維持する。
- 返信先名は次の優先順で決める。
  1. 最新名（リンク可能な場合のみ）
  2. 返信時点名（`replyToDisplayName`）
  3. 親投稿時点名（親コメントの `authorName`）
  4. 役割ラベル（`先生` / `学習者`）

## 用語（初心者向け）
- 親質問: 返信元が「質問コメント」の場合の元コメント。
- 親回答: 返信元が「回答コメント」の場合の元コメント。
- 最新名: いまの公開プロフィール上の名前（講座専用表示を含む）。
- 返信時点名: 返信保存時に記録された名前（`replyToDisplayName`）。
- 親投稿時点名: 親コメントが投稿された時点での名前（`authorName`）。
- 遷移: 学習記録カードをタップして「質問コメント画面」を開くこと。

## 判定に使う入力条件（Predicate）

### 1) 返信先表示名で使う条件
- `latestNameLinkAllowed`
  - 最新名を取りに行ってよいか。
  - 条件不足または判定不能なら `false`（安全側）。
- `latestNameResolved`
  - 最新名リンクを試した結果、有効な表示名を得られたか。
- `replyTimeNameAvailable`
  - `replyToDisplayName` が空でなく、メール形式でもないか。
- `parentPostedNameAvailable`
  - 親コメント `authorName` が空でなく、メール形式でもないか。

### 2) コメント欄遷移で使う条件
- `questionOpenable`
  - 親質問が削除/非公開でなく開けるか。
- `recordAnswerOpenable`
  - この学習記録の回答コメント自体が開けるか。
  - 例外として「自分の回答コメントが先生非公開」は `true` 扱いを維持。
- `parentAnswerOpenable`
  - 親回答が必要なケースで、親回答が削除/非公開でなく開けるか。
- `parentType`
  - `question` または `answer`。

## 返信先表示名の判定表（固定）

### 共通ルール（親質問返信/親回答返信 共通）
1. `latestNameLinkAllowed == true` かつ `latestNameResolved == true`  
   -> 最新名を表示（リンクあり）
2. 上記以外で `replyTimeNameAvailable == true`  
   -> 返信時点名を表示（リンクなし）
3. 上記以外で `parentPostedNameAvailable == true`  
   -> 親投稿時点名を表示（リンクなし）
4. すべて満たさない  
   -> 役割ラベルを表示（リンクなし）

### リンク不可とみなす条件（現状+将来）
- 親質問または親回答が削除/非公開。
- 学習記録から親コメントを解決できない。
- 返信先プロフィールの公開条件を満たさない。
- 講座が削除/非公開（将来条件）。
- 返信先または自分が講座で停止状態（将来条件）。
- 判定に必要な情報が欠ける（判定不能）。

## コメント欄遷移の判定表（固定）

### A. `parentType == question`（質問への返信）
- 遷移可:
  - `recordAnswerOpenable == true` かつ `questionOpenable == true`
- 遷移不可:
  - 上記以外すべて

### B. `parentType == answer`（回答への返信）
- 遷移可:
  - `recordAnswerOpenable == true`
  - `questionOpenable == true`
  - `parentAnswerOpenable == true`
- 遷移不可:
  - 上記いずれかが `false`

### 明示的な例外（維持）
- 自分の回答コメントが先生非公開でも、`recordAnswerOpenable` は `true` 扱いで維持。
- ただし `parentType == answer` の場合は、親回答が開けない限り遷移しない。

## 将来要件の接続方法（逆算）

### 新しい集約ゲートを先に定義する
- `canLinkLatestNameGate(context)`
- `canOpenThreadGate(context)`

`context` は次の情報を受け取る前提にする。
- `courseAccessible`（講座削除/非公開でない）
- `interactionFeatureEnabled`（質問機能利用可）
- `currentUserActiveInCourse`（自分が停止されていない）
- `targetUserActiveInCourse`（返信先が停止されていない）
- `questionOpenable`
- `parentAnswerOpenable`（必要時）
- `profileVisibleForLink`

### フェイルクローズ原則
- どれか1つでも不明なら `false` を返す。
- これにより「リンクできてしまう」「開けてしまう」事故を防ぐ。

## 実装時の安全ガード（参照優先5関数）
- `lib/screens/lesson_questions_page.dart` `_resolveReplyTargetDisplayNameForPersist(...)`
- `lib/screens/lesson_questions_page.dart` `_saveAnswer(...)`
- `lib/screens/learning_records_page.dart` `_buildReplyPreviewWidget(...)`
- `lib/screens/learning_records_page.dart` `_fallbackReplyTargetDisplayName(...)`
- `lib/screens/learning_records_page.dart` `_linkedReplyTargetDisplayNameStream(...)`

## Mustテストケース（実装前提の最小セット）

### 返信先表示名
1. `latest_name_question_reply_linkable_uses_latest`
2. `latest_name_answer_reply_linkable_uses_latest`
3. `latest_blocked_uses_reply_time_snapshot`
4. `reply_time_missing_uses_parent_posted_snapshot`
5. `all_missing_falls_back_to_role_label`
6. `email_like_name_never_rendered_as_display_name`

### コメント欄遷移
7. `question_reply_openable_when_question_openable`
8. `question_reply_not_openable_when_question_unavailable`
9. `answer_reply_not_openable_when_parent_answer_unavailable`
10. `answer_reply_openable_when_parent_answer_openable`
11. `own_hidden_answer_keeps_openable_exception`

### 将来条件（実装時に有効化）
12. `link_blocked_when_course_inaccessible`
13. `navigation_blocked_when_current_user_suspended`
14. `link_and_navigation_blocked_when_target_user_suspended`

## レビュー完了の定義（Definition of Done）
- 判定表だけで「表示名」と「遷移可否」の結論を説明できる。
- 親質問返信/親回答返信/多段返信で矛盾がない。
- 現在条件と将来条件を同じゲート設計で扱える。
- Mustテストケース名が確定し、実装タスクにそのまま落とせる。
