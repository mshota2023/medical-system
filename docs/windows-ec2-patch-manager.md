# EC2 Windows Server の月次パッチ運用（Patch Manager・方針案）

EC2 で稼働する Windows Server に、SSM Patch Manager のパッチベースラインで適用するパッチを制御しながら、月次でパッチを適用するための方針案。

## 目次

1. [この資料について](#1-この資料について)
2. [全体像](#2-全体像)
3. [パッチベースラインの設計](#3-パッチベースラインの設計)
4. [Windows 側の前提設定](#4-windows-側の前提設定)
5. [dev の運用（自動適用）](#5-dev-の運用自動適用)
6. [stg・prd の運用（日付で限定・再起動は手動）](#6-stgprd-の運用日付で限定再起動は手動)
7. [stg・prd の起動方式の比較](#7-stgprd-の起動方式の比較)
8. [緊急適用（定例外）](#8-緊急適用定例外)
9. [記録として残すもの](#9-記録として残すもの)
10. [Terraform 実装の想定](#10-terraform-実装の想定)
11. [3省2ガイドラインとの対応](#11-3省2ガイドラインとの対応)
12. [未決事項](#12-未決事項)

## 1. この資料について

- 現時点で Windows EC2 の Terraform 実装はない。Windows EC2 を導入する場合のたたき台とする
- 方針の決定は要件定義の [U17 運用手順・変更管理・パッチ適用](./requirements.md#u17) で行う
- 決定後、Terraform で実装したもの（Patch Baseline・Maintenance Window 等）は [infra/README.md](../infra/README.md) に記載する
- 本資料は **Windows 本体のパッチ（Microsoft 配信分）を Patch Manager でどう制御するか** に絞る。AWS ドライバー・エージェントの更新、更新前の確認、事前バックアップ、切り戻しは [windows-ec2-driver-patch.md](./windows-ec2-driver-patch.md) を参照する

## 2. 全体像

### 2.1 使う機能

| 機能 | 用途 |
|---|---|
| パッチベースライン（カスタム、OS は `WINDOWS`） | 適用してよいパッチ（承認済みパッチ）を決める。環境ごとに1つ作る |
| パッチグループ（タグ `Patch Group`） | インスタンスとベースラインを紐付ける |
| Maintenance Window | パッチ適用を決まった日時に実行する |
| Run Command `AWS-RunPatchBaseline` | `Operation=Scan`（未適用の確認のみ）と `Operation=Install`（適用）。`RebootOption` で再起動するかを決める |
| Patch Manager のコンプライアンス | インスタンスごとの適用状況（未適用・再起動待ち等）を確認する |
| S3（KMS 暗号化） | Run Command の出力を保存し、作業記録にする |

### 2.2 環境ごとの方針

| 項目 | dev | stg | prd |
|---|---|---|---|
| 適用するパッチ | 公開されたものをすぐに承認（`ApproveAfterDays=0`） | 締め日までに公開されたもの（`ApproveUntilDate=<締め日>`） | stg と同じ締め日 |
| 実行のきっかけ | 定期の Maintenance Window（毎月固定） | 毎月の作業日時（[7 章](#7-stgprd-の起動方式の比較)で比較） | stg と同じ |
| 適用の並列度 | 対象の全台に並列で適用（`MaxConcurrency=100%`、[6.3](#63-並列での適用)） | 同左 | 同左 |
| 再起動 | 自動（`RebootOption=RebootIfNeeded`） | 人が行う（`RebootOption=NoReboot` で適用し、再起動は別に実施） | stg と同じ |
| 承認 | 不要 | 不要 | 変更作成者以外の承認者が承認する（[driver-patch 4.4](./windows-ec2-driver-patch.md#44-環境ごとの適用) と同じ職務分離） |

stg と prd で **同じ締め日** を使うことで、stg で検証したパッチの集合と、prd に適用するパッチの集合を一致させる。

### 2.3 月次の流れ

| 時期 | dev | stg | prd |
|---|---|---|---|
| 第2火曜（米国時間、Patch Tuesday） | — | — | — |
| Patch Tuesday の2日後 | 自動で適用・再起動 | — | — |
| 〜1週間 | 動作確認。問題のある KB を記録 | 締め日と作業日時を決め、設定を更新する | — |
| stg の作業日 | — | 適用 → 人が再起動 → 動作確認 | 締め日と作業日時を設定し、承認を得る |
| prd の作業日 | — | — | 適用 → 人が再起動 → 動作確認 |

## 3. パッチベースラインの設計

### 3.1 ベースラインとパッチグループ

- 環境ごとにカスタムベースラインを1つ作り、パッチグループ `pacs-<env>-windows` に登録する
- AWS 提供のデフォルトベースライン（`AWS-DefaultPatchBaseline` 等）には依存しない。パッチグループのタグが外れたインスタンスはデフォルトベースラインで評価されるため、タグの付け忘れに注意する（Terraform でタグを付与する）

### 3.2 承認ルール

承認ルールのフィルタは全環境で共通とし、承認のタイミングだけを環境ごとに変える。

| フィルタ | 設定値（例） | 説明 |
|---|---|---|
| `PRODUCT` | `WindowsServer2022`（使う OS に合わせる） | 対象の OS |
| `CLASSIFICATION` | `CriticalUpdates`, `SecurityUpdates`（必要に応じて `UpdateRollups`, `Updates`） | パッチの分類 |
| `MSRC_SEVERITY` | `Critical`, `Important`（必要に応じて `Moderate`, `Low`, `Unspecified`） | Microsoft の重大度 |

| 環境 | 承認のタイミング | 意味 |
|---|---|---|
| dev | `ApproveAfterDays=0` | 公開された時点で承認する |
| stg・prd | `ApproveUntilDate=YYYY-MM-DD` | その日付 **以前に公開された** パッチだけを承認する。締め日より後に公開されたパッチ（翌月の更新・定例外の更新）は承認されない |

- `ApproveAfterDays` と `ApproveUntilDate` は、1つの承認ルール内で同時に指定できない
- `ApproveUntilDate` は Microsoft の公開日で判定する

### 3.3 締め日の決め方

- **推奨：その月の Patch Tuesday の日付（米国時間の第2火曜）を締め日にする**。例：2026年11月は `2026-11-10`
- Patch Tuesday 以降に公開された定例外の更新は含まれない。必要な場合は [8 章](#8-緊急適用定例外)の手順で個別に承認する
- 前月以前に公開された未適用のパッチも、締め日以前なので承認される（前月に適用できなかった分も取りこぼさない）

### 3.4 例外の指定

| 設定 | 用途 |
|---|---|
| 承認済みパッチ（`ApprovedPatches`） | 締め日に関係なく、指定した KB を承認する。定例外の緊急パッチに使う（[8 章](#8-緊急適用定例外)） |
| 拒否パッチ（`RejectedPatches`）と `RejectedPatchesAction=BLOCK` | 指定した KB を適用しない。dev で不具合が見つかった KB や、切り戻した KB（[driver-patch 5.4](./windows-ec2-driver-patch.md#54-手段-2個別の戻し)）を登録する |
| 承認済みパッチのコンプライアンスレベル（`ApprovedPatchesComplianceLevel`） | 未適用の承認済みパッチがあるとき、コンプライアンスでどの重大度として扱うか（例：`HIGH`） |

### 3.5 注意事項

- ベースラインの変更は、次回の Scan・Install の実行時に評価される。変更後は Scan を実行して、承認される KB を確認する
- Microsoft がパッチを再リリース・置き換え（superseded）した場合、承認対象が想定と変わることがある。prd の作業前に Scan し、stg で適用した KB の一覧と比べる（[6.2](#62-作業の流れ)）
- 承認対象が多すぎる・少なすぎる場合は、フィルタの範囲（[3.2](#32-承認ルール)）を見直す

## 4. Windows 側の前提設定

| 項目 | 内容 | 理由 |
|---|---|---|
| Windows Update の自動更新を止める | GPO またはレジストリ（`HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU` の `NoAutoUpdate=1`）。State Manager の関連付けで設定し、設定が戻らないようにする | Patch Manager 以外の経路でパッチが入ると、ベースラインで制御できなくなる |
| 自動再起動を止める | 同上（`NoAutoRebootWithLoggedOnUsers=1` 等） | stg・prd で再起動を人が制御するため |
| SSM で管理できる | SSM Agent が `Online`。インスタンスプロファイルに `AmazonSSMManagedInstanceCore` 相当の権限。VPC エンドポイント（ssm・ssmmessages・ec2messages・s3）経由で通信する | インターネットに出さずに Patch Manager を使う（既存の `network/vpc-endpoints` を参照） |
| パッチグループのタグ | `Patch Group = pacs-<env>-windows` を Terraform で付与する | ベースラインとの紐付け（[3.1](#31-ベースラインとパッチグループ)） |
| パッチの取得経路 | Windows Update（Microsoft のサイト）に到達できること。NAT Gateway 経由、または WSUS を用意する | Patch Manager はインスタンスが Windows Update からパッチをダウンロードする |

## 5. dev の運用（自動適用）

| 項目 | 設定 |
|---|---|
| スケジュール | `cron(0 3 ? * TUE#2 *)`、`ScheduleOffset=2`、タイムゾーン `Asia/Tokyo`（第2火曜の2日後、木曜 3:00 に実行） |
| タスク | `AWS-RunPatchBaseline`（`Operation=Install`、`RebootOption=RebootIfNeeded`） |
| 同時実行 | 全台に並列で適用する（`MaxConcurrency=100%`、`MaxErrors` は [6.3](#63-並列での適用)） |

- Patch Tuesday のパッチは日本時間の水曜未明に公開されるため、オフセットで公開後に実行する
- 「第2水曜」（`WED#2`）は、月によっては Patch Tuesday より前になるため使わない（1日が水曜の月）
- 実行後、コンプライアンスとアプリの動作を確認する。問題のある KB は、stg・prd の拒否パッチの候補として記録する

## 6. stg・prd の運用（日付で限定・再起動は手動）

### 6.1 再起動を人が制御する理由

- 再起動のタイミングを、業務の停止・再開や、モダリティからの DICOM 送信の停止と合わせるため
- 適用結果（失敗した KB 等）を確認してから再起動するため

`RebootOption=NoReboot` で適用すると、再起動が必要なパッチは **再起動待ち（`InstalledPendingReboot`）** になり、コンプライアンス上は未準拠として扱われる。再起動するまでパッチは有効にならないため、再起動は作業当日中に行い、放置しない。

### 6.2 作業の流れ

| 順序 | 作業 | 内容 |
|---|---|---|
| 1 | 締め日と作業日時の設定 | 各環境の `terraform.tfvars` で締め日と作業日時（[7 章](#7-stgprd-の起動方式の比較)の案1の場合）を更新し、PR を作成する。prd は変更作成者以外が承認する |
| 2 | 事前の Scan | `AWS-RunPatchBaseline`（`Operation=Scan`）を実行し、適用される KB の一覧を取る。prd では stg で適用した一覧と一致することを確認し、承認依頼に添付する |
| 3 | 事前作業 | [driver-patch 4.3](./windows-ec2-driver-patch.md#43-定期メンテナンス内の作業) の順序1〜4（業務の停止、直前確認、事前バックアップ、ドライバー更新） |
| 4 | パッチの適用 | `AWS-RunPatchBaseline`（`Operation=Install`、`RebootOption=NoReboot`）。対象の全台に並列で適用する（[6.3](#63-並列での適用)） |
| 5 | 適用結果の確認 | 失敗した KB がないこと、再起動待ちの KB を確認する（下記コマンド） |
| 6 | 再起動 | 人が実行する（下記コマンド） |
| 7 | 事後の Scan | `Operation=Scan` を再度実行し、コンプライアンスを更新する。再起動待ち・未適用が残っていないことを確認する |
| 8 | 正常性確認と判定 | [driver-patch 5.1](./windows-ec2-driver-patch.md#51-切り戻しの判断基準) の項目を確認し、業務を再開するか切り戻すかを判定する |

**適用結果の確認**

```sh
# 再起動待ちの KB
aws ssm describe-instance-patches --instance-id <インスタンス ID> \
  --filters Key=State,Values=InstalledPendingReboot \
  --query "Patches[].[KBId,Title]" --output table

# 失敗した KB
aws ssm describe-instance-patches --instance-id <インスタンス ID> \
  --filters Key=State,Values=Failed \
  --query "Patches[].[KBId,Title]" --output table

# インスタンスの適用状況のまとめ
aws ssm describe-instance-patch-states --instance-ids <インスタンス ID> \
  --query "InstancePatchStates[].[InstalledCount,InstalledPendingRebootCount,MissingCount,FailedCount,Operation,OperationEndTime]"
```

**再起動**

```sh
# Run Command で OS から再起動する（実行記録が S3 に残る）
aws ssm send-command --instance-ids <インスタンス ID> \
  --document-name AWS-RunPowerShellScript \
  --parameters 'commands=["Restart-Computer -Force"]' \
  --output-s3-bucket-name <ログ用バケット> --output-s3-key-prefix patch/<実施日>
```

### 6.3 並列での適用

Windows Update の適用（Scan・Install）は、パッチグループの全台に対して並列で実行する。1台ずつ順に行うと、台数に比例して作業時間が延びるため。

| 設定 | 値 | 説明 |
|---|---|---|
| 対象の指定 | パッチグループのタグ（`tag:Patch Group = pacs-<env>-windows`） | インスタンス ID を並べず、タグで全台を一度に指定する。台数が増えても手順・設定を変えずに済む |
| 同時実行数（`MaxConcurrency`） | `100%` | 対象の全台で同時に実行する |
| 許容エラー数（`MaxErrors`） | `100%` | 一部の台で失敗しても、残りの台の適用を止めない。失敗した台は、適用後に個別に確認して再実行する（[6.2](#62-作業の流れ) 順序5） |

Maintenance Window（dev、および [7 章](#7-stgprd-の起動方式の比較)の案1）では、タスクの `MaxConcurrency`・`MaxErrors` に上記を設定する。手動で実行する場合（案2）は次のコマンドを使う。

```sh
# 事前・事後の Scan（並列）
aws ssm send-command --document-name AWS-RunPatchBaseline \
  --targets "Key=tag:Patch Group,Values=pacs-<env>-windows" \
  --max-concurrency 100% --max-errors 100% \
  --parameters Operation=Scan \
  --output-s3-bucket-name <ログ用バケット> --output-s3-key-prefix patch/<実施日>

# 適用（並列、再起動しない）
aws ssm send-command --document-name AWS-RunPatchBaseline \
  --targets "Key=tag:Patch Group,Values=pacs-<env>-windows" \
  --max-concurrency 100% --max-errors 100% \
  --parameters Operation=Install,RebootOption=NoReboot \
  --output-s3-bucket-name <ログ用バケット> --output-s3-key-prefix patch/<実施日>

# 台ごとの結果を確認する
aws ssm list-command-invocations --command-id <コマンド ID> \
  --query "CommandInvocations[].[InstanceId,Status]" --output table
```

並列で適用する場合の注意点。

- **事前作業は全台分を済ませてから適用する**。業務の停止と事前バックアップ（[6.2](#62-作業の流れ) 順序3）は、対象の全台で完了していることを確認してから、適用を始める
- **再起動も全台を並列で行ってよい**。stg・prd は業務を止めた状態で作業するため。冗長化した構成（同じ役割の台が複数）で業務を止めずに作業する場合は、再起動を役割ごとに分けて順に行う（パッチの適用は並列のままでよい）
- **パッチのダウンロードが集中する**。全台が同時に Windows Update からダウンロードするため、NAT Gateway 経由の通信量とダウンロード時間が増える。stg で所要時間を測り、prd の作業時間の見積もりに使う
- **dev は再起動まで自動で並列に行われる**（`RebootIfNeeded`）。dev 内で台どうしの依存関係（例：DB サーバーの再起動中にアプリサーバーが起動する）による問題が出る場合は、役割ごとに Window・タスクを分ける

## 7. stg・prd の起動方式の比較

stg・prd は毎月の作業日時が変わるため、cron の定期スケジュールでは表せない。次の2案を比較する。どちらも適用は `RebootOption=NoReboot` とし、再起動は人が行う。

- **案1：月ごとに1回限りの Maintenance Window**
  スケジュールを `at(2026-11-18T22:00:00)`（タイムゾーン `Asia/Tokyo`）の形にし、締め日と一緒に `terraform.tfvars` で毎月更新する
- **案2：当日に手動実行**
  Maintenance Window は使わず、作業当日にオペレーターが Run Command `AWS-RunPatchBaseline` を実行する

| 観点 | 案1：1回限りの Maintenance Window | 案2：当日に手動実行 |
|---|---|---|
| 作業日時の変更 | `terraform.tfvars` を毎月更新し、apply する | 不要 |
| 変更の記録・承認 | 締め日と作業日時が同じ PR に残り、prd の承認と一体で管理できる | CloudTrail と Run Command の履歴のみ。作業日時の承認は別のチケット等で行う |
| 人の事前作業との順序 | 指定時刻に自動で始まるため、業務の停止や事前バックアップが遅れると先に適用が始まる。開始前に作業者が Window を有効にする運用（普段は無効）にすると防げる | 事前作業の完了を確認してから実行できる |
| パラメータの誤り | `RebootOption=NoReboot` 等が Terraform で固定され、誤りが起きにくい | 実行のたびに指定するため誤りの余地がある。コマンドのテンプレートを手順書で固定する |
| 実行時間・並列実行の制御 | Window の長さ・終了前の締切（cutoff）に加え、並列度（`MaxConcurrency`・`MaxErrors`、[6.3](#63-並列での適用)）が Terraform で固定される | 実行のたびに `--max-concurrency`・`--max-errors` を指定する（[6.3](#63-並列での適用) のコマンドを使う） |
| 作業日時の急な変更 | PR と apply が必要（prd は承認からやり直し） | 柔軟に変えられる |
| 予定外の実行 | 1回限りのため、実行後に再び動くことはない。apply を忘れても古い日時で再実行されることはない（その場合は適用されないまま） | なし |

**案1 のスケジュール式について**

- Maintenance Window のスケジュールには、cron 式・rate 式に加えて、1回だけ実行するタイムスタンプ（`at(YYYY-MM-DDThh:mm:ss)`）を指定できる（[AWS 公式：Reference: Cron and rate expressions for Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/reference-cron-and-rate-expressions.html) の「Single-run schedules」と、`create-maintenance-window` の CLI 例）
- 同ドキュメントには「タイムスタンプは UTC 形式」とある一方、CLI 例では `--schedule-timezone` と組み合わせている。`schedule_timezone = "Asia/Tokyo"` が `at()` に効くかは、stg で作成後に次回の実行予定（`aws ssm get-maintenance-window --window-id <ID> --query NextExecutionTime`）を見て確認する
- 実行が終わった Window は削除されず、管理画面（Maintenance Windows の一覧）に残る。次回の実行予定がない状態で残るだけで、再び実行されることはない
- Window は環境ごとに1つとし、毎月 `terraform.tfvars` の日時を書き換えて同じ Window のスケジュールを更新する（毎月新しい Window を作らない）。過去の Window が一覧にたまらず、実行履歴も1つの Window にまとまる
- Window の実行履歴の保持期間は限られる（AWS のブログでは30日間と説明されているが、公式ドキュメントでは要確認）。長期の記録は、S3 に出力した Run Command の結果と CloudTrail で残す（[9 章](#9-記録として残すもの)）
- `at()` の扱いに不安がある場合は、年まで指定した cron 式（例：`cron(0 22 18 11 ? 2026)`）でも1回だけの実行になる。cron 式は `schedule_timezone` に従う

**推奨：prd・stg とも案1 を基本とし、案2 は緊急適用と再実行の手段として手順書に用意する。**

- prd は承認と記録の観点から、締め日と作業日時を同じ PR で管理できる案1 が向いている
- stg は prd の予行のため、prd と同じ仕組み（案1）で行う
- 事前作業との順序のリスクには、Window を普段は無効（`enabled = false`）にしておき、事前作業の完了後に作業者が有効にする運用で対応する。ただしこの操作も手作業になるため、作業日が多い・変更が多い場合は案2 の方が運用しやすい。stg で数か月試し、U17 で決定する

## 8. 緊急適用（定例外）

定例外の更新や、締め日より後に公開された重大な脆弱性のパッチを、月次を待たずに適用する場合。

1. 対象の KB を、stg・prd のベースラインの承認済みパッチ（`ApprovedPatches`）に追加する（`terraform.tfvars` を更新し、PR → apply）
2. dev・stg で適用し、動作を確認する
3. prd は承認を得てから、[7 章](#7-stgprd-の起動方式の比較)の案2（手動実行）で適用する。再起動は人が行う

緊急適用の基準（重大度・CVSS 等）は U17 で決める。

## 9. 記録として残すもの

[driver-patch 4.5](./windows-ec2-driver-patch.md#45-記録として残すもの) に加えて、次を残す。

- 締め日・承認済みパッチ・拒否パッチの変更履歴（PR とその承認者）
- 適用前後の Scan 結果（適用された KB の一覧、prd では stg との一致確認の結果）
- 再起動の実施者と時刻（Run Command の履歴）
- コンプライアンスの状態（作業後に未適用・再起動待ちが残っていないこと）

## 10. Terraform 実装の想定

実装時の指針。現時点では実装しない。

### 10.1 モジュール

- 配置：`infra/terraform/modules/security/patch-manager/`（`security` は脆弱性対応を扱うため。[CLAUDE.md](../CLAUDE.md) のディレクトリ規約）
- `environments/_shared/` は3環境で共通のため、環境ごとの差は `terraform.tfvars` だけで吸収する

| リソース | 内容 |
|---|---|
| `aws_ssm_patch_baseline` | `operating_system = "WINDOWS"`。承認ルールは `dynamic` で `approve_after_days` と `approve_until_date` を切り替える。`approved_patches`・`rejected_patches`・`rejected_patches_action = "BLOCK"` |
| `aws_ssm_patch_group` | ベースラインとパッチグループ `pacs-<env>-windows` の紐付け |
| `aws_ssm_maintenance_window` | `schedule`（dev は cron、stg・prd は `at()`）、`schedule_timezone = "Asia/Tokyo"`、`schedule_offset`（cron のみ）、`enabled` |
| `aws_ssm_maintenance_window_target` | パッチグループのタグでインスタンスを指定する |
| `aws_ssm_maintenance_window_task` | `AWS-RunPatchBaseline`（`Operation`・`RebootOption`）。`max_concurrency = "100%"`・`max_errors = "100%"` で全台に並列で適用する（[6.3](#63-並列での適用)）。出力先は KMS で暗号化した S3 |

### 10.2 環境ごとの変数（例）

```hcl
# dev
patch_approve_after_days = 0
patch_approve_until_date = null
patch_window_schedule    = "cron(0 3 ? * TUE#2 *)"
patch_window_offset_days = 2
patch_window_enabled     = true
patch_reboot_option      = "RebootIfNeeded"
patch_approved_patches   = []
patch_rejected_patches   = []

# stg（毎月更新する）
patch_approve_after_days = null
patch_approve_until_date = "2026-11-10"
patch_window_schedule    = "at(2026-11-18T22:00:00)"
patch_window_offset_days = null
patch_window_enabled     = false # 事前作業の完了後に有効にする運用の場合
patch_reboot_option      = "NoReboot"
patch_approved_patches   = []
patch_rejected_patches   = []

# prd（締め日は stg と同じ値にする）
patch_approve_after_days = null
patch_approve_until_date = "2026-11-10"
patch_window_schedule    = "at(2026-11-25T22:00:00)"
patch_window_offset_days = null
patch_window_enabled     = false
patch_reboot_option      = "NoReboot"
patch_approved_patches   = []
patch_rejected_patches   = []
```

- `patch_approve_after_days` と `patch_approve_until_date` は、どちらか一方だけを指定するよう `validation` で検査する
- `patch_window_enabled` を作業当日に切り替える運用にする場合、その切り替えを apply で行うか CLI（`aws ssm update-maintenance-window --enabled`）で行うかを決める。CLI で行う場合は Terraform の差分を無視する設定（`lifecycle.ignore_changes`）が必要

## 11. 3省2ガイドラインとの対応

| 観点 | 対応 |
|---|---|
| 脆弱性対策（パッチの計画的な適用） | 月次の定期適用と、緊急適用（[8 章](#8-緊急適用定例外)）の手順を定める |
| 変更管理・職務分離 | 締め日・作業日時・例外 KB を PR で管理し、prd は変更作成者以外が承認する |
| 適用内容の検証 | stg と prd で同じ締め日を使い、検証済みのパッチだけを prd に適用する |
| 監査証跡と改ざん防止 | Run Command の出力、Maintenance Window の実行履歴、CloudTrail を保存する。CloudTrail は Object Lock 付きのバケットに保存済み（[infra/README.md](../infra/README.md#注意事項)） |
| 保存データの暗号化 | Run Command の出力先 S3 は KMS で暗号化する |
| データ保管場所 | 出力・ログは国内リージョン（ap-northeast-1）に保存する |

> 該当する条文は、厚生労働省ガイドライン第7.0版のシステム運用編で要確認。

## 12. 未決事項

[U17](./requirements.md#u17) で決める。

| # | 論点 | 暫定の推奨 |
|---|---|---|
| 1 | stg・prd の起動方式 | 案1（1回限りの Maintenance Window）を基本とし、stg で試して決める（[7 章](#7-stgprd-の起動方式の比較)） |
| 2 | 締め日の決め方 | その月の Patch Tuesday の日付 |
| 3 | 承認する分類・重大度 | `CriticalUpdates`・`SecurityUpdates`、重大度 `Critical`・`Important` から始める |
| 4 | stg から prd までの間隔 | 1週間以上あける（stg での検証期間） |
| 5 | 再起動の期限 | 適用した作業当日中 |
| 6 | 緊急適用の基準 | 重大度や CVSS による基準を決める（[driver-patch 8 章](./windows-ec2-driver-patch.md#8-未決事項) #2 と共通） |
| 7 | パッチの取得経路 | NAT Gateway 経由で Windows Update に接続するか、WSUS を置くか |
| 8 | Office 等のアプリケーションのパッチ | 対象とするかを、インストールするソフトが決まった時点で決める |
| 9 | Window の有効化の切り替え方法 | apply で行うか CLI で行うか（[10.2](#102-環境ごとの変数例)） |
| 10 | 並列での適用の許容エラー数 | `100%`（失敗した台があっても他の台を止めない）。失敗が多い場合に止めたいなら、`MaxErrors` を台数に応じた値にする（[6.3](#63-並列での適用)） |
