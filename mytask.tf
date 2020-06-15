//firstTask

//creating a region variable
variable "enter_ur_region" {
	type = string

}

//creating a profile variable

variable "enter_ur_profile" {
	type = string

}



//aws login
provider "aws" {
  region = var.enter_ur_region
  profile = var.enter_ur_profile
  
}


//listing vpc id's
data "aws_vpcs" "foo" {
  }





//creating security grps

resource "aws_security_group" "SecurityGroups" {
  name        = "SecurityGroups"
  description = "Allow http inbound traffic"
  vpc_id      = element(data.aws_vpcs.foo.ids.*,0)
  

  ingress {
    description = "allowing ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allowing http traffic"
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
    Name = "SecurityGroupTerra"
  }

}





//creating ec2 key pair

resource "aws_key_pair" "SaloniKey" {
  key_name   = "Saloni-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQB51eLfnN20qXPKuvCCn9fnkoWB4iVFSJvjFJoHIGdNK+Q34sWKjC6++aiqP4s8zLDHwRDicwwfdQvJPoYUeJCrvwLmt+fT6tB1Dnu0YoAy66Tk6XZwlENyl6ylf3qK0l7Cun2TWPx7DCMMT31J0n8+8G+8+jr2CkqPP7Dy8fyOOV5PPYLHuG7uJuNwSHTWUr+U+3CoAxiQSmjNjVHYDS0CNyVTUh/M1uNxrjocJY9lu0+vHBL44H6qqyO6VNtGetNs6hhlyE9Ldkm7XuhDajeiK9x0b8Zvfq4BauwTFVxz74D47d3iyCzazpNfr1yS0MIYcUGjOc+Kalfred0YvYb9 rsa-key-20200611"
}


//creating instance

resource "aws_instance"  "SaloniOS1" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name	= aws_key_pair.SaloniKey.key_name
  security_groups =  ["SecurityGroups"]
  
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("D:/downloads/Saloni-key.pem")
    host     = aws_instance.SaloniOS1.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "SaloniOS1"
  }
}




//creating ebs volume

resource "aws_ebs_volume" "PD" {
  availability_zone = aws_instance.SaloniOS1.availability_zone
  size              = 1
  tags = {
    Name = "SaloniEBS"
  }
}


//attaching new volume

resource "aws_volume_attachment" "PD_att_detach" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.PD.id
  instance_id = aws_instance.SaloniOS1.id
  force_detach = true
}


//creating null resource for remote ebs volume mount commands
resource "null_resource" "nullremote1"  {

 depends_on = [
    aws_volume_attachment.PD_att_detach,
  ]

 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("D:/downloads/Saloni-key.pem")
    host     = aws_instance.SaloniOS1.public_ip
  }

 provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/saloni2398/Web.git /var/www/html/"
    ]
  }
}





//creating a S3 bucket

resource "aws_s3_bucket" "BucketTF" {
  bucket = "saloni.tf.test.bucket"
  
  versioning {
    enabled = true
  }

  tags = {
    Name        = "BucketTF"
    Environment = "Dev"
  }
}


//allowing public access
resource "aws_s3_bucket_public_access_block" "public" {
  bucket = aws_s3_bucket.BucketTF.id

  block_public_acls   = false
  block_public_policy = false

 
}

//local commands to download image from github
resource "null_resource" "nulllocal1"  {



   provisioner "local-exec" {
	    command = "git clone https://github.com/saloni2398/Web.git github"
  	}

    provisioner "local-exec" {
	    when = destroy
	    command = "rmdir /Q /S github "
  	}
	
}







//creating object in the given bucket name
resource "aws_s3_bucket_object" "bucket_object" {
  depends_on = [
    null_resource.nulllocal1
  ]
  
  key        = "smiley.png"
  bucket     = aws_s3_bucket.BucketTF.id
  source     = "github/smiley.png"
   acl    = "public-read"
  
 }





//creating cloudfront distribution and performinf remote operation in the php file using provisioner

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "access-identity-saloni.tf.test.bucket.s3.amazonaws.com"
}





resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.BucketTF.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.BucketTF.id}"
    s3_origin_config {
  	origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
   }
    

}
    

  enabled             = true
  is_ipv6_enabled     = true
  
 

  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-saloni.tf.test.bucket"

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

  
  
  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
      
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("D:/downloads/Saloni-key.pem")
    host     = aws_instance.SaloniOS1.public_ip
  }

 provisioner "remote-exec" {
    inline = [
	"sudo su << EOF",
	"echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.bucket_object.key}'>\" >>/var/www/html/index.php"
    
     
    ]
  }



}


//at the end the website automatically opens

resource "null_resource" "nulllocal2"  {


depends_on = [
    aws_cloudfront_distribution.s3_distribution
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.SaloniOS1.public_ip}"
  	}
}




