resource "aws_db_subnet_group" "main" {
  name       = "scholaris-db-subnets"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_db_instance" "db" {
  allocated_storage    = 20
  db_name              = "scholaris"
  engine               = "postgres"
  instance_class       = "db.t3.micro"
  username             = "scholaris_admin"
  password             = "ScholarisPass123"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
}

resource "aws_efs_file_system" "fs" {
  creation_token = "scholaris-efs"
  tags = { Name = "Scholaris-Shared-Storage" }
}

resource "aws_efs_mount_target" "a" {
  file_system_id = aws_efs_file_system.fs.id
  subnet_id      = aws_subnet.public_a.id
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_efs_mount_target" "b" {
  file_system_id = aws_efs_file_system.fs.id
  subnet_id      = aws_subnet.public_b.id
  security_groups = [aws_security_group.efs_sg.id]
}