# Minecraft server control.
# Requires: aws CLI (configured) and terraform. The instance ID and address are
# read from Terraform outputs, so these targets keep working across rebuilds.

REGION   ?= us-east-1
TF_DIR   := terraform
INSTANCE  = $(shell cd $(TF_DIR) && terraform output -raw instance_id 2>/dev/null)

.DEFAULT_GOAL := help

.PHONY: help start stop status address connect logs mods

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

start: ## Start the EC2 instance (Minecraft auto-starts on boot)
	@aws ec2 start-instances --region $(REGION) --instance-ids $(INSTANCE) \
	  --query 'StartingInstances[0].{Instance:InstanceId,State:CurrentState.Name}' --output table
	@echo "Waiting for the instance to reach 'running'..."
	@aws ec2 wait instance-running --region $(REGION) --instance-ids $(INSTANCE)
	@echo "Instance is running. The server accepts connections in ~1-2 min at $$(cd $(TF_DIR) && terraform output -raw connection_address)."

stop: ## Stop the EC2 instance (halts compute billing; world is saved)
	@aws ec2 stop-instances --region $(REGION) --instance-ids $(INSTANCE) \
	  --query 'StoppingInstances[0].{Instance:InstanceId,State:CurrentState.Name}' --output table

status: ## Show the instance power state
	@aws ec2 describe-instances --region $(REGION) --instance-ids $(INSTANCE) \
	  --query 'Reservations[0].Instances[0].State.Name' --output text

address: ## Print the server connection address
	@cd $(TF_DIR) && terraform output -raw connection_address && echo

connect: ## Open a root shell on the server (SSM Session Manager; Ctrl-D to exit)
	@aws ssm start-session --region $(REGION) --target $(INSTANCE)

logs: ## Show the most recent Minecraft server logs
	@cmd=$$(aws ssm send-command --region $(REGION) --instance-ids $(INSTANCE) \
	  --document-name AWS-RunShellScript \
	  --parameters 'commands=["docker logs --tail 80 minecraft 2>&1 | sed -r \"s/\\x1B\\[[0-9;]*[mK]//g\""]' \
	  --query 'Command.CommandId' --output text); \
	  sleep 5; \
	  aws ssm get-command-invocation --region $(REGION) --command-id $$cmd --instance-id $(INSTANCE) \
	  --query 'StandardOutputContent' --output text

mods: ## Re-sync the mod list (from terraform.tfvars) to the running server
	@aws ssm send-command --region $(REGION) --instance-ids $(INSTANCE) \
	  --document-name AWS-RunShellScript \
	  --parameters 'commands=["/opt/minecraft/refresh-mods.sh"]' \
	  --query 'Command.CommandId' --output text
	@echo "Mod refresh dispatched. Watch with: make logs"

curseforge-preview: ## Preview mod URLs resolved from your CurseForge modpack (requires CURSEFORGE_API_KEY)
	@cd $(TF_DIR) && terraform output -json curseforge_modpack_sync 2>/dev/null | python3 -m json.tool || \
	  (echo "Set curseforge_modpack_project_id in terraform.tfvars and run: export CURSEFORGE_API_KEY=... && cd terraform && terraform plan")
