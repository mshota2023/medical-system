# EC2 Windows Server のドライバー・パッチ運用（方針案）

EC2 で Windows Server を稼働させる場合の、ドライバーと OS パッチの更新方針案。

## 目次

1. [この資料について](#1-この資料について)
2. [対象](#2-対象)
3. [更新方式](#3-更新方式)
4. [手順（方式 B）](#4-手順方式-b)
5. [注意事項](#5-注意事項)
6. [3省2ガイドラインとの対応](#6-3省2ガイドラインとの対応)
7. [未決事項](#7-未決事項)

## 1. この資料について

- 現時点で Windows EC2 の Terraform 実装はない。Windows EC2 を導入する場合のたたき台とする
- 方針の決定は要件定義の [U17 運用手順・変更管理・パッチ適用](./requirements.md#u17) で行う
- 決定後、Terraform で実装したもの（SSM Maintenance Window・Patch Baseline 等）は [infra/README.md](../infra/README.md) に記載する

## 2. 対象

AWS 固有のドライバー（ENA・NVMe・PV）は Windows Update では配信されない。Windows 本体のパッチとは別に更新する。

| 種別 | 用途 | 更新手段 |
|---|---|---|
| ENA ドライバー | Nitro 系インスタンスのネットワーク | SSM Distributor `AwsEnaNetworkDriver` |
| AWS NVMe ドライバー | Nitro 系インスタンスの EBS・インスタンスストア | SSM Distributor `AWSNVMe` |
| AWS PV ドライバー | 旧 Xen 系インスタンス（T2・M4 等） | SSM Distributor `AWSPVDriver` |
| EC2Launch v2 | 起動時の初期設定 | SSM Distributor `AWSEC2Launch-Agent` |
| SSM Agent | Session Manager・Run Command | `AWS-UpdateSSMAgent` |
| CloudWatch Agent | ログ・メトリクス収集 | SSM Distributor `AmazonCloudWatchAgent` |
| GPU ドライバー（NVIDIA 等） | G 系インスタンスを使う場合 | AWS 提供の S3 バケット、またはベンダー提供版 |
| Windows 本体・一般ドライバー | Microsoft 配信分 | SSM Patch Manager `AWS-RunPatchBaseline` |

## 3. 更新方式

| 方式 | 内容 | 向いている対象 |
|---|---|---|
| A ゴールデン AMI（第一候補） | EC2 Image Builder のパイプラインで、AWS 提供の最新 Windows AMI（毎月 Patch Tuesday 後に更新、AWS ドライバーを含む）を元に自社 AMI を毎月作る。検証後にインスタンスを入れ替える | 状態を持たないサーバー。切り戻しは旧 AMI に戻すだけで済み、構成のドリフトも起きない |
| B インプレース更新 | SSM Maintenance Window で、稼働中のインスタンスにドライバーとパッチを適用する | 入れ替えが難しい、状態を持つサーバー |
| C 緊急・世代移行 | Automation ランブック `AWSSupport-UpgradeWindowsAWSDrivers` で、停止したインスタンスにもオフラインで適用する | Xen 系から Nitro 系への移行、ドライバー不具合で起動しない場合 |

## 4. 手順（方式 B）

### 4.1 Maintenance Window のタスク

| 順序 | タスク | 使う機能 |
|---|---|---|
| 1 | 事前バックアップ（AMI または EBS スナップショット） | `AWS-CreateImage`、または AWS Backup のオンデマンドバックアップ |
| 2 | AWS ドライバー・エージェントの更新 | Run Command `AWS-ConfigureAWSPackage`（prod は `version` を指定して固定する） |
| 3 | Windows パッチの適用 | Run Command `AWS-RunPatchBaseline` |
| 4 | 再起動と正常性確認 | EC2 ステータスチェック、アプリのヘルスチェック、SSM で接続できるか |

### 4.2 環境ごとの適用

| 環境 | 適用するバージョン | 承認 |
|---|---|---|
| dev | 最新版 | 不要 |
| stg | dev で問題がなかった版 | 不要 |
| prod | stg で検証した版（`version` を固定する） | 変更作成者以外の承認者が承認する（アプリの本番デプロイと同じ職務分離） |

### 4.3 記録として残すもの

- Maintenance Window の実行履歴
- Run Command の出力（S3 または CloudWatch Logs に出力する）
- CloudTrail（誰がいつ実行したか）
- 適用したドライバー・パッチのバージョンと承認者

## 5. 注意事項

- **事前バックアップは必須**。ドライバー更新に失敗すると起動しない、または通信できなくなり、SSM で操作できなくなる。事前のスナップショットが唯一の復旧手段になる場合がある
- **ENA ドライバーの更新中は通信が数秒切れる**。業務時間外に行い、モダリティからの DICOM 送信を止める調整をする
- **インスタンスタイプを Nitro 系に変える前に、ENA と NVMe のドライバーを確認する**。入っていないと起動に失敗する。AWS 公式の事前チェック手順に従う
- **バージョンを見える化する**。SSM Inventory でドライバーとエージェントのバージョンを集め、環境間の差分を把握する
- **リリース情報を追う**。ENA・NVMe・EC2Launch のバージョン履歴ページを定期的に確認し、AWS Health の通知を受け取る
- **PACS 関連ソフトのベンダーがサポートするバージョンを確認する**。ベンダーが動作を保証する OS パッチ・ドライバーのバージョンを指定している場合は、承認を得たバージョンに固定する

## 6. 3省2ガイドラインとの対応

| 観点 | 対応 |
|---|---|
| 脆弱性対策（パッチの計画的な適用） | 定期更新（方式 A または B）と、緊急適用の基準を定める |
| 変更管理の記録 | 「[4.3 記録として残すもの](#43-記録として残すもの)」を保存する |
| 監査証跡の改ざん防止 | CloudTrail は Object Lock 付きのバケットに保存済み（[infra/README.md](../infra/README.md#注意事項)） |
| バックアップ | 適用前に AMI またはスナップショットを取得する |

> 該当する条文は、厚生労働省ガイドライン第7.0版のシステム運用編で要確認。

## 7. 未決事項

[U17](./requirements.md#u17) で決める。

| # | 論点 | 暫定の推奨 |
|---|---|---|
| 1 | 定期更新の頻度 | 月1回（Patch Tuesday 後、AWS の AMI 更新に合わせる） |
| 2 | 緊急適用の基準 | CVSS や重大度による基準を決める（例：Critical は定期更新を待たずに適用） |
| 3 | メンテナンスウィンドウの時間帯 | 医療機関の業務への影響が小さい時間帯。SLA（[U01](./requirements.md#u01)）の計画停止の定義と合わせる |
| 4 | 方式 A と方式 B の使い分け | サーバーの役割が決まった時点で決める |
