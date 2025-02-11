locals {
  vpc_dns_resolver       = module.this.enabled ? cidrhost(data.aws_vpc.lookup[0].cidr_block, 2) : "10.0.0.2"
  proxies                = { for k, v in var.proxies : k => merge(v, { name = k }) }
  proxies_port_range     = [local.proxies.default.listener_port, local.proxies.default.listener_port]
  haproxy_config_inputs  = { proxies = local.proxies, resolver = local.vpc_dns_resolver }
  haproxy_config_encoded = base64encode(templatefile("${path.module}/assets/haproxy.cfg.tmplt", local.haproxy_config_inputs))
  capacity               = merge(var.capacity, { desired = coalesce(var.capacity.desired, var.capacity.min) })

  nlb_vpc_subnet_ids = var.public_accessible ? var.vpc_public_subnet_ids : var.vpc_private_subnet_ids
  nlb_security_group_rules = [
    for x in local.proxies.default.listener_allowed_cidrs : {
      key                      = "i-${base64encode(join(",", sort(split(",", x.cidr))))}"
      type                     = "ingress"
      from_port                = local.proxies_port_range[0]
      to_port                  = local.proxies_port_range[1]
      protocol                 = "tcp"
      description              = x.description == "" ? "default tunnel rule" : "default tunnel: ${x.description}"
      cidr_blocks              = split(",", x.cidr)
      source_security_group_id = null
      self                     = null
    }
  ]

  ssm_sessions = {
    enabled          = var.ssm_sessions.enabled
    logs_bucket_name = try(coalesce(var.ssm_sessions.logs_bucket_name, var.logs_bucket_name), "")
  }
}

# ================================================================== service ===

module "proxy" {
  source  = "cloudposse/ec2-autoscale-group/aws"
  version = "0.41.0"

  image_id                = data.aws_ssm_parameter.linux_ami.value
  instance_type           = "t3.nano"
  health_check_type       = "ELB"
  user_data_base64        = base64encode(module.this.enabled ? data.template_cloudinit_config.this[0].rendered : "")
  force_delete            = true
  disable_api_termination = false
  update_default_version  = true

  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = var.experimental_mode ? 0 : 100
      max_healthy_percentage = 200
    }
  }

  iam_instance_profile_name     = module.this.enabled ? resource.aws_iam_instance_profile.this[0].id : null
  key_name                      = ""
  metadata_http_tokens_required = true

  autoscaling_policies_enabled      = false
  desired_capacity                  = local.capacity.desired
  min_size                          = var.capacity.min
  max_size                          = var.capacity.max
  max_instance_lifetime             = "604800"
  wait_for_capacity_timeout         = "300s"
  tag_specifications_resource_types = ["instance", "volume", "spot-instances-request"]

  mixed_instances_policy = {
    instances_distribution = {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      on_demand_allocation_strategy            = "prioritized"
      spot_allocation_strategy                 = "capacity-optimized"
      spot_instance_pools                      = 0
      spot_max_price                           = ""
    }
    override = [{
      instance_type     = "t3.nano"
      weighted_capacity = 1
      }, {
      instance_type     = "t3a.nano"
      weighted_capacity = 1
      }, {
      instance_type     = "t3.micro"
      weighted_capacity = 1
      }, {
      instance_type     = "t3a.micro"
      weighted_capacity = 1
    }]
  }

  associate_public_ip_address = false
  subnet_ids                  = var.vpc_private_subnet_ids
  security_group_ids          = concat([module.security_group.id], var.vpc_security_group_ids)
  target_group_arns           = module.this.enabled ? [module.nlb[0].default_target_group_arn] : []

  tags    = merge(module.this.tags, { Name = module.this.id })
  context = module.this.context
}

data "template_cloudinit_config" "this" {
  count = module.this.enabled ? 1 : 0

  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = templatefile("${path.module}/assets/userdata.sh", { haproxy_config_encoded = local.haproxy_config_encoded })
  }

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/assets/cloud-config.yaml", {
      cloudwatch_agent_config_encoded = base64encode(templatefile("${path.module}/assets/cloudwatch-agent-config.json", {
        log_group_name = aws_cloudwatch_log_group.this[0].name
      }))
    })
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/assets/provision.sh")
  }
}

resource "aws_cloudwatch_log_group" "this" {
  count = module.this.enabled ? 1 : 0

  name              = module.this.id
  retention_in_days = var.experimental_mode ? 90 : 180
  tags              = module.this.tags
}

# =============================================================== networking ===

