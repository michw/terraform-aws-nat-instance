#!/bin/bash -x

# Update password
echo 'ec2-user:OulaPass' | chpasswd

sleep 30 # dont hurry

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

# extract tags from running instance
ENV="$(ec2-metadata -g --quiet  | grep -E '^\s*Environment:'   | sed 's/.*: //' | xargs)"
PROJ="$(ec2-metadata -g --quiet | grep -E '^\s*Project:'       | sed 's/.*: //' | xargs)"
APP_NAME="$(ec2-metadata -g --quiet | grep -E '^\s*OulahealthAppName:'       | sed 's/.*: //' | xargs)"


# Allocate Elastic IP with the extracted tags
ALLOCATION_ID="$(aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Project,Value=$${PROJ}},{Key=Environment,Value=$${ENV}},{Key=OulahealthAppName,Value=$${APP_NAME}},{Key=Name,Value=$${PROJ}-$${APP_NAME}-$${ENV}-$${REGION}},{Key=$${PROJ}-stop-outside-of-business-hours-$${ENV}-$${REGION},Value=true},{Key=$${PROJ}-stop-when-unused-$${ENV}-$${REGION},Value=true},{Key=$${PROJ}-manual-stop-$${ENV}-$${REGION},Value=true},{Key=Terragrunt,Value=false}]" \
  --endpoint-url "$${ENDPOINT}" \
  --query 'AllocationId' \
  --output text)"

sleep 3

# associate it
ASSOCIATION_ID="$(aws ec2 associate-address \
  --allocation-id $${ALLOCATION_ID} \
  --network-interface-id "${eni_id}" \
  --endpoint-url "$${ENDPOINT}" \
  --query 'AssociationId' \
  --output text)"

# prep script to run on instance termination
tee /opt/nat/ec2-termination <<EOF
#!/bin/bash -x
sysctl -w net.ipv6.conf.all.disable_ipv6=0
sysctl -w net.ipv6.conf.default.disable_ipv6=0
sysctl -w net.ipv6.conf.lo.disable_ipv6=0
rm -vf /etc/systemd/network/20-ens5.network
sleep 2
networkctl reload
networkctl reconfigure ens5
sleep 5
curl -6 -v https://ec2.us-east-1.api.aws
aws ec2 disassociate-address --association-id "$${ASSOCIATION_ID}" --endpoint-url "$${ENDPOINT}" || aws ec2 disassociate-address --association-id "$${ASSOCIATION_ID}" --endpoint-url "$${ENDPOINT}"
sleep 5
aws ec2 release-address --allocation-id "$${ALLOCATION_ID}" --endpoint-url "$${ENDPOINT}" || aws ec2 release-address --allocation-id "$${ALLOCATION_ID}" --endpoint-url "$${ENDPOINT}"
EOF

chmod +x /opt/nat/ec2-termination


tee /etc/systemd/system/myshutdown.service <<EOF
[Unit]
Description=Run custom script on shutdown
After=network-online.target syslog.service
Requires=network-online.target
Before=shutdown.target reboot.target halt.target
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStop=/opt/nat/ec2-termination
TimeoutStopSec=50

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable myshutdown.service
systemctl start myshutdown.service


dnf --quiet --assumeyes install nftables

#yum install iptables -y

# start SNAT
systemctl enable snat
systemctl start snat
