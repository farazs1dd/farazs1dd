#!/bin/bash

# Script to detect public IP and update AWS security groups in specified regions
# This script will:
# 1. Detect your current public IP address
# 2. Find security groups attached to EC2 instances in the specified regions
# 3. Update those security groups to allow inbound traffic from your IP

# Usage:
# bash update_aws_sg_with_my_ip.sh [protocol] [port]
# 
# Interactive mode (default):
#   - Will prompt for security group IDs (or use all EC2 security groups)
#   - Will prompt for port options:
#     - Specific ports (22, 443)
#     - All TCP ports (1-65535)
#
# Command-line mode:
#   - Default protocol: tcp
#   - Default port: 22 (SSH)
#
# Examples:
#   bash update_aws_sg_with_my_ip.sh          # Interactive mode
#   bash update_aws_sg_with_my_ip.sh tcp 22   # Command-line mode for SSH
#   bash update_aws_sg_with_my_ip.sh tcp 443  # Command-line mode for HTTPS
#   bash update_aws_sg_with_my_ip.sh tcp all  # Command-line mode for all TCP ports
# Exit on any error
set -e

# Default values
# Check if we're in command-line mode (arguments provided)
COMMAND_LINE_MODE=false
if [[ -n "$1" && -n "$2" ]]; then
COMMAND_LINE_MODE=true
PROTOCOL="$1"

# Handle special "all" keyword for all TCP ports
if [[ "$2" == "all" ]]; then
    PORTS=("1-65535")
else
    PORTS=("$2")
fi
else
PROTOCOL="tcp"  # Default protocol
PORTS=()        # Will be filled through user input
fi

# Default region, can be customized in interactive mode
REGIONS=("eu-west-1" "eu-north-1")
DESCRIPTION="Auto-added by script for $(whoami) on $(date)"
USE_ALL_SG=true   # Default to using all security groups if none specified
SG_IDS=()         # Will be filled through user input if specified
# Function to check if command exists
command_exists() {
command -v "$1" &> /dev/null
}

# Check if required commands are available
# Check if jq is installed (needed for JSON parsing)
if ! command_exists jq; then
    echo "Error: jq is not installed. Please install it first."
    echo "Visit: https://stedolan.github.io/jq/download/"
    exit 1
fi

if ! command_exists aws; then
echo "Error: AWS CLI is not installed. Please install it first."
echo "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
exit 1
fi

if ! command_exists curl; then
echo "Error: curl is not installed. Please install it first."
exit 1
fi

# Check if AWS CLI is configured
aws sts get-caller-identity &> /dev/null || {
echo "Error: AWS CLI is not configured properly. Please run 'aws configure'."
exit 1
}

echo "Detecting your public IP address..."

