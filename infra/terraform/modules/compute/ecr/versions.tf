terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws.dr: DR リージョンのリポジトリ作成テンプレート用（replication_enabled = false でも渡す）
      configuration_aliases = [aws.dr]
    }
  }
}
