data "aws_availability_zones" "available" {} 
#Fetches available AZs (like ap-south-1a, ap-south-1b)

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr #It defines the network range for the VPC so all resources get private IPs within that range
  enable_dns_hostnames = true #Gives DNS names to instances
  enable_dns_support   = true #Resources can resolve domain names (like google.com → IP)

  tags = merge(var.common_tags, { Name = "${var.project_name}-vpc" })
  #Adds labels to your VPC for easier management and cost tracking. The merge function combines common_tags with a specific Name tag.
    #  var.common_tags → your default tags (like Environment, Owner, etc.)
    # { Name = "${var.project_name}-vpc" } → adds a specific tag for this resource
    # merge() → combines both into one map
    # var.common_tags = {
    # Environment = "prod"
    # Owner       = "DevOps"
    # }
    # var.project_name = "bankapp"
    # Then final tags become:
    # {
    # Environment = "prod"
    # Owner       = "DevOps"
    # Name        = "bankapp-vpc"
    # }
}

# --- Subnets ---

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, { 
    Name                     = "${var.project_name}-public-${count.index + 1}"  #Gives a unique name to each subnet
    "kubernetes.io/role/elb" = "1" #Marks this subnet as public subnet for Load Balancer
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared" #Associates subnet with your EKS cluster.So Kubernetes knows it can use this subnet for resources
  })
}

resource "aws_subnet" "private_app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnets[count.index] #Defines the IP range for this subnet, taken from the list of private app subnets provided as input
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.common_tags, { 
    Name                              = "${var.project_name}-private-app-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared"
    "karpenter.sh/discovery"                        = var.project_name
  })
}

resource "aws_subnet" "private_data" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_data_subnets[count.index] #
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.common_tags, { Name = "${var.project_name}-private-data-${count.index + 1}" })
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.common_tags, { Name = "${var.project_name}-igw" })
}

resource "aws_eip" "nat" {  #Allocates a static public IP address in AWS
  domain = "vpc"    #The Elastic IP is allocated for use inside a VPC (Virtual Private Cloud).
  tags   = merge(var.common_tags, { Name = "${var.project_name}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id #
  tags          = merge(var.common_tags, { Name = "${var.project_name}-nat-gw" })
}

# 1. Public Route Table (Connects to Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-public-rt" })
}

# 2. Private Route Table (Connects to NAT Gateway)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-private-rt" })
}

#Connects subnets to route tables
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private App Subnets -> Private RT
resource "aws_route_table_association" "private_app" {
  count          = 2
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private.id
}

# Private Data Subnets -> Private RT
resource "aws_route_table_association" "private_data" {
  count          = 2
  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private.id
}