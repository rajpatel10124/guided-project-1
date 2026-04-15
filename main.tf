# Security Group to allow Web and SSH access
resource "aws_security_group" "web_sg" {
  name   = "scholaris-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For production, change to your specific IP
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# The EC2 Instance
resource "aws_instance" "app_server" {
  ami           = "ami-0ec10929233384c7f" # Ubuntu 24.04  
  instance_type = "m7i-flex.large"
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name      = "terra" # Ensure this key exists in AWS Console!

  # THIS IS THE BLOCK YOU NEED
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "Scholaris-Server" }

  # This script runs on the FIRST BOOT of the instance
  user_data = <<-EOF
              #!/bin/bash
              # 1. Install Docker & Docker Compose
              apt-get update -y
              apt-get install -y docker.io docker-compose-v2 git

              # 2. Start Docker service
              systemctl start docker
              systemctl enable docker

              # 3. Clone your project
              cd /home/ubuntu
              git clone https://github.com/rajpatel10124/guided-project-1.git
              cd guided-project-1

              # 4. Set up basic environment (User should rotate these in production!)
              echo "POSTGRES_PASSWORD=scholaris_secure_pw_2024" > .env
              echo "SECRET_KEY=$(openssl rand -hex 24)" >> .env

              # 5. Build and Run with Docker Compose
              # We use --build to ensure the latest app.py fixes are included
              docker compose up -d --build
              EOF
}