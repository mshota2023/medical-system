# compute/ecs

> 3省2GL観点：ネットワーク分離（プライベートサブネット・公開 IP なし）・バックアップ/可用性（マルチ AZ・自動ロールバック）

- Fargate サービスを private-app サブネットに配置し、ALB の SG からの通信だけを受け付ける
- デプロイ方式は **ECS ネイティブ Blue/Green**（AWS プロバイダー 6.4.0 以降が必要）
  - 新バージョン（Green）はまずテストリスナーで確認し、その後で本番トラフィックを切り替える
  - 切替後 `bake_time_in_minutes` の間は旧バージョン（Blue）を残し、問題があればすぐに戻せる
  - デプロイに失敗した場合は、サーキットブレーカーで自動ロールバックする
- タスク数は Application Auto Scaling で管理する（サービスの `desired_count` は作成時のみ使い、以降は `ignore_changes`）
  - `autoscaling_enabled = false`: min = max = `desired_count` で固定
  - `autoscaling_enabled = true`: CPU 使用率（`autoscaling_cpu_target`）のターゲット追跡で `desired_count`〜`max_count` の範囲で増減する
  - 夜間停止（`compute/ecs-scheduled-stop`）も同じスケーラブルターゲットの min/max を変更して行う
- Container Insights は `container_insights`（`enabled` / `enhanced` / `disabled`）で切り替える
- ECS Exec（コンテナへの対話ログイン）は既定で無効。`exec_enabled = true` で有効にする（ルートモジュールでは prod での有効化を validation で禁止している）
  - セッションは logs 用 KMS キーで暗号化し、操作内容を `/ecs/<prefix>/<service>/exec` ロググループに記録する（監査証跡）
  - 有効化は、次のデプロイで起動したタスクから反映される
  - 利用者には `ecs:ExecuteCommand` と、logs キーに対する `kms:GenerateDataKey` が必要。IAM Identity Center の権限セットで付与する

## Terraform と CI の役割分担

| 管理対象 | 管理者 |
|---|---|
| クラスター・サービス・IAM ロール・SG・ロググループ | Terraform |
| タスク定義（イメージ・環境変数・CPU/メモリ） | アプリリポジトリの `taskdef.json` から CI が登録する |

Terraform が作成するタスク定義は、初回作成用のプレースホルダ。サービスの `task_definition` と `load_balancer` は `ignore_changes` にしている（Blue/Green 完了後、ECS が本番ターゲットグループを入れ替えるため）。
そのため、ロードバランサー設定を Terraform から変更する場合は、サービスの再作成が必要になる。
