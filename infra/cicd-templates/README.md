# CI/CD テンプレート（アプリリポジトリ用）

[modules/cicd/pipeline](../terraform/modules/cicd/pipeline/README.md) が作るパイプラインで使うファイル。
**アプリリポジトリのルートにコピーして使う**（このディレクトリは Terraform モジュールではない）。

| ファイル | 用途 |
|---|---|
| `buildspec.yml` | Build：ビルド・ECR への push・CRITICAL 脆弱性の判定・タスク定義の登録 |
| `buildspec-migrate.yml` | Migrate：DB マイグレーション（`MIGRATION_COMMAND` を空にするとスキップ） |
| `buildspec-deploy.yml` | Deploy：`update-service` を実行し、Blue/Green の完了またはロールバックまで監視 |
| `taskdef.json` | タスク定義。`${...}` は Build 時に `envsubst` で置換される |

## ルール

### イメージの再現性（環境ごとに再ビルドするため）

各環境のパイプラインが同じコミットから個別にビルドするため、次を守る。

- Dockerfile のベースイメージは **digest で固定する**（例：`FROM public.ecr.aws/docker/library/node:22-alpine@sha256:...`）
- 依存パッケージは**ロックファイルでバージョンを固定する**（`package-lock.json`・`poetry.lock` 等）。ビルドではロックファイルどおりにインストールする（`npm ci` 等）
- ベースイメージは Docker Hub ではなく ECR Public 等から取得する（Docker Hub のレート制限を避けるため）

### タスク定義

- `readonlyRootFilesystem: true` と非 root ユーザーを基本にする。一時ファイルが必要な場合はボリュームを追加する
- `family`・`executionRoleArn`・`taskRoleArn`・コンテナ名は置換変数のまま変更しない（IAM の権限範囲と一致させているため）
- パスワード等は `environment` に書かず、`secrets`（Secrets Manager）で渡す

### DB マイグレーション（expand/contract）

Blue/Green では、マイグレーション後もしばらく旧バージョンが稼働し、ロールバックで旧バージョンに戻ることもある。そのため、**マイグレーションは旧バージョンのアプリでも動く変更に限る**。

- 列の削除・名前変更は、2回のリリースに分ける（1回目で新しい列を追加して両方に書き込み、2回目で旧列を削除する）
- `NOT NULL` 制約の追加は、既定値を設定してから行う

## 環境の昇格手順

dev・stg・prod は、それぞれのアカウントの CodeCommit リポジトリ（ミラー）を持つ。

```sh
# 1. dev で確認したコミットを stg に push（stg のパイプラインが起動する）
git push stg <検証済みコミット>:refs/heads/main

# 2. stg で確認したコミットを prod に push（prod のパイプラインは Approval で停止する）
git push prod <検証済みコミット>:refs/heads/main
```

prod へ push する権限と、承認する権限は別の人に付与する（職務分離）。
