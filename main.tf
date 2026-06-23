resource "aws_instance" "main" {
  ami           = local.ami_id
  instance_type = "t3.micro"
  subnet_id = local.private_subnet_ids[0]
  vpc_security_group_ids = [local.security_group_id]

  tags = merge(
    {
        Name = "${var.project}-${var.environment}-${var.component}"
    },
    local.common_tags
  )
}

resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id 
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.main.private_ip
  }

  provisioner "file" {
    source      = "ansible.sh"                                                 # Local file path
    destination = "/tmp/ansible.sh"                                            # Destination path on the remote machine
  }

  provisioner "remote-exec" {
    inline = [
        "chmod +x /tmp/ansible.sh",
        "sudo sh /tmp/ansible.sh ${var.component} ${var.environment} ${var.app_version}"
    ]
  }
}

resource "aws_ec2_instance_state" "main" {                                        #this will stop the instance
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on = [terraform_data.main] 
}

resource "aws_ami_from_instance" "main" {
  name               = "${var.project}-${var.environment}-${var.component}"
  source_instance_id = aws_instance.main.id
  depends_on = [aws_ec2_instance_state.main]
  tags = merge(
    {
        Name = "${var.project}-${var.environment}-${var.component}"
    },
    local.common_tags
  )
}

resource "aws_lb_target_group" "main" {                                            #alb target group
  name     = "${var.project}-${var.environment}-${var.component}"
  port     = local.port_number
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  deregistration_delay = 60

  health_check {
    healthy_threshold = 2
    interval = 10
    matcher = "200-299"
    path = "local.health_check_path"
    port = local.port_number
    protocol = "HTTP"
    timeout = 2
    unhealthy_threshold = 3
  }
}

resource "aws_launch_template" "main" {
  name = "${var.project}-${var.environment}-${var.component}"
  image_id = aws_ami_from_instance.main.id
  instance_initiated_shutdown_behavior = "terminate"                               #once asg sees less traffic it will start terminating instance.
  instance_type = "t3.micro"
  vpc_security_group_ids = [local.security_group_id]

  update_default_version = true                                                    #each time we update terraform this version gets updated by default.

  tag_specifications {
    resource_type = "instance"

     tags =merge(
     {
        Name = "${var.project}-${var.environment}-${var.component}"
    },
    local.common_tags
   )
  }

  tag_specifications {                                               
    resource_type = "volume"

     tags =merge(
     {
        Name = "${var.project}-${var.environment}-${var.component}"
    },
    local.common_tags
   )
  }

  tags =merge(                                                                         #for launch template
        {
           Name = "${var.project}-${var.environment}-${var.component}"
        },
        local.common_tags
  )
}

resource "aws_autoscaling_group" "main" {                                             #asg
  name                      = "${var.project}-${var.environment}-${var.component}"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 3
  force_delete              = false
  
  launch_template {
    id = aws_launch_template.main.id
    version = "$Latest"
  }
  
  vpc_zone_identifier = local.private_subnet_ids
  target_group_arns = [aws_lb_target_group.main.arn]

  instance_refresh {                                                                       #this will refresh the instances when evere there is an new version rolled out.
    strategy = "Rolling"                                                                                       #so new instances are created and old ones are deleted.
    preferences {
      min_healthy_percentage = 50 
    }
    triggers = ["launch_template"]
  }
  
  dynamic "tag" {                                                                         
    for_each = merge(
     {
        Name = "${var.project}-${var.environment}-${var.component}"
     },
      local.common_tags
    )

   content {
     key                 = tag.key
     value               = tag.value
     propagate_at_launch = true                                                           #whenever the ASG launches a new EC2 instance, these tags are automatically applied to the instance.                                                          
   }
  }
 
  timeouts {                                                                               #if this process is not completed with in 15mins then this will destroy                                                            
    delete = "15m"
  }
}

resource "aws_autoscaling_policy" "main" {                                            #This Terraform resource creates an Auto Scaling Policy, which will Automatically add or remove EC2 instances based on CPU usage.
  autoscaling_group_name = aws_autoscaling_group.main.name
  name      = "${var.project}-${var.environment}-${var.component}"
  policy_type            = "TargetTrackingScaling"
  estimated_instance_warmup = 120                                                          


  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 70.0
  }
}

resource "aws_lb_listener_rule" "main" {                                              #This Terraform resource creates a Listener Rule on the Backend Application Load Balancer(ALB)
  listener_arn = local.aws_lb_listener_arn                                          
  priority     = var.role_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = [local.host_header]
    }
  }
} 

resource "terraform_data" "main_delete" {                                            #This intended to terminate the temporary EC2 instance that was used to create the Launch Template/AMI before the Auto Scaling Group takes over.
  triggers_replace = [
    aws_instance.main.id
  ]
  depends_on = [ aws_autoscaling_group.main ]

  provisioner "local-exec" {                                                                #this is executed in bastion
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }
}
