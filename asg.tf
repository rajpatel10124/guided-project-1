data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_lb" "alb" {
  name               = "scholaris-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "scholaris-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path     = "/health"
    interval = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_launch_template" "lt" {
  name_prefix   = "scholaris-tpl-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = "terra"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile { name = aws_iam_instance_profile.scholaris_profile.name }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 30
      volume_type = "gp3"
    }
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nfs-common docker.io git
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu

              cd /home/ubuntu
              # Force latest code: Clone if missing, Pull if exists
              if [ ! -d "guided-project-1" ]; then
                for i in {1..5}; do git clone https://github.com/rajpatel10124/guided-project-1.git && break || sleep 5; done
              fi
              cd guided-project-1
              git pull origin main
              
              mkdir -p static/uploads
              # Wait for EFS mount target to be ready
              sleep 30
              mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.fs.dns_name}:/ /home/ubuntu/guided-project-1/static/uploads
              chown -R ubuntu:ubuntu /home/ubuntu/guided-project-1

              docker build -t scholaris-app .
              # Wait for RDS to be reachable
              until docker run --rm scholaris-app python3 -c "import socket; s = socket.socket(); s.connect(('${split(":", aws_db_instance.db.endpoint)[0]}', 5432))"; do
                echo "Waiting for RDS..."
                sleep 5
              done

              # Grant permissions to public schema (Necessary for RDS Postgres 15+)
              docker run --rm scholaris-app python3 -c "import sqlalchemy; engine=sqlalchemy.create_engine('postgresql://scholaris_admin:ScholarisPass123@${aws_db_instance.db.endpoint}/scholaris'); conn=engine.connect(); conn.execute(sqlalchemy.text('GRANT ALL ON SCHEMA public TO scholaris_admin')); conn.commit(); conn.close()" || true

              docker run -d --name scholaris-container \
                --restart always \
                -p 80:5000 \
                -e DATABASE_URL="postgresql://scholaris_admin:ScholarisPass123@${aws_db_instance.db.endpoint}/scholaris" \
                -e SECRET_KEY="something-very-secret-123" \
                -e MAIL_USERNAME="lykensolution@gmail.com" \
                -e MAIL_PASSWORD="dgmo vyaq ansy bmwu" \
                -e MAIL_SERVER="smtp.gmail.com" \
                -e MAIL_PORT=587 \
                --log-driver=awslogs \
                --log-opt awslogs-group=/aws/ec2/scholaris-app \
                --log-opt awslogs-region=us-east-1 \
                scholaris-app
              EOF
  )
}

resource "aws_autoscaling_group" "asg" {
  desired_capacity    = 1
  max_size            = 2
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.tg.arn]
  vpc_zone_identifier = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "scholaris-app-instance"
    propagate_at_launch = true
  }
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }
}

output "ALB_URL" { value = "http://${aws_lb.alb.dns_name}" }