resource "random_string" "nlb_label_suffix" {
  length  = 6
  special = false
  lower   = false
  upper   = true

  keepers = {
    name              = module.this.name,
    public_accessible = var.public_accessible
    port              = local.proxies_port_range[0]
  }
}

module "nlb_trancated_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  id_length_limit = 25 # allows random 6 char suffic
  label_order     = ["name", "attributes"]
  context         = module.this.context
}

module "nlb_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  name        = "${module.nlb_trancated_label.id}-${random_string.nlb_label_suffix.result}"
  label_order = ["name"]
  context     = module.this.context
}

module "nlb" {
  count   = module.this.enabled ? 1 : 0
  source  = "cloudposse/nlb/aws"
  version = "0.18.0"

  vpc_id                            = var.vpc_id
  subnet_ids                        = local.nlb_vpc_subnet_ids
  internal                          = !var.public_accessible
  ip_address_type                   = "ipv4"
  eip_allocation_ids                = var.eip_allocation_ids
  cross_zone_load_balancing_enabled = tobool(local.capacity.desired < 3)
  security_group_ids                = [module.security_group.id]

  tcp_enabled              = true
  tcp_port                 = local.proxies_port_range[0]
  deregistration_delay     = 15
  health_check_threshold   = 2
  health_check_interval    = 10
  target_group_port        = local.proxies_port_range[0]
  target_group_target_type = "instance"

  access_logs_enabled      = false # todo tobool(var.logs_bucket_name != "")
  access_logs_s3_bucket_id = var.logs_bucket_name

  deletion_protection_enabled = var.experimental_mode ? false : true

  context = module.nlb_label.context
}

resource "aws_vpc_endpoint_service" "this" {
  count = var.vpc_endpoint_service.enabled ? 1 : 0

  acceptance_required        = var.vpc_endpoint_service.auto_accept_enabled
  allowed_principals         = var.vpc_endpoint_service.allowed_principals
  network_load_balancer_arns = module.this.enabled ? [module.nlb[0].nlb_arn] : []

  tags = merge(module.this.tags, { Name = module.this.id })
}

# ----------------------------------------------------------- security-group ---

module "security_group" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"

  attributes                 = []
  vpc_id                     = var.vpc_id
  allow_all_egress           = true
  preserve_security_group_id = true

  rules = concat(local.nlb_security_group_rules, [{
    key                      = "i-healthcheck",
    description              = "allow traffic from nlb endpoints for healthchecks"
    type                     = "ingress"
    protocol                 = "-1"
    from_port                = 0
    to_port                  = 0
    cidr_blocks              = []
    source_security_group_id = null
    self                     = true
  }])

  tags    = merge(module.this.tags, { Name = module.this.id })
  context = module.this.context
}

# ====================================================================== iam ===

resource "aws_iam_instance_profile" "this" {
  count = module.this.enabled ? 1 : 0

  name = module.this.id
  role = aws_iam_role.this[0].name
}

resource "aws_iam_role" "this" {
  count = module.this.enabled ? 1 : 0

  name                 = module.this.id
  description          = ""
  max_session_duration = "3600"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["ec2.amazonaws.com"] }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = module.this.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = toset(module.this.enabled ? [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    resource.aws_iam_policy.this[0].arn
  ] : [])

  role       = resource.aws_iam_role.this[0].name
  policy_arn = each.key
}

resource "aws_iam_policy" "this" {
  count  = module.this.enabled ? 1 : 0
  policy = data.aws_iam_policy_document.this[0].json
}

data "aws_iam_policy_document" "this" {
  count = module.this.enabled ? 1 : 0

  statement {
    sid    = "AllowCWAgentLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:TagResource",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.this[0].arn,
      "${aws_cloudwatch_log_group.this[0].arn}:log-stream:*"
    ]
  }

  dynamic "statement" {
    for_each = var.ssm_sessions.enabled && var.ssm_sessions.logs_bucket_name != "" ? [true] : []

    content {
      sid    = "AllowSessionLogging"
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:PutObjectTagging",
        "s3:GetEncryptionConfiguration",
        "s3:GetBucketLocation",
      ]
      resources = [
        "arn:aws:s3:::${var.ssm_sessions.logs_bucket_name}",
        "arn:aws:s3:::${var.ssm_sessions.logs_bucket_name}/*"
      ]
    }
  }
}

# ================================================================== lookups ===

data "aws_vpc" "lookup" {
  count = module.this.enabled ? 1 : 0
  id    = var.vpc_id
}

data "aws_ssm_parameter" "linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

