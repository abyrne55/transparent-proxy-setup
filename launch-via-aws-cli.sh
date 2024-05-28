#!/bin/bash

KEY_NAME="mySSHkeypair"
SEC_GROUP_ID=sg-08da4d3550d024b10
AWS_REGION=us-east-2

# This will get the latest RHEL AMI in the given region
AMI_ID=$(aws ec2 describe-images --owners 309956199498 --filters "Name=platform-details,Values='Red Hat Enterprise Linux'" "Name=architecture,Values=x86_64" "Name=root-device-type,Values=ebs" "Name=manifest-location,Values=amazon/RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP2" --region=$AWS_REGION --output json --query 'sort_by(Images, &CreationDate)[-1].ImageId')

TMP_FILE=$(mktemp)
aws ec2 run-instances --image-id=$AMI_ID --instance-type=t3.micro --key-name=$KEY_NAME --security-group-ids=$SEC_GROUP_ID --associate-public-ip-address --user-data=file://userdata.yaml --tag-specifications="ResourceType=instance,Tags=[{Key=Name,Value=mitmproxy}]" --region=$AWS_REGION --no-paginate | tee $TMP_FILE
sleep 2
INSTANCE_ID=$(jq -r .Instances[0].InstanceId ${TMP_FILE})
INSTANCE_IP=$(aws ec2 describe-instances --instance-ids=$INSTANCE_ID --query='Reservations[*].Instances[*].PublicIpAddress' --output=text --region=${AWS_REGION})
ENI_ID=$(jq -r .Instances[0].NetworkInterfaces[0].NetworkInterfaceId ${TMP_FILE})
aws ec2 modify-network-interface-attribute --no-source-dest-check --network-interface-id=$ENI_ID --region=$AWS_REGION
sleep 10

echo "Run 'ssh ec2-user@${INSTANCE_IP}' to log-in, then run 'tmux attach -t mitmproxy' to view traffic flowing through proxy"
echo "Run 'aws ec2 terminate-instances --instance-ids=$INSTANCE_ID --region=$AWS_REGION' to terminate"
