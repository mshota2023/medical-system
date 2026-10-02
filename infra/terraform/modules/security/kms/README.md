# security/kms

> 3省2GL観点：保存データの暗号化（KMS による暗号化を標準とする）

用途別のカスタマーマネージドキーを作成する。どちらのキーも自動ローテーションを有効にしている。

| キー | エイリアス | 用途 |
|---|---|---|
| logs | `alias/<prefix>-logs` | CloudTrail・CloudWatch Logs（VPC Flow Logs 等）。サービスプリンシパルの利用は自アカウントのリソースに限定 |
| data | `alias/<prefix>-data` | 医療情報（S3・Aurora・EBS 等）。利用権限は各モジュールの IAM ポリシーで最小限に付与する |

テナント別キー（暗号学的消去用）はテナント数が多いため Terraform では管理しない。アプリのオンボーディング処理で作成する（[docs/requirements.md](../../../../../docs/requirements.md) 参照）。
