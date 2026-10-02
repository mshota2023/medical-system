# compute/ecr

> 3省2GL観点：保存データの暗号化・変更管理（イメージの改ざん防止）

- タグを不変（IMMUTABLE）にし、デプロイ済みイメージの上書き（すり替え）を防ぐ
- push 時に脆弱性スキャンを実行する。CRITICAL が見つかった場合の停止判定は CI（[buildspec.yml](../../../../cicd-templates/buildspec.yml)）で行う
- data 用 KMS キーで暗号化する
- 未タグのイメージは7日で削除し、タグ付きは `max_image_count` 世代まで保持する（ロールバック用）
- `replication_enabled = true` で、`aws.dr` プロバイダーのリージョンへイメージを複製する。複製先のリポジトリは ECR が自動作成するため、作成テンプレートで KMS 暗号化（`replica_kms_key_arn`）・タグ不変・Lifecycle を揃える
  - レプリケーション設定はレジストリ単位（1アカウントに1つ）のため、同じアカウントで別の複製設定を作る場合はこのモジュールに統合する
  - 有効化以降に push されたイメージだけが複製される
