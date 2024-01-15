#!/bin/bash -x

# Update password
echo 'ec2-user:OulaPass' | chpasswd

REGION="$(/opt/aws/bin/ec2-metadata -z  | sed 's/placement: \(.*\).$/\1/')"
INSTANCE_ID="$(/opt/aws/bin/ec2-metadata -i | cut -d' ' -f2)"
ENDPOINT="https://ec2.$${REGION}.api.aws" # dualstack endpoint

# attach the ENI
aws ec2 attach-network-interface \
  --region "$${REGION}" \
  --instance-id "$${INSTANCE_ID}" \
  --device-index 1 \
  --endpoint-url "$${ENDPOINT}" \
  --network-interface-id "${eni_id}"

# start SNAT
systemctl enable snat
systemctl start snat
