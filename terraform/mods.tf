###############################################################################
# Mod management, decoupled from the instance lifecycle.
#
# The mod list lives in an SSM parameter (the single source of truth) instead
# of being baked into user_data. The instance reads it at boot and can re-sync
# on demand, so changing var.mod_urls updates the parameter in place and pushes
# the new list to the *running* server -- no instance replacement required.
###############################################################################

resource "aws_ssm_parameter" "mod_urls" {
  name        = "/${var.project_name}/mod_urls"
  description = "Comma-separated list of mod .jar URLs for the Minecraft server."
  type        = "String"
  tier        = "Intelligent-Tiering" # auto-upgrades past the 4KB Standard limit for long lists
  value       = join(",", local.effective_mod_urls)
}

# Let the instance role read (only) the mod-list parameter.
data "aws_iam_policy_document" "read_mod_param" {
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [aws_ssm_parameter.mod_urls.arn]
  }
}

resource "aws_iam_role_policy" "read_mod_param" {
  name   = "${var.project_name}-read-mod-param"
  role   = aws_iam_role.minecraft.id
  policy = data.aws_iam_policy_document.read_mod_param.json
}

# When the mod list changes, push it to the already-running instance via SSM
# Run Command (runs /opt/minecraft/refresh-mods.sh as root). Best-effort: on
# first creation / instance replacement the instance may still be provisioning,
# in which case the boot-time sync applies the list instead. Requires the AWS
# CLI locally (same credentials Terraform uses); on_failure = continue keeps
# `terraform apply` from breaking if it is unavailable.
resource "terraform_data" "sync_mods" {
  triggers_replace = [aws_ssm_parameter.mod_urls.value]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    on_failure  = continue
    command     = <<-EOT
      cmd_id=$(aws ssm send-command \
        --region ${var.aws_region} \
        --instance-ids ${aws_instance.minecraft.id} \
        --document-name AWS-RunShellScript \
        --comment "Refresh Minecraft mods" \
        --parameters 'commands=["/opt/minecraft/refresh-mods.sh"]' \
        --query 'Command.CommandId' --output text 2>/dev/null) \
        && echo "Mod refresh dispatched to ${aws_instance.minecraft.id} (command $cmd_id)." \
        || echo "Mod refresh not dispatched (instance still provisioning?); boot-time sync will apply the list."
    EOT
  }

  depends_on = [aws_ssm_parameter.mod_urls, aws_instance.minecraft]
}