# Try multiple services to get public IP for reliability
get_public_ip() {
# Try ipify first
IP=$(curl -s https://api.ipify.org)
if [[ -z "$IP" || ! "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Try icanhazip as fallback
    IP=$(curl -s https://icanhazip.com)
    if [[ -z "$IP" || ! "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Try ifconfig.me as second fallback
    IP=$(curl -s https://ifconfig.me)
    if [[ -z "$IP" || ! "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Could not detect your public IP address."
        exit 1
    fi
    fi
fi
echo "$IP"
}
# Function to get user input for security groups
get_security_groups_input() {
local choice
echo -e "\nDo you want to specify security groups or update all EC2 security groups?"
echo "1) Specify security group IDs"
echo "2) Update all EC2 security groups (default)"
read -p "Enter choice [1-2]: " choice

if [[ "$choice" == "1" ]]; then
    USE_ALL_SG=false
    echo "Enter security group IDs (comma-separated):"
    read sg_input

    # Split input by commas and store in SG_IDS array
    IFS=',' read -ra SG_IDS <<< "$sg_input"

    # Trim whitespace from each entry
    for i in "${!SG_IDS[@]}"; do
    SG_IDS[$i]=$(echo "${SG_IDS[$i]}" | xargs)
    done

    echo "Will update these security groups: ${SG_IDS[*]}"
else
    USE_ALL_SG=true
    echo "Will update all security groups attached to running EC2 instances"
fi
}

# Function to get port options from user
get_ports_input() {
    local choice
    echo -e "\nSelect port option:"
    echo "1) Specific ports: 22 (SSH) and 443 (HTTPS)"
    echo "2) All TCP ports (1-65535)"
    echo "3) Custom port(s)"
    read -p "Enter choice [1-3, default: 1]: " choice
    
    case "$choice" in
        2)
            PORTS=("1-65535")
            echo "Will update for all TCP ports (1-65535)"
            ;;
        3)
            local port_input
            echo -e "Enter port numbers (comma-separated):"
            read port_input
            
            if [[ -z "$port_input" ]]; then
                PORTS=(22)
            else
                # Split input by commas and store in PORTS array
                IFS=',' read -ra PORTS <<< "$port_input"
                
                # Validate each port
                for port in "${PORTS[@]}"; do
                    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                        echo "Error: Invalid port number: $port. Must be between 1-65535."
                        return 1
                    fi
                done
            fi
            echo "Will update for ports: ${PORTS[*]}"
            ;;
        *)
            PORTS=(22 443)
            echo "Will update for ports: 22 (SSH) and 443 (HTTPS)"
            ;;
    esac
    
    return 0
}

PUBLIC_IP=$(get_public_ip)
CIDR_IP="${PUBLIC_IP}/32"

echo "Your public IP address is: $PUBLIC_IP"

# If not in command-line mode, get user input
if [[ "$COMMAND_LINE_MODE" == "false" ]]; then
    # Allow user to select region
    echo -e "\nSelect region(s):"
    echo "1) eu-west-1"
    echo "2) eu-north-1"
    echo "3) Both regions (default)"
    read -p "Enter choice [1-3]: " region_choice
    
    case "$region_choice" in
        1) REGIONS=("eu-west-1") ;;
        2) REGIONS=("eu-north-1") ;;
        *) REGIONS=("eu-west-1" "eu-north-1") ;;
    esac
    
    get_security_groups_input
    while ! get_ports_input; do
        echo "Please try again."
    done
else
    echo "Running in command-line mode"
    if [[ "${PORTS[0]}" == "1-65535" ]]; then
        echo "Will update security groups to allow $PROTOCOL all ports from $CIDR_IP"
    else
        echo "Will update security groups to allow $PROTOCOL port ${PORTS[0]} from $CIDR_IP"
    fi
fi

echo "Processing regions: ${REGIONS[*]}"
# Process each region
for REGION in "${REGIONS[@]}"; do
echo -e "\nProcessing region: $REGION"

# Get list of instance security groups
if [[ "$USE_ALL_SG" == "true" ]]; then
    echo "Finding EC2 instances and their security groups..."
    
    # This command gets security group IDs attached to running instances
    SG_IDS=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=instance-state-name,Values=running" \
        --query "Reservations[*].Instances[*].SecurityGroups[*].GroupId" \
        --output text)
    
    if [[ -z "$SG_IDS" ]]; then
        echo "No running EC2 instances found in $REGION"
        continue
    fi
    
    # Remove duplicates
    UNIQUE_SG_IDS=($(echo "$SG_IDS" | tr ' ' '\n' | sort -u))
    
    echo "Found ${#UNIQUE_SG_IDS[@]} unique security groups attached to running instances"
else
    echo "Using specified security groups..."
    UNIQUE_SG_IDS=("${SG_IDS[@]}")
    
    if [[ ${#UNIQUE_SG_IDS[@]} -eq 0 ]]; then
        echo "No security groups specified for $REGION"
        continue
    fi
fi
# Update each security group
for SG_ID in "${UNIQUE_SG_IDS[@]}"; do
    echo "Updating security group: $SG_ID"
    
    # Process each port or port range
    for PORT in "${PORTS[@]}"; do
        # Check if this is a port range (e.g., "1-65535")
        if [[ "$PORT" == *-* ]]; then
            # Extract the port range values
            FROM_PORT=$(echo "$PORT" | cut -d'-' -f1)
            TO_PORT=$(echo "$PORT" | cut -d'-' -f2)
            
            # Check if the rule already exists
            echo "Checking if rule already exists for $CIDR_IP on port range $FROM_PORT-$TO_PORT..."
            SG_RULES=$(aws ec2 describe-security-groups \
                --region "$REGION" \
                --group-ids "$SG_ID" \
                --query "SecurityGroups[0].IpPermissions[*]" \
                --output json)

            # Parse through the rules to find matching ones
            if echo "$SG_RULES" | jq -e --arg proto "$PROTOCOL" --arg from "$FROM_PORT" --arg to "$TO_PORT" --arg cidr "$CIDR_IP" \
                '.[] | select(.IpProtocol==$proto and .FromPort==($from|tonumber) and .ToPort==($to|tonumber) and .IpRanges[].CidrIp==$cidr)' > /dev/null; then
                echo "Rule already exists for $CIDR_IP on port range $PORT in security group $SG_ID"
            else
                # Add the new rule
                echo "Adding rule for $CIDR_IP on port range $PORT ($PROTOCOL) to security group $SG_ID"
                aws ec2 authorize-security-group-ingress \
                    --region "$REGION" \
                    --group-id "$SG_ID" \
                    --ip-permissions "[{\"IpProtocol\": \"$PROTOCOL\", \"FromPort\": $FROM_PORT, \"ToPort\": $TO_PORT, \"IpRanges\": [{\"CidrIp\": \"$CIDR_IP\", \"Description\": \"$DESCRIPTION\"}]}]" || {
                    echo "Warning: Failed to update security group $SG_ID"
                    continue
                }
                echo "Successfully added rule to security group $SG_ID for port range $PORT"
            fi
        else
            # Handle single port (normal case)
            # Check if the rule already exists
            echo "Checking if rule already exists for $CIDR_IP on port $PORT..."
            SG_RULES=$(aws ec2 describe-security-groups \
                --region "$REGION" \
                --group-ids "$SG_ID" \
                --query "SecurityGroups[0].IpPermissions[*]" \
                --output json)

            # Parse through the rules to find matching ones
            if echo "$SG_RULES" | jq -e --arg proto "$PROTOCOL" --arg port "$PORT" --arg cidr "$CIDR_IP" \
                '.[] | select(.IpProtocol==$proto and .FromPort==($port|tonumber) and .ToPort==($port|tonumber) and .IpRanges[].CidrIp==$cidr)' > /dev/null; then
                echo "Rule already exists for $CIDR_IP on port $PORT in security group $SG_ID"
            else
                # Add the new rule
                # Add the new rule
                echo "Adding rule for $CIDR_IP on port $PORT ($PROTOCOL) to security group $SG_ID"
                aws ec2 authorize-security-group-ingress \
                    --region "$REGION" \
                    --group-id "$SG_ID" \
                    --ip-permissions "[{\"IpProtocol\": \"$PROTOCOL\", \"FromPort\": $PORT, \"ToPort\": $PORT, \"IpRanges\": [{\"CidrIp\": \"$CIDR_IP\", \"Description\": \"$DESCRIPTION\"}]}]" || {
                    continue
                }
                echo "Successfully added rule to security group $SG_ID for port $PORT"
            fi
        fi
    done
done
done

echo -e "\nSecurity group update completed successfully!"
echo "Your IP address $CIDR_IP has been added to the specified security groups."
