resource "aws_vpc" "main" { cidr_block = var.vpc_cidr
 enable_dns_support = true
 enable_dns_hostnames = true
 tags = { Name = local.name } }
resource "aws_internet_gateway" "main" { vpc_id = aws_vpc.main.id
 tags = { Name = local.name } }
resource "aws_subnet" "public" { count = 3
 vpc_id = aws_vpc.main.id
 availability_zone = local.azs[count.index]
 cidr_block = cidrsubnet(var.vpc_cidr, 4, count.index)
 map_public_ip_on_launch = false
 tags = { Name = "${local.name}-public-${count.index}", "kubernetes.io/role/elb" = "1" } }
resource "aws_subnet" "private" { count = 3
 vpc_id = aws_vpc.main.id
 availability_zone = local.azs[count.index]
 cidr_block = cidrsubnet(var.vpc_cidr, 4, count.index + 4)
 tags = { Name = "${local.name}-private-${count.index}", "kubernetes.io/role/internal-elb" = "1" } }
resource "aws_eip" "nat" { count = 3
 domain = "vpc"
 depends_on = [aws_internet_gateway.main]
 tags = { Name = "${local.name}-nat-${count.index}" } }
resource "aws_nat_gateway" "main" { count = 3
 allocation_id = aws_eip.nat[count.index].id
 subnet_id = aws_subnet.public[count.index].id
 depends_on = [aws_internet_gateway.main]
 tags = { Name = "${local.name}-${count.index}" } }
resource "aws_route_table" "public" { vpc_id = aws_vpc.main.id
 route { cidr_block = "0.0.0.0/0"
 gateway_id = aws_internet_gateway.main.id }
 tags = { Name = "${local.name}-public" } }
resource "aws_route_table_association" "public" { count = 3
 subnet_id = aws_subnet.public[count.index].id
 route_table_id = aws_route_table.public.id }
resource "aws_route_table" "private" { count = 3
 vpc_id = aws_vpc.main.id
 route { cidr_block = "0.0.0.0/0"
 nat_gateway_id = aws_nat_gateway.main[count.index].id }
 tags = { Name = "${local.name}-private-${count.index}" } }
resource "aws_route_table_association" "private" { count = 3
 subnet_id = aws_subnet.private[count.index].id
 route_table_id = aws_route_table.private[count.index].id }
resource "aws_cloudwatch_log_group" "vpc_flow" { name = "/edgemint/${var.environment}/vpc-flow"
 retention_in_days = 365
 kms_key_id = aws_kms_key.platform.arn }
resource "aws_iam_role" "flow_logs" { name = "${local.name}-flow-logs"
 assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "vpc-flow-logs.amazonaws.com" }, Action = "sts:AssumeRole" }] }) }
resource "aws_iam_role_policy" "flow_logs" { role = aws_iam_role.flow_logs.id
 policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"], Resource = "*" }] }) }
resource "aws_flow_log" "main" { iam_role_arn = aws_iam_role.flow_logs.arn
 log_destination = aws_cloudwatch_log_group.vpc_flow.arn
 traffic_type = "ALL"
 vpc_id = aws_vpc.main.id }
