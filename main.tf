provider "aws" {
  region = "us-east-1"
}

# VPC creation
resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "MyTerraformVPC"
  }
}

resource "aws_subnet" "Publicsubnet1" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "Public Subnet 1"
  }
}

resource "aws_subnet" "Publicsubnet2" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "Public Subnet 2"
  }
}

resource "aws_subnet" "Privatesubnet1" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "Private Subnet 1"
  }
}

resource "aws_subnet" "Privatesubnet2" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "Private Subnet 2"
  }
}

# Internet Gateway 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
  tags = {
    Name = "Internet Gateway"
  }
}


resource "aws_route_table" "PublicRT" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route_table_association" "PublicRTassociation1" {
  subnet_id      = aws_subnet.Publicsubnet1.id
  route_table_id = aws_route_table.PublicRT.id
}

resource "aws_route_table_association" "PublicRTassociation2" {
  subnet_id      = aws_subnet.Publicsubnet2.id
  route_table_id = aws_route_table.PublicRT.id
}

resource "aws_eip" "nat_eip" {
  tags = {
    Name = "NAT EIP"
  }
}

# NAT Gateway 
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.Publicsubnet1.id
  tags = {
    Name = "NAT Gateway"
  }
}


resource "aws_route_table" "PrivateRT" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "Private Route Table"
  }
}

resource "aws_route_table_association" "PrivateRTassociation1" {
  subnet_id      = aws_subnet.Privatesubnet1.id
  route_table_id = aws_route_table.PrivateRT.id
}

resource "aws_route_table_association" "PrivateRTassociation2" {
  subnet_id      = aws_subnet.Privatesubnet2.id
  route_table_id = aws_route_table.PrivateRT.id
}

# CMK Key
resource "aws_kms_key" "my_cmk" {
  description             = "KMS CMK for EC2 and RDS encryption"
  key_usage               = "ENCRYPT_DECRYPT"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = "my-cmk"
  }
}

resource "aws_kms_alias" "my_cmk_alias" {
  name          = "alias/my-cmk-alias"
  target_key_id = aws_kms_key.my_cmk.key_id
}

# Security group
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.myvpc.id
  name   = "ec2-sg"

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

  tags = {
    Name = "EC2 Security Group"
  }
}

# EC2 instance in the private subnet in AZ1 volumes with CMK created abvove
resource "aws_instance" "instance1" {
  ami                    = "ami-0ebfd941bbafe70c6"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.Privatesubnet1.id
  key_name               = "my-key-pair"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  root_block_device {
    encrypted  = true
    kms_key_id = aws_kms_key.my_cmk.arn
  }

  tags = {
    Name = "Private EC2 Instance"
  }
}


resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.Privatesubnet1.id, aws_subnet.Privatesubnet2.id]

  tags = {
    Name = "RDS Subnet Group"
  }
}

# RDS instance in the private subnet with CMK Key created above
resource "aws_db_instance" "rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  username             = var.db_username
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  storage_encrypted    = true
  kms_key_id           = aws_kms_key.my_cmk.arn
  publicly_accessible  = false
  skip_final_snapshot  = true

  tags = {
    Name = "MyRDSInstance"
  }
}

