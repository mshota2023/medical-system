terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.4, < 7.0" # 6.4.0 で ECS ネイティブ Blue/Green（advanced_configuration）に対応
    }
  }

  # 変数展開できないため空にし、各環境の backend.hcl で指定する
  # terraform init -backend-config=backend.hcl
  backend "s3" {}
}
