# modules/alb/main.tf

# 1. Security Group for ALB
resource "aws_security_group" "alb" { # Creates a security group for ALB (load balancer)
  name        = "${var.project_name}-alb-sg" # Name of the security group
  description = "Allow HTTPS inbound traffic" # Description of purpose
  vpc_id      = var.vpc_id # Attaches this security group to your VPC

  ingress {
    description = "HTTPS from internet" # Rule description
    from_port   = 443 # Start port (HTTPS)
    to_port     = 443 # End port (HTTPS) When both are same → only one port is allowed
    protocol    = "tcp" # Protocol used
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic from anywhere (public access)
  }

  ingress {
    description = "HTTP redirect to HTTPS" # Rule description
    from_port   = 80 # Start port (HTTP)
    to_port     = 80 # End port (HTTP)
    protocol    = "tcp" # Protocol used
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic from anywhere
  }

  egress {
    from_port   = 0 # Start port (all ports)
    to_port     = 0 # End port (all ports)
    protocol    = "-1" # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound traffic to anywhere
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-alb-sg" }) # Adds tags (common + name)
}
# 2. Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false  # Internet-facing ALB (public)
  load_balancer_type = "application" # ALB for HTTP/HTTPS traffic
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false # set to true Production Best Practice

  tags = merge(var.common_tags, { Name = "${var.project_name}-alb" })
}

resource "aws_lb_target_group" "app" { # Creates a target group (where ALB sends traffic)
  name        = "${var.project_name}-tg" # Name of target group
  port        = 8080 # App runs on port 8080 (Bankapp)
  protocol    = "HTTP" # Communication protocol
  vpc_id      = var.vpc_id # Target group belongs to this VPC
  target_type = "ip" # Targets are IPs (used for EKS pods)

  health_check {
    enabled             = true # Enables health check
    path                = "/actuator/health" # Endpoint to check app health
    interval            = 30 # Check every 30 seconds
    timeout             = 5 # Wait 5 seconds for response
    healthy_threshold   = 3 # 3 successful checks = healthy
    unhealthy_threshold = 3 # 3 failed checks = unhealthy
  }
}

# 4. HTTPS Listener
resource "aws_lb_listener" "https" { # Listens for HTTPS traffic on ALB
  load_balancer_arn = aws_lb.main.arn # Attach to ALB
  port              = "443" # HTTPS port
  protocol          = "HTTPS" # Secure protocol
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # TLS security policy
  certificate_arn   = var.certificate_arn # SSL certificate for HTTPS

  default_action {
    type             = "forward" # Forward traffic
    target_group_arn = aws_lb_target_group.app.arn # Send traffic to target group (your app)
  }
}

# 5. HTTP to HTTPS Redirect
resource "aws_lb_listener" "http_redirect" { # Listens for HTTP traffic
  load_balancer_arn = aws_lb.main.arn # Attach to ALB
  port              = "80" # HTTP port
  protocol          = "HTTP" # Protocol

  default_action {
    type = "redirect" # Redirect instead of forward

    redirect {
      port        = "443" # Redirect to HTTPS port
      protocol    = "HTTPS" # Use HTTPS
      status_code = "HTTP_301" # Permanent redirect
    }
  }
} 

# User hits load balancer
# Listener receives request
# Listener says → “Send this to target group”
# Target group sends request to your app