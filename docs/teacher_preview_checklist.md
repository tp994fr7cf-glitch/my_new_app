# 先生プレビュー確認チェック（最小版）

## 目的
- 次の担当者が、先生視点の不具合有無を短時間で確認できるようにする。
- ここに書いていない詳細調査は、必要になった時だけ実施する。

## 使い方（3分）
1. 先生アカウントで対象講座を開く。
2. `プレビューを見る` -> `質問コメントを開く` を確認する。
3. `公開メモ・質問管理` で表示ラベルを確認する。
4. 学習者アカウントで「見えてはいけないもの」が見えないことを確認する。
5. NGがあれば、下の「判定表」に `NG` とメモを1行追加する。

## 判定表（OK/NG）
- [ ] 先生プレビューで `teacherOnly` 質問が一覧に出る  
  期待表示: `先生だけ表示 / 先生だけ回答可`
- [ ] 先生プレビューで `teacherOnly` メモが `先生にだけ公開` と表示される  
  NG例: `学習者にも公開` と表示される
- [ ] `公開メモ・質問管理` で `teacherOnly` の状態表示が崩れていない
- [ ] 学習者側で他人の `teacherOnly` 質問/メモは見えない
- [ ] 引用メモのラベルが `引用するメモ` になっている

## 補完（teacherOnly質問ミラー）運用メモ
- ドライラン:
  - `node "scripts/backfill_teacher_only_question_mirrors.mjs" --mode plan`
- 低リスク条件付き実行:
  - `node "scripts/backfill_teacher_only_question_mirrors.mjs" --mode apply --low-risk-limit 50`
- ロールバック:
  - `node "scripts/backfill_teacher_only_question_mirrors.mjs" --mode rollback --apply-report "<applyレポートのパス>"`

## 直近の実行結果（記録）
- 直近適用レポート:
  - `backup_snapshots/teacher_only_question_mirror_apply_2026-06-05T23-10-41-636Z.json`
- 直近確認結果:
  - `missingMirrorCount=0`（plan再実行で確認）

## 更新ルール
- このファイルは「短く保つ」。追加は最大3行まで。
- 実装が変わったら、判定表の期待表示だけ更新する。
