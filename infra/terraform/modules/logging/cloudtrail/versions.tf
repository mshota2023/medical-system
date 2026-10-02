terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws.dr: DR リージョンのレプリカバケット用（replication_enabled = false でも渡す）
      configuration_aliases = [aws.dr]
    }
  }
}
