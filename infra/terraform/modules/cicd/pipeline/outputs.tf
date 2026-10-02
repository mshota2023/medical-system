output "repository_clone_url_grc" {
  description = "CodeCommit リポジトリの clone URL（git-remote-codecommit 形式）"
  value       = "codecommit::${data.aws_region.current.region}://${aws_codecommit_repository.this.repository_name}"
}

output "pipeline_name" {
  description = "CodePipeline 名"
  value       = aws_codepipeline.this.name
}

output "approver_policy_json" {
  description = "本番承認者用の IAM ポリシー（IAM Identity Center の承認者用権限セットのインラインポリシーに設定する）"
  value       = data.aws_iam_policy_document.approver.json
}
