data "aws_ami" "joidevops" {
  most_recent = true
  owners      = ["973714476881"]

  filter {
    name   = "name"
    values = ["Redhat-9-DevOps-Practice"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${var.project}/${var.environment}/private_subnet_ids"
}

data "aws_ssm_parameter" "security_group_id" {
  name = "/${var.project}/${var.environment}/${var.component}_security_group_id"
}

data "aws_ssm_parameter" "backend_alb_listener_arn" {
  name = "/${var.project}/${var.environment}/${var.component}/backend_alb_listener_arn"
}

data "aws_ssm_parameter" "frontend_alb_listener_arn" {
  name = "/${var.project}/${var.environment}/${var.component}/frontend_alb_listener_arn"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project}/${var.environment}/${var.component}/vpc_id"
}