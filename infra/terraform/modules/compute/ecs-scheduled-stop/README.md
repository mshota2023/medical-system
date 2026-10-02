# compute/ecs-scheduled-stop

dev / stg のコスト削減のため、ECS サービスのタスクを夜間・土日に停止する。

- Application Auto Scaling のスケジュールアクションで、スケーラブルターゲット（`compute/ecs` が作成）の min/max を変更する
  - 停止時刻: min/max を 0 にする
  - 起動時刻: 通常時の min/max（`compute/ecs` の `min_capacity` / `max_capacity`）に戻す。オートスケーリング有効時は、この範囲でスケーリングを再開する
- サービスリンクロールで動くため、IAM ロールや Lambda は不要
- 既定値は平日 21:00 に停止、平日 8:00 に起動（Asia/Tokyo）。起動は平日だけなので、金曜夜から月曜朝まで止まる
- ルートモジュールでは `ecs_scheduled_stop_enabled` で ON/OFF する

## 注意

- **祝日は対象外**。祝日に止めたい場合は手動で止める
- 停止中に `terraform apply` すると、スケーラブルターゲットの min/max が通常時の値に戻り、タスクが起動する（plan に差分が出るので確認できる）。次の停止時刻に再び 0 になる
- 停止中に CI/CD でデプロイすると、タスク 0 のままデプロイが完了する。動作確認は起動後に行う
