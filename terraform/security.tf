###############################################################################
# Security group: allow the Minecraft port from the internet (configurable),
# optional SSH from a restricted CIDR, and all egress.
###############################################################################

resource "aws_security_group" "minecraft" {
  name        = "${var.project_name}-sg"
  description = "Allow Minecraft and optional SSH access"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "minecraft" {
  for_each = toset(var.allowed_minecraft_cidrs)

  security_group_id = aws_security_group.minecraft.id
  description       = "Minecraft client traffic"
  cidr_ipv4         = each.value
  from_port         = var.minecraft_port
  to_port           = var.minecraft_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.minecraft.id
  description       = "SSH administrative access"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.minecraft.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
