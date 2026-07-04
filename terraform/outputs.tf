output "server_ip" {
  description = "Public IP address players connect to."
  value       = aws_eip.minecraft.public_ip
}

output "connection_address" {
  description = "Address to paste into the Minecraft client's 'Add Server' dialog."
  value       = "${aws_eip.minecraft.public_ip}:${var.minecraft_port}"
}

output "instance_id" {
  description = "EC2 instance ID (use with SSM Session Manager)."
  value       = aws_instance.minecraft.id
}

output "ssm_connect_command" {
  description = "Open a shell on the server without SSH via AWS Session Manager."
  value       = "aws ssm start-session --target ${aws_instance.minecraft.id} --region ${var.aws_region}"
}

output "logs_hint" {
  description = "How to watch provisioning + server logs once connected."
  value       = "tail -f /var/log/minecraft-setup.log ; cd /opt/minecraft && docker compose logs -f"
}

output "mod_list_parameter" {
  description = "SSM parameter holding the mod list (source of truth)."
  value       = aws_ssm_parameter.mod_urls.name
}

output "refresh_mods_command" {
  description = "Manually re-sync mods to the running server (Terraform also does this automatically on mod changes)."
  value       = "aws ssm send-command --region ${var.aws_region} --instance-ids ${aws_instance.minecraft.id} --document-name AWS-RunShellScript --parameters 'commands=[\"/opt/minecraft/refresh-mods.sh\"]'"
}

output "curseforge_modpack_sync" {
  description = "CurseForge modpack resolution status (empty when sync is disabled)."
  value = var.curseforge_modpack_project_id > 0 ? {
    project_id         = var.curseforge_modpack_project_id
    modpack_file_id    = try(data.external.curseforge_mod_urls[0].result.modpack_file_id, "")
    modpack_name       = try(data.external.curseforge_mod_urls[0].result.modpack_name, "")
    modpack_version    = try(data.external.curseforge_mod_urls[0].result.modpack_version, "")
    resolved_mod_count = try(data.external.curseforge_mod_urls[0].result.count, "0")
    extra_mod_count    = length(var.mod_urls_extra)
  } : null
}
