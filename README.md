# terraform-aws-network-protocol-proxy

This terraform module provisions a simple, scalable tcp proxy based on haproxy.
It deploys an EC2 autoscaling group behind a network load balancer (NLB), sets
up cloudwatch logging, optionally configures a vpc endpoint service, and
provides a configurable way to forward tcp traffic to any specified backend
target.

## how it works

- an ec2 autoscaling group is created, each instance running haproxy
- a network load balancer routes incoming traffic on tcp ports you define
- haproxy listens on the same ports and forwards traffic to your backend
  target(s)
- security group rules are created to allow ingress on the listener port from
  allowed cidrs
- optional vpc endpoint service can be created if you need a private service endpoint

## usage

```hcl
module "network_protocol_proxy" {
  source  = "cruxstack/network-protocol-proxy/aws"
  version = "x.x.x"

  name                   = "database-proxy"
  vpc_id                 = "vpc-1234567890abcdef"
  vpc_public_subnet_ids  = ["subnet-1234abcd", "subnet-5678efgh"]
  vpc_private_subnet_ids = ["subnet-1234abcd", "subnet-5678efgh"]
  vpc_pr

  proxies = {
    default = {
      target                 = "10.0.1.10:5432"
      listener_port          = 10432
      listener_allowed_cidrs = [
        {
          cidr        = "0.0.0.0/0"
          description = "allow all inbound for testing"
        }
      ]
    }
  }
}
```

## inputs

| name                     | type         | default | description                                                  |
|--------------------------|--------------|---------|--------------------------------------------------------------|
| `enabled`                | bool         | `true`  | enable or disable the module                                 |
| `proxies`                | object(...)  | n/a     | configuration for one or more haproxy proxies                |
| `capacity`               | object(...)  | `{}`    | autoscaling desired, min, max settings                       |
| `logs_bucket_name`       | string       | `""`    | s3 bucket name for logs                                      |
| `ssm_sessions`           | object(...)  | `{}`    | enable session manager logging                               |
| `public_accessible`      | bool         | `false` | set to true to place the nlb in public subnets               |
| `eip_allocation_ids`     | list(string) | `[]`    | list of eip allocation ids for the nlb                       |
| `vpc_id`                 | string       | n/a     | id of the vpc                                                |
| `vpc_private_subnet_ids` | list(string) | `[]`    | list of private subnet ids                                   |
| `vpc_public_subnet_ids`  | list(string) | `[]`    | list of public subnet ids                                    |
| `vpc_security_group_ids` | list(string) | `[]`    | additional security group ids to attach to the instances     |
| `vpc_endpoint_service`   | object(...)  | `{}`    | configuration for optionally creating a vpc endpoint service |
| `aws_account_id`         | string       | n/a     | your aws account id                                          |
| `aws_kv_namespace`       | string       | n/a     | your aws k/v namespace                                       |
| `aws_region_name`        | string       | n/a     | the aws region                                               |
| `experimental_mode`      | bool         | n/a     | toggles extra debug or development settings                  |

## outputs

| name            | description                          |
|-----------------|--------------------------------------|
| `nlb_dns_name`  | the dns name of the network lb (nlb) |

