# MyProxy terraform project
#
# deploys 1 public networks + 1 bastion hosts


variable "aws_region" {
	default = "eu-central-1"
  #default = "us-east-1"
}


# defined in creds.tf
provider "aws" {
  access_key = var.aws_ak1
  secret_key = var.aws_sk1
  region = var.aws_region
}

variable "aws_key" {
  default = "kea1"
}



#### networking variables

variable "vpc1_cidr" {
    description = "CIDR for the VPC"
    default = "172.18.0.0/22"
}


variable "subnetpub1" {
    type    = map
    default = { name = "public1", cidr = "172.18.0.0/24", az = "a" }
}


#### networking create

resource "aws_vpc" "default" {
    cidr_block = var.vpc1_cidr
    enable_dns_hostnames = true 
    enable_dns_support   = true
    tags = { Name = "pxvpc" }
}


##### nat, private subnets ####

resource "aws_internet_gateway" "igw1" {
    vpc_id = aws_vpc.default.id
}

# assign eip to igw1
resource "aws_eip" "igw1ip" {
  vpc        = true
  depends_on = [aws_internet_gateway.igw1]
}


## Default route to Internet

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw1.id
  depends_on = [aws_internet_gateway.igw1]
}

## Routing table

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id
  route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw1.id
    }
  depends_on = [aws_internet_gateway.igw1]

  tags = {
       Name = "Public route table proxy"
  }
}


## Route tables associations

# Associate subnet public_subnet to public route table
resource "aws_route_table_association" "public_subnet_association1" {
    subnet_id = aws_subnet.public1.id
    route_table_id = aws_route_table.public.id
    depends_on = [aws_internet_gateway.igw1, aws_subnet.public1]
}


## networks

# public1
resource "aws_subnet" "public1" {
  vpc_id     = aws_vpc.default.id
  cidr_block = var.subnetpub1["cidr"]
  availability_zone = format("%s%s",var.aws_region,var.subnetpub1["az"])
  tags = { Name =  var.subnetpub1["name"] }
}




#### NACL

resource "aws_network_acl" "public_nacl1" {
  vpc_id     = aws_vpc.default.id
  subnet_ids = formatlist( "%s", ["${aws_subnet.public1.id}"] )
  #subnet_ids = formatlist( "%s", ["${aws_subnet.public1.id}", "${aws_subnet.public2.id}"] )


  egress {
    from_port   = 0
    to_port     = 0
    rule_no    = 200
    action     = "allow"
    protocol    = "-1"
    cidr_block = "0.0.0.0/0"
  }

  ingress {
    protocol    = "tcp"
    rule_no    = 201
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port   = 22
    to_port     = 22
  }

  egress {
    protocol   = -1
    rule_no    = 202
    action     = "allow"
    cidr_block = var.vpc1_cidr
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = -1
    rule_no    = 203
    action     = "allow"
    cidr_block = var.vpc1_cidr
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol    = "tcp"
    rule_no    = 210
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port   = 4096
    to_port     = 65535
  }

  tags = {
    Name = "pub-main"
  }

}




#### SG

resource "aws_default_security_group" "default" {
  vpc_id     = aws_vpc.default.id
}


resource "aws_security_group" "sg_bastion" {
  name = "sg_bastion"
  description = "ACL rules for Bastion hosts"
  vpc_id     = aws_vpc.default.id

  ingress {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc1_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_security_group" "sg_ssh" {
  name = "sg_ssh"
  description = "ACL rules for ssh access to hosts"
  vpc_id     = aws_vpc.default.id

  ingress {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.vpc1_cidr]
  }

  egress {
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc1_cidr]
  }

}



# attach SG to bastion hosts

resource "aws_network_interface_sg_attachment" "sg_attachment1" {
  security_group_id    = aws_security_group.sg_bastion.id
  network_interface_id = aws_instance.bastion1.primary_network_interface_id
  depends_on = [aws_instance.bastion1]
}



# look for Debian 10 AMI
# ! x86 !
#
data "aws_ami" "image_deb10" {
  most_recent = true

  filter {
    name = "name"
    values = [ "debian*10*" ]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }

  owners = [ "679593333241" ]
}

#output "u18out" {
#  value = data.aws_ami.image_bast
#  depends_on = [data.aws_ami.image_bast]
#}

output "deb10out" {
  value = data.aws_ami.image_deb10
  depends_on = [data.aws_ami.image_deb10]
}





# proxy instance
resource "aws_instance" "bastion1" {
  #ami           = data.aws_ami.image_bast.id
  ami           = data.aws_ami.image_deb10.id

  instance_type = "t2.nano"

  tags = {
    Name = "proxy1"
  }

  key_name = var.aws_key

  associate_public_ip_address = "true"

  security_groups = [  ]

  root_block_device {
    volume_size = "15"   # root device size, GB
  }

  private_ip = "172.18.0.4"
  subnet_id = aws_subnet.public1.id

  depends_on = [aws_internet_gateway.igw1]
}

 output "bastion1out" {
  value = formatlist( "#inv bastions pub=%s priv=%s key=%s name=%s", aws_instance.bastion1.public_ip, aws_instance.bastion1.private_ip, aws_instance.bastion1.key_name,  aws_instance.bastion1.tags["Name"])
  depends_on = [aws_instance.bastion1]
}


