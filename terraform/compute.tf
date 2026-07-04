###############################################################################
# Amazon Linux 2023 AMI (resolved from the public SSM parameter).
###############################################################################

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

###############################################################################
# IAM role so the instance can be managed via SSM Session Manager
# (browser/CLI shell without needing an SSH key or open port 22).
###############################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "minecraft" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.minecraft.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "minecraft" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.minecraft.name
}

###############################################################################
# Persistent data volume (world + mods). Kept separate from the root volume so
# the instance can be replaced/resized without losing the world.
###############################################################################

resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"

  tags = {
    Name = "${var.project_name}-data"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "data" {
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.data.id
  instance_id  = aws_instance.minecraft.id
  force_detach = true
}

###############################################################################
# The server instance.
###############################################################################

resource "aws_instance" "minecraft" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.minecraft.id]
  iam_instance_profile   = aws_iam_instance_profile.minecraft.name
  key_name               = var.ssh_key_name != "" ? var.ssh_key_name : null

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    data_volume_id    = aws_ebs_volume.data.id
    mod_loader        = var.mod_loader
    minecraft_version = var.minecraft_version
    server_memory     = var.server_memory
    motd              = var.motd
    difficulty        = var.difficulty
    max_players       = var.max_players
    ops               = var.ops
    seed              = var.seed
    minecraft_port    = var.minecraft_port
    server_image_tag  = var.server_image_tag

    idle_shutdown_minutes = var.idle_shutdown_minutes
    # Mods are read from this SSM parameter at boot (by name, not value), so the
    # rendered user_data is stable when only the mod list changes.
    aws_region     = var.aws_region
    mod_param_name = aws_ssm_parameter.mod_urls.name
  })

  # Re-run provisioning when the rendered config changes.
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${var.project_name}-server"
  }
}

###############################################################################
# Stable public address.
###############################################################################

resource "aws_eip" "minecraft" {
  instance = aws_instance.minecraft.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }

  depends_on = [aws_internet_gateway.this]
}
