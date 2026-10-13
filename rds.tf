resource "random_password" "db" {
  length  = 24
  special = false
}

# Allow Postgres only from the private (node) subnets
resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "PostgreSQL from the private subnets only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private[*].cidr_block
  }
}

# Practice setup: plain connections so Prisma works without extra CA settings.
# For production, keep rds.force_ssl = 1 and configure the RDS CA.
resource "aws_db_parameter_group" "pg" {
  name_prefix = "${local.name}-pg16-"
  family      = "postgres16"

  parameter {
    name         = "rds.force_ssl"
    value        = "0"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${local.name}-pg"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "animethreads"
  username = "postgres"
  password = random_password.db.result

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.pg.name
  publicly_accessible    = false

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
}