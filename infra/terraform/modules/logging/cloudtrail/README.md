# logging/cloudtrail

> 3省2GL観点：監査ログ（改ざん防止と長期保存）

- 全リージョン・グローバルサービスイベントを対象とした証跡を作成し、ログファイルの整合性検証を有効にする
- S3 バケットは Object Lock・バージョニング・KMS 暗号化・パブリックアクセスブロック・TLS 強制で保護する。Lifecycle で Glacier へ移行し、保存期間の経過後に削除する
- CloudWatch Logs にも送信する（検知・調査用。長期保管は S3 側で行う）
- `external_bucket_name` を指定すると、ログ集約アカウント等の既存バケットへ出力する（バケットは作成しない）

## Object Lock の注意

| 環境 | 推奨モード | 理由 |
|---|---|---|
| dev / stg | GOVERNANCE | 特別な権限があれば削除できる。検証環境の作り直しに対応できる |
| prod | COMPLIANCE | 保持期間中は root を含め誰も削除できない。**設定後に期間を短くすることも、バケットを削除することもできない** |

バケットには `prevent_destroy` を設定している。

`object_lock_enabled = false` にすると Object Lock 設定を作成しない（dev 等の検証用。ルートでは prod での無効化を validation で禁止している）。Object Lock はバケット作成後に `aws_s3_bucket_object_lock_configuration` で有効化するため、後から ON にしてもバケットは置き換わらない。一度有効にしたバケットは S3 の仕様上無効化できず、OFF にしても既定の保持期間が外れるだけで、ロック済みのログは保護されたまま。

## DR（クロスリージョンレプリケーション）

`replication_enabled = true` で、`aws.dr` プロバイダーのリージョンにレプリカバケットを作成して複製する（外部バケット利用時は対象外）。

- レプリカバケットも Object Lock・バージョニング・KMS（`replica_kms_key_arn`）・パブリックアクセスブロック・TLS 強制で保護し、複製元と同じ Lifecycle を設定する
- 複製元での削除（削除マーカー）は複製しない
- 有効化以降のログだけが複製される。既存ログは S3 Batch Replication で複製する
- レプリカバケットにも `prevent_destroy` を設定している

## 今後の追加予定

- 画像バケットの S3 データイベント（誰がどの画像を参照したかの監査）。画像バケットの実装時に追加する
