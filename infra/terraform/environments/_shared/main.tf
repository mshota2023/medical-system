locals {
  name_prefix = "${var.system_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# security（暗号鍵は他モジュールより先に用意する）
# ---------------------------------------------------------------------------
module "kms" {
  source = "../../modules/security/kms"

  name_prefix = local.name_prefix
}

# DR リージョン側の鍵（複製先のログ・イメージの暗号化に使う）
module "kms_dr" {
  source = "../../modules/security/kms"
  count  = var.dr_enabled ? 1 : 0

  providers = {
    aws = aws.dr
  }

  name_prefix = local.name_prefix
}

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------
module "cloudtrail" {
  source = "../../modules/logging/cloudtrail"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name_prefix               = local.name_prefix
  kms_key_arn               = module.kms.logs_key_arn
  external_bucket_name      = var.cloudtrail_external_bucket_name
  object_lock_enabled       = var.s3_object_lock_enabled
  object_lock_mode          = var.cloudtrail_object_lock_mode
  object_lock_days          = var.cloudtrail_object_lock_days
  log_retention_days        = var.cloudtrail_log_retention_days
  glacier_transition_days   = var.cloudtrail_glacier_transition_days
  cloudwatch_retention_days = var.cloudtrail_cloudwatch_retention_days
  replication_enabled       = var.dr_enabled
  replica_kms_key_arn       = var.dr_enabled ? module.kms_dr[0].logs_key_arn : null
}

# ---------------------------------------------------------------------------
# network
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/network/vpc"

  name_prefix              = local.name_prefix
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  single_nat_gateway       = !var.network_ha_enabled
  logs_kms_key_arn         = module.kms.logs_key_arn
  flow_logs_retention_days = var.flow_logs_retention_days
}

# Interface エンドポイントは、冗長化なしの場合は先頭 AZ のみに置く（他 AZ のタスクは AZ をまたいで利用する）
module "vpc_endpoints" {
  source = "../../modules/network/vpc-endpoints"

  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  subnet_ids         = var.network_ha_enabled ? module.vpc.app_subnet_ids : slice(module.vpc.app_subnet_ids, 0, 1)
  route_table_ids    = module.vpc.private_route_table_ids
  interface_services = var.vpc_interface_endpoint_services
}

# ---------------------------------------------------------------------------
# compute
# ---------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/compute/ecr"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  repository_name     = "${local.name_prefix}/${var.app_service_name}"
  kms_key_arn         = module.kms.data_key_arn
  max_image_count     = var.ecr_max_image_count
  replication_enabled = var.dr_enabled
  replica_kms_key_arn = var.dr_enabled ? module.kms_dr[0].data_key_arn : null
}

module "alb" {
  source = "../../modules/compute/alb"

  name_prefix         = local.name_prefix
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = module.vpc.vpc_cidr
  public_subnet_ids   = module.vpc.public_subnet_ids
  certificate_arn     = var.acm_certificate_arn
  ingress_cidrs       = var.alb_ingress_cidrs
  test_listener_cidrs = var.alb_test_listener_cidrs
  target_port         = var.app_container_port
  health_check_path   = var.app_health_check_path
  deletion_protection = var.alb_deletion_protection

  access_log_retention_days = var.alb_access_log_retention_days
}

module "ecs" {
  source = "../../modules/compute/ecs"

  name_prefix                  = local.name_prefix
  service_name                 = var.app_service_name
  container_port               = var.app_container_port
  desired_count                = var.app_desired_count
  autoscaling_enabled          = var.ecs_autoscaling_enabled
  max_count                    = var.app_max_count
  autoscaling_cpu_target       = var.ecs_autoscaling_cpu_target
  container_insights           = var.ecs_container_insights
  exec_enabled                 = var.ecs_exec_enabled
  bake_time_in_minutes         = var.app_bake_time_in_minutes
  log_retention_days           = var.app_log_retention_days
  vpc_id                       = module.vpc.vpc_id
  subnet_ids                   = module.vpc.app_subnet_ids
  alb_security_group_id        = module.alb.security_group_id
  blue_target_group_arn        = module.alb.blue_target_group_arn
  green_target_group_arn       = module.alb.green_target_group_arn
  production_listener_rule_arn = module.alb.production_listener_rule_arn
  test_listener_rule_arn       = module.alb.test_listener_rule_arn
  logs_kms_key_arn             = module.kms.logs_key_arn
}

module "ecs_scheduled_stop" {
  source = "../../modules/compute/ecs-scheduled-stop"
  count  = var.ecs_scheduled_stop_enabled ? 1 : 0

  name_prefix    = local.name_prefix
  service_name   = module.ecs.service_name
  resource_id    = module.ecs.autoscaling_resource_id
  min_capacity   = module.ecs.min_capacity
  max_capacity   = module.ecs.max_capacity
  stop_schedule  = var.ecs_stop_schedule
  start_schedule = var.ecs_start_schedule

  # スケーリングポリシーと同じターゲットを同時に更新しないよう、ecs モジュールの後に作成する
  depends_on = [module.ecs]
}

# ---------------------------------------------------------------------------
# cicd
# ---------------------------------------------------------------------------
module "pipeline" {
  source = "../../modules/cicd/pipeline"

  name_prefix              = local.name_prefix
  environment              = var.environment
  service_name             = var.app_service_name
  source_branch            = var.pipeline_source_branch
  require_manual_approval  = var.pipeline_require_manual_approval
  build_log_retention_days = var.build_log_retention_days
  artifact_retention_days  = var.pipeline_artifact_retention_days
  kms_key_arn              = module.kms.data_key_arn
  logs_kms_key_arn         = module.kms.logs_key_arn
  vpc_id                   = module.vpc.vpc_id
  codebuild_subnet_ids     = module.vpc.app_subnet_ids
  ecr_repository_arn       = module.ecr.repository_arn
  ecr_repository_url       = module.ecr.repository_url
  ecs_cluster_arn          = module.ecs.cluster_arn
  ecs_service_name         = module.ecs.service_name
  task_family              = module.ecs.task_family
  container_name           = module.ecs.container_name
  container_port           = var.app_container_port
  execution_role_arn       = module.ecs.execution_role_arn
  task_role_arn            = module.ecs.task_role_arn
  app_log_group_name       = module.ecs.log_group_name
  task_subnet_ids          = module.vpc.app_subnet_ids
  task_security_group_id   = module.ecs.task_security_group_id
}
