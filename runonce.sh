#!/bin/bash -x

# Update password
echo 'ec2-user:OulaPass' | chpasswd

REGION="$(/usr/bin/ec2-metadata -R --quiet)"
INSTANCE_ID="$(/usr/bin/ec2-metadata -i --quiet)"
ENDPOINT="https://ec2.$${REGION}.api.aws" # dualstack endpoint

# attach the ENI
aws ec2 attach-network-interface \
  --region "$${REGION}" \
  --instance-id "$${INSTANCE_ID}" \
  --device-index 1 \
  --endpoint-url "$${ENDPOINT}" \
  --network-interface-id "${eni_id}"

yum install iptables -y

# start SNAT
systemctl enable snat
systemctl start snat
