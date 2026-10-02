# cicd/pipeline

> 3省2GL観点：変更管理（本番変更の承認記録・職務分離・証跡）・最小権限

アプリケーションを ECS にデプロイする CodePipeline。各環境アカウントに1つずつ作成する。

```
Source (CodeCommit) → Build → [Approval: prod のみ] → Migrate → Deploy (ECS Blue/Green)
```

| ステージ | 実行内容 | buildspec（アプリリポジトリ側） |
|---|---|---|
| Build | イメージをビルドして ECR に push する。CRITICAL の脆弱性があれば停止する。タスク定義を登録する | `buildspec.yml` |
| Approval | 本番のみ（`require_manual_approval = true`）。変更作成者以外が承認する | — |
| Migrate | 登録したタスク定義で、DB マイグレーション用のタスクを `run-task` で実行する | `buildspec-migrate.yml` |
| Deploy | `update-service` で Blue/Green デプロイを開始し、完了またはロールバックまで監視する | `buildspec-deploy.yml` |

承認を Migrate の前に置いている。承認の前に本番 DB が変更されないようにするため。

buildspec とタスク定義のテンプレートは [infra/cicd-templates/](../../../../cicd-templates/) にある。

## 権限設計

- CodeBuild のロールはステージごとに分け、それぞれに必要な操作だけを許可する。PassRole は ECS タスク用の2ロールに限定している
- パイプラインと CodeBuild のロールには承認権限（`PutApprovalResult`）を与えない
- 承認者用ポリシーは `approver_policy_json` として出力する。IAM Identity Center の承認者用権限セットに設定し、開発者用の権限セットとは分ける

## 証跡

- パイプラインの実行履歴・承認者・承認時のコメントは CodePipeline の実行履歴と CloudTrail（`PutApprovalResult`）に残る
- ビルドログは KMS で暗号化した CloudWatch Logs に保存する（既定365日）
