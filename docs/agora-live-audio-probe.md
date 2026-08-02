# Agora ライブ音声・ホワイトボード配信

Android とデスクトップ Web で、次の機能を提供します。

- 先生1人から受講者2人への音声配信
- 音声に同期させた板書、ボード切替、ズーム・パン
- 途中参加・再接続時の保存済み板書復元
- 先生による受講者の発表許可と解除
- 配信開始時からの自動録音
- おおむね10〜30秒遅れのHLS追っかけ再生
- 配信終了後、同じレッスンパートを編集可能な下書きへ変換

## セキュリティ方針

- Agora App Certificate は、Flutter、GitHub、設定ファイルへ保存しません。
- App ID と App Certificate は Firebase Secret Manager に登録します。
- トークンは Firebase Authentication を確認した Functions だけが発行します。
- 受講者用トークンには視聴権限だけを付けます。
- 先生または先生が許可した発表者だけに、音声・板書の送信権限を付けます。
- 動画の送信権限は、この検証では発行しません。
- トークンは15分で更新します。
- 録音用のCustomer Secretとクラウドストレージ鍵も、FlutterやFirestoreへ保存しません。

## Agora Console で必要な準備

1. Agoraでプロジェクトを作成する。
2. App Certificateを有効にする。
3. Co-host token authentication（共同配信者認証）を有効にする。
4. App IDとApp Certificateを確認する。

App Certificateをチャット、メール、ソースコードへ貼らないでください。

## Firebaseへ秘密情報を登録

PowerShellで次を1行ずつ実行します。各コマンドの実行後に値の入力を求められるので、その場で入力します。入力した値は画面に表示されず、リポジトリにも保存されません。

```powershell
cd C:\Users\naona\StudioProjects\my_new_app
firebase functions:secrets:set AGORA_APP_ID --project my-new-app-naona-20260523
firebase functions:secrets:set AGORA_APP_CERTIFICATE --project my-new-app-naona-20260523
firebase functions:secrets:set AGORA_CUSTOMER_ID --project my-new-app-naona-20260523
firebase functions:secrets:set AGORA_CUSTOMER_SECRET --project my-new-app-naona-20260523
firebase functions:secrets:set AGORA_GCS_ACCESS_KEY --project my-new-app-naona-20260523
firebase functions:secrets:set AGORA_GCS_SECRET_KEY --project my-new-app-naona-20260523
firebase functions:secrets:set AGORA_GCS_BUCKET --project my-new-app-naona-20260523
```

Firebase Functionsのデプロイには、FirebaseプロジェクトのBlazeプランが必要になる場合があります。

`AGORA_GCS_ACCESS_KEY`と`AGORA_GCS_SECRET_KEY`には、Google Cloud
Storageの「相互運用性」画面で作成したHMACアクセスキーを登録します。
`AGORA_GCS_BUCKET`にはバケット名だけを登録してください。

Functionsの実行サービスアカウントには、そのバケットの
`Storage オブジェクト閲覧者`権限が必要です。配信終了後、Functionsが
録音MP4を既定Firebase Storageのレッスン用パスへコピーします。この権限が
不足した場合も配信自体は終了でき、先生のレッスン編集画面から保存処理を
再試行できます。

## 録画元アーカイブの管理スクリプト

`scripts/prune_live_audio_probe_raw.mjs` は、何も指定しなければ削除しない
`plan` モードです。`apply` は取り消せないため、現在のplanが表示した確認
トークンと、プロジェクト・2つのバケットの再入力がすべて一致した場合だけ
実行できます。配信中・確定処理中のセッションや、安全でないファイル構成が
1つでも見つかるとapplyを拒否します。

これは既存データを一度だけ整理する管理用スクリプトです。定期Functionの
「9GBを超えたら5GBまで整理」とは異なり、現在の合計が9GB未満でも、安全確認を
通過した録画元セッションをすべてplanへ含めます。完成MP4を確認できない
リンク済み録画や、再試行可能な録画は保護され、削除対象に入りません。

このスクリプトはAgoraのHMACアクセスキーを使いません。実行前にGoogle Cloud
CLIのApplication Default Credentials（ADC）へログインしてください。
実行ユーザーには、Firestoreのセッション文書を読む権限、両バケットの
オブジェクト一覧・メタデータを読む権限が必要です。apply時だけ、録画元
バケットにオブジェクト削除権限も必要です。サービスアカウント鍵を使う場合は
`GOOGLE_APPLICATION_CREDENTIALS` でリポジトリ外のファイルを指定し、鍵の内容を
コマンドや設定ファイルへ書かないでください。

