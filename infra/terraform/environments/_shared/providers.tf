provider "aws" {
  region = var.region

  # 環境ごとに別アカウントのため、想定外のアカウントへの適用を防ぐ
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      System      = var.system_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# DR リージョン（国内に限定）。dr_enabled = false でも provider 定義は必要なため常に構成する
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      System      = var.system_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
