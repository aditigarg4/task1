provider "aws" {
  region = "ap-south-1"
  profile = "lwprofile"
}


resource "tls_private_key" "pkey" {
  algorithm   = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "mykey" {
  key_name   = "mykey"
  public_key = tls_private_key.pkey.public_key_openssh
}

resource "aws_security_group" "allow_traffic" {
  name        = "allow_traffic"
  description = "Allow TLS inbound traffic"
  vpc_id      = "vpc-4ab4a922"

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


 ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
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
    Name = "allow_traffic"
  }
}

resource "aws_instance" "instance_ec2" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  security_groups = ["allow_traffic"]
  key_name 	=  "mykey"


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.pkey.private_key_pem
    host     = aws_instance.instance_ec2.public_ip
  }


  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"
    ]
  }
  tags = {
    Name = "firstos"
  }
}

resource "aws_ebs_volume" "ebs1" {

  availability_zone = aws_instance.instance_ec2.availability_zone
  size              = 1

  tags = {
    Name = "firstebs"
  }
}


resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs1.id
  instance_id = aws_instance.instance_ec2.id
}


resource "null_resource" "null1"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.pkey.private_key_pem
    host     = aws_instance.instance_ec2.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/aditigarg4/aditi.git /var/www/html/"
    ]
  }
}


resource "aws_s3_bucket" "lwbucket12" {
  bucket = "lwbucket123"
  acl    = "public-read"
  region = "ap-south-1"

  tags = {
    Name        = "lwbucket123"
  }
}


resource "aws_s3_bucket_object" "image" {

depends_on = [
    aws_s3_bucket.lwbucket12,
  ]

  bucket = aws_s3_bucket.lwbucket12.bucket
  key    = "first.jpg"
  source = "C:/Users/user/Desktop/first.jpg"
  acl 	 = "public-read"
}



locals {
  s3_origin_id = "my-s3-origin-id"
}

resource "aws_cloudfront_distribution" "s3_distribution" {


depends_on = [
    aws_s3_bucket_object.image,
  ]

  origin {
    domain_name = aws_s3_bucket.lwbucket12.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }


  viewer_certificate {
    cloudfront_default_certificate = true
  }

  
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.pkey.private_key_pem
    host     = aws_instance.instance_ec2.public_ip
  } 

 
  provisioner "remote-exec" {
    inline = [
      "sudo su <<END",
      "echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image.key}' height='200' width='200'>\">> /var/www/html/index.php","END",
    ]
  }
}


resource "null_resource" "openwebsite" {


depends_on = [
    aws_cloudfront_distribution.s3_distribution,
    aws_volume_attachment.ebs_att,
  ]

 provisioner "local-exec" {
    command = "start chrome http://${aws_instance.instance_ec2.public_ip}/"
    
  }  
}
