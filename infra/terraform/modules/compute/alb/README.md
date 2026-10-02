# compute/alb

> 3省2GL観点：通信の暗号化（TLS 1.2 以上）・監査ログ（アクセスログ）

- HTTPS（443）のみで提供する。HTTP（80）は HTTPS へのリダイレクトだけを行う
- ECS ネイティブ Blue/Green 用に、ターゲットグループ（blue / green）、本番リスナールール、テストリスナー（`test_listener_port`）を用意する
- リスナールールの重みは、デプロイ時に ECS が書き換える。そのため Terraform では `ignore_changes` にしている
- テストリスナーは運用者の CIDR だけに開放する（`0.0.0.0/0` は validation で拒否する）
- アクセスログは専用バケットに保存する。ALB のアクセスログは SSE-KMS に対応していないため、SSE-S3 で暗号化する

CloudFront を導入したら、`ingress_cidrs` を CloudFront のマネージドプレフィックスリストに置き換える。
