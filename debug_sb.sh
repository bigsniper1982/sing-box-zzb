#!/bin/bash
# Mock variables
shadowtls="true"
port_shadowtls=8443
shadowtls_password="password123"
shadowtls_domain="www.bing.com"
port_vless_local=10086
uuid="test-uuid"
port_vl_re=2053
port_vm_ws=8080
port_hy2=8443
port_tu=8880
tlsyn="true"
ym_vl_re="example.com"
ym_vm_ws="example.com"
private_key="test-key"
short_id="1234abcd"
certificatec_vmess_ws="/path/to/cert"
certificatep_vmess_ws="/path/to/key"
certificatec_hy2="/path/to/cert"
certificatep_hy2="/path/to/key"
certificatec_tuic="/path/to/cert"
certificatep_tuic="/path/to/key"
ipv="prefer_ipv4"
endip="1.1.1.1"
v6="2001:db8::1"
pvk="test-pvk"
res="[1,2,3]"

# Source the function
source /root/sing-box-yg/sb.sh

# Run the function
inssbjsonser

# Validate
echo "Validating sb10.json..."
jq . /etc/s-box/sb10.json > /dev/null && echo "sb10.json is valid" || echo "sb10.json is INVALID"
echo "Validating sb11.json..."
jq . /etc/s-box/sb11.json > /dev/null && echo "sb11.json is valid" || echo "sb11.json is INVALID"
