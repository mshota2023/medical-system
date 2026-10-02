# network/vpc-endpoints

> 3省2GL観点：ネットワーク分離（AWS サービスへの通信をインターネットに出さない）

- Gateway エンドポイント：S3・DynamoDB（private-app / private-db のルートテーブルに関連付け）
- Interface エンドポイント：SSM・SSM Messages・EC2 Messages（Session Manager 踏み台用）、ECR（API / DKR）、CloudWatch Logs、KMS、STS
- Interface エンドポイントの SG は、VPC CIDR からの 443 のみを許可する

Interface エンドポイントは AZ × サービス数ごとに時間課金が発生する。dev でコストを抑えたい場合は `interface_services` を絞る。
