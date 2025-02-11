# ================================================================== general ===

variable "proxies" {
  type = object({
    default = object({
      type          = optional(string, "static")
      target        = string
      listener_port = number
      listener_allowed_cidrs = list(object({
        cidr        = string
        description = optional(string, "")
      }))
    })
  })
  description = "Configuration of the proxy."
}

# =========================================================== infrastructure ===

variable "capacity" {
  type = object({
    desired = optional(number)
    min     = optional(number, 1)
    max     = optional(number, 3)
  })
  description = "Autoscaling group capacity configuration."
  default     = {}
}

variable "logs_bucket_name" {
  type        = string
  description = "S3 bucket for storing logs."
  default     = ""
}

variable "ssm_sessions" {
  type = object({
    enabled          = optional(bool, false)
    logs_bucket_name = optional(string, "")
  })
  description = "SSM Session Manager configuration with optional bucket for session logs."
  default     = {}
}

# --------------------------------------------------------------- networking ---

variable "public_accessible" {
  type        = bool
  description = "Toggle whether the NLB is publicly accessible."
  default     = false
}

variable "eip_allocation_ids" {
  type        = list(string)
  description = "Optional list of EIPs for NLB if it is publicly accessible."
  default     = []
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC"
}

variable "vpc_private_subnet_ids" {
  type        = list(string)
  description = "IDs of private subnets."
  default     = []
}

variable "vpc_public_subnet_ids" {
  type        = list(string)
  description = "ID of the public subnets. Only used if publicly accessible."
  default     = []
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "IDs of security groups to attach to the EC2 instances."
  default     = []
}

variable "vpc_endpoint_service" {
  type = object({
    enabled             = optional(bool, false)
    auto_accept_enabled = optional(bool, false)
    allowed_principals  = optional(list(string), [])
  })
  description = "Configuration for AWS VPC endpoint service. "
  default     = {}
}

# ================================================================== context ===

variable "aws_account_id" {
  type        = string
  description = "AWS account ID."
}

variable "aws_kv_namespace" {
  type        = string
  description = "AWS key-value namespace."
}

variable "aws_region_name" {
  type        = string
  description = "AWS region name."
}

variable "experimental_mode" {
  type        = bool
  description = "Toggle for experimental mode."
}
