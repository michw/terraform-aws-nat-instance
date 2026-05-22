#!/bin/bash
set -x


#nic_name="$(ip route show | grep default | sed -n 's/.*dev \([^\ ]*\).*/\1/p')"
#echo "Found interface name ${nic_name}"
#
#echo "Determining the MAC address on ${nic_name}"
#nic_mac="$(cat /sys/class/net/${nic_name}/address)"
#echo "Found MAC ${nic_mac} for ${nic_name}."
#
#nic_name=



# wait for eth1
while ! ip link show dev ens6; do
  sleep 1
done

nic_mac="$(cat /sys/class/net/ens6/address)"

echo "Requesting IMDSv2 token"
TOKEN=$(curl --silent --fail -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 900")
readarray -t vpc_cidrs <<< $(curl --silent --fail -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/${nic_mac}/vpc-ipv4-cidr-blocks)
if [ ${#vpc_cidrs[*]} -lt 1 ]; then
   panic "Unable to obtain VPC CIDR range from metadata."
else
   echo "Retrieved VPC CIDR range(s) ${vpc_cidrs[@]} from metadata."
fi



# switch the default route to eth1
ip route del default dev ens5

tee /etc/systemd/network/20-ens5.network <<EOF
[Match]
Name=ens5

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
UseGateway=false        # Prevents default route
UseRoutes=false       # Optional: also block other routes from DHCP

[IPv6AcceptRA]
UseGateway=false
EOF

systemctl restart systemd-networkd

sleep 3





# enable IP forwarding and NAT
sysctl -w "net.ipv4.ip_forward"=1 "net.ipv4.conf.ens6.send_redirects"=0 "net.ipv4.ip_local_port_range"="1024 65535"

nft add table ip nat
nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }

for cidr in "${vpc_cidrs[@]}";
do
   nft add rule ip nat postrouting ip saddr "$cidr" oif ens6 masquerade
   if [ $? -ne 0 ]; then
      panic "Unable to add nft rule for cidr $cidr. nft exited with status $?"
   fi
done

sysctl "net.ipv4.ip_forward" "net.ipv4.conf.ens6.send_redirects" "net.ipv4.ip_local_port_range"
nft list ruleset

echo "NAT configuration complete"

###iptables -t nat -A POSTROUTING -o ens6 -j MASQUERADE
###
#### prevent setting the default route to eth0 after reboot
###rm -f /etc/sysconfig/network-scripts/ifcfg-eth0
###


###
# wait for network connection
sleep 3
curl -4 -v --retry 10 http://www.example.com


#### disable ipv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
###

# reestablish connections
dnf --quiet --assumeyes install amazon-ssm-agent
systemctl enable --now amazon-ssm-agent
