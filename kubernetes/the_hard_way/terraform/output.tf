output "IP_controller" {
    value = [for u in aws_eip.kubernetes_controller: "${u.tags.Name} (${u.instance}): ${u.private_ip}, ${u.public_ip}"]
    description = "Controllers epastic IP"
}

output "IP_worker" {
    value = [for u in aws_eip.kubernetes_worker: "${u.tags.Name} (${u.instance}): ${u.private_ip}, ${u.public_ip}"]
    description = "Workers epastic IP"
}
