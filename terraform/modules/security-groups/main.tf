resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "Allows inbound HTTP from internet"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.environment}-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "Allows inbound traffic only from ALB"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.environment}-app-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.environment}-rds-sg"
  description = "Allows inbound traffic only from App tier"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.environment}-rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80

  tags = {
    Name = "${var.environment}-alb-allow-http"
  }
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = {
    Name = "${var.environment}-alb-all"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id
  referenced_security_group_id  = aws_security_group.alb.id
  from_port         = 8000
  ip_protocol       = "tcp"
  to_port           = 8000

  tags = {
    Name = "${var.environment}-app-alb"
  }
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = {
    Name = "${var.environment}-app-all"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  security_group_id = aws_security_group.rds.id
  referenced_security_group_id  = aws_security_group.app.id
  from_port         = 5432
  ip_protocol       = "tcp"
  to_port           = 5432

  tags = {
    Name = "${var.environment}-rds-app"
  }
}