初回準備:

```powershell
cd C:\Users\naona\StudioProjects\my_new_app
gcloud auth application-default login
gcloud auth application-default set-quota-project my-new-app-naona-20260523
npm --prefix functions install
npm --prefix functions run build
```

まず読み取り専用planを実行します。`$RAW_BUCKET` はSecret Managerの
`AGORA_GCS_BUCKET`に登録した「バケット名だけ」を手元で入力します。値を
ソースコードや文書へ保存しないでください。

```powershell
cd C:\Users\naona\StudioProjects\my_new_app
$PROJECT_ID = "my-new-app-naona-20260523"
$RAW_BUCKET = "<AGORA_GCS_BUCKETのバケット名>"
$COMPLETED_COPY_BUCKET = "my-new-app-naona-20260523.firebasestorage.app"
node scripts/prune_live_audio_probe_raw.mjs --mode plan --project $PROJECT_ID --raw-bucket $RAW_BUCKET --completed-copy-bucket $COMPLETED_COPY_BUCKET
```

出力の`selectedSessions`、`protectedSessions`、容量、プレフィックスを確認します。
`scope.selectionPolicy`が`allEligible`であることも確認してください。
問題がない場合だけ、同じ出力の`applyConfirmationToken`を使ってapplyします。
次のコマンドは実際に削除するため、plan確認前には実行しないでください。

```powershell
cd C:\Users\naona\StudioProjects\my_new_app
$PLAN_TOKEN = "<plan出力のapplyConfirmationToken>"
node scripts/prune_live_audio_probe_raw.mjs --mode apply --project $PROJECT_ID --raw-bucket $RAW_BUCKET --completed-copy-bucket $COMPLETED_COPY_BUCKET --confirm-project $PROJECT_ID --confirm-raw-bucket $RAW_BUCKET --confirm-completed-copy-bucket $COMPLETED_COPY_BUCKET --confirm-plan $PLAN_TOKEN --acknowledge-permanent-delete DELETE_RAW_ARCHIVES_PERMANENTLY
```

apply開始直前にもplanを取り直します。対象や容量が変わって確認トークンが一致
しなくなった場合は削除せず終了するため、新しいplanをもう一度確認してください。

## 検証用バックエンドの反映

```powershell
cd C:\Users\naona\StudioProjects\my_new_app
firebase deploy --only functions,firestore:rules --project my-new-app-naona-20260523
```

通常のHostingや既存レッスンデータは、このコマンドでは変更しません。

## 検証画面の起動

検証画面は通常起動では表示されません。

Web:

```powershell
cd C:\Users\naona\StudioProjects\my_new_app
flutter run -d chrome --dart-define=ENABLE_LIVE_AUDIO=true
```

Android:

```powershell
cd C:\Users\naona\StudioProjects\my_new_app
flutter run --dart-define=ENABLE_LIVE_AUDIO=true
```

## 確認手順

1. 先生がレッスン編集画面で「パートを追加」→「ライブ音声配信」を選ぶ。
2. 「配信画面を開く」を押し、「先生として配信を開始」から配信コードをコピーする。
3. 受講者2人が「ライブ音声・板書配信」を開き、配信コードを入力する。
4. 先生の音声が受講者2人へ聞こえることを確認する。
5. 先生が書いた線が、音声と不自然にずれず表示されることを確認する。
6. ボード切替とズーム・パンが受講者へ反映されることを確認する。
7. 受講者を一度退出・再参加させ、保存済みの板書と表示状態が戻ることを確認する。
8. 先生が受講者1人の発表を許可し、その受講者の音声と板書が全員へ届くことを確認する。
9. 先生が発表許可を解除し、受講者が視聴専用へ戻ることを確認する。
10. 配信開始から30秒以上経過後、受講者が追っかけ再生とライブへ戻る操作を確認する。
11. AndroidとWebの組み合わせを入れ替えて同じ確認を行う。
12. 先生が「配信を終了」を押す。
13. レッスン編集画面へ戻り、録音とBoardSetが下書きとして読み込まれることを確認する。

本番Firebaseへ反映する前に、必ずテストアカウントと短い配信でこの一連の確認を行ってください。

追っかけ再生では、参加者認証後に有効期限付きの再生URLを発行し、Functionsが
HLSマニフェスト内の各ファイルを同じ保護された経路へ書き換えます。
GCSのオブジェクト名やHMAC秘密鍵をクライアントへ渡すことはありません。
