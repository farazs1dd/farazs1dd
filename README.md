# Update AWS Security Groups with My IP

A bash script that automatically detects your public IP address and updates specified AWS security groups to allow inbound traffic from your location.

## Description

This utility script helps maintain secure AWS environments by:
- Detecting your current public IP address
- Adding a rule to specified AWS security groups that allows traffic only from your IP
- Removing outdated IP address rules you previously added

Perfect for developers who work from different locations but need to maintain secure access to their AWS resources.

## Prerequisites

- Bash shell environment
- AWS CLI installed and configured with appropriate permissions
- `jq` command-line JSON processor
- AWS IAM permissions to describe and modify security groups

## Installation

1. Clone this repository:
```bash
git clone https://github.com/yourusername/update_aws_sg_with_my_ip.git
```

2. Make the script executable:
```bash
cd update_aws_sg_with_my_ip
chmod +x update_aws_sg_with_my_ip.sh
```

3. Ensure the AWS CLI is installed and configured with appropriate credentials.

## Usage

The script can be run in two modes: interactive or command-line.

### Interactive Mode

Simply run the script without arguments:

```bash
./update_aws_sg_with_my_ip.sh
```

The script will:
1. Detect your public IP address
2. Prompt you to select AWS regions to search
3. Find security groups in the selected regions
4. Allow you to select which security groups to update
5. Prompt for the port to allow access to
6. Update the selected security groups with your IP address

### Command-Line Mode

For automation or scripting, use command-line arguments:

```bash
./update_aws_sg_with_my_ip.sh [options]
```

Options:
- `-r, --regions`: Comma-separated list of AWS regions
- `-g, --groups`: Comma-separated list of security group IDs
- `-p, --port`: Port number to allow access to (default: 22)
- `-d, --description`: Description for the security group rule (default: "My IP")
- `-h, --help`: Display help information

## Examples

### Interactive Mode Example
```bash
./update_aws_sg_with_my_ip.sh
```

### Command-Line Mode Examples

Update specific security groups in a single region:
```bash
./update_aws_sg_with_my_ip.sh -r us-east-1 -g sg-12345678,sg-87654321 -p 22
```

Update security groups across multiple regions:
```bash
./update_aws_sg_with_my_ip.sh -r us-east-1,us-west-2 -g sg-12345678,sg-87654321 -p 443 -d "HTTPS access"
```

## License

MIT

