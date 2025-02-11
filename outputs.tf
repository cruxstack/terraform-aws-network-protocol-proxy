output "nlb_dns_name" {
  value       = try(module.nlb[0].nlb_dns_name, "")
  description = "dns name of the network lb (nlb)"
}
