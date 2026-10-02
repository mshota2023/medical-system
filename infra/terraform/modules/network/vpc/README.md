# network/vpc

> 3省2GL観点：ネットワーク分離・監査ログ（VPC Flow Logs）

| 層 | CIDR（/16 内） | 配置するもの | インターネットへの経路 |
|---|---|---|---|
| public | `x.x.0-2.0/24` | ALB・NAT Gateway | IGW（受信は ALB の 443 のみを想定） |
| private-app | `x.x.16.0/20` ～ `x.x.48.0/20` | ECS タスク・Interface エンドポイント | NAT Gateway 経由の外向きのみ |
| private-db | `x.x.200-202.0/24` | Aurora・ElastiCache | なし |

- デフォルト SG はルールを全削除し、使用できない状態にする
- VPC Flow Logs は全トラフィック（ACCEPT / REJECT）を、KMS で暗号化した CloudWatch Logs に送る
- `single_nat_gateway = true` は dev 向け（コスト優先）。prod は AZ ごとに NAT Gateway を置く
