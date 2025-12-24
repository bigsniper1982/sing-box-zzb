#!/bin/bash

# ShadowTLS 配置测试和验证脚本
# 用于检查 sing-box shadowtls 配置是否正确

export LANG=en_US.UTF-8
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
plain='\033[0m'

red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}

echo "=================================================="
blue "ShadowTLS 配置检查工具"
echo "=================================================="

# 检查 sing-box 是否安装
if [[ ! -f /etc/s-box/sing-box ]]; then
    red "错误：未找到 sing-box，请先运行安装脚本"
    exit 1
fi

# 检查配置文件
if [[ ! -f /etc/s-box/sb.json ]]; then
    red "错误：未找到配置文件 /etc/s-box/sb.json"
    exit 1
fi

echo
green "1. 检查 sing-box 配置语法..."
if /etc/s-box/sing-box check -c /etc/s-box/sb.json 2>&1 | grep -q "configuration ok"; then
    green "   ✓ 配置文件语法正确"
else
    red "   ✗ 配置文件语法错误："
    /etc/s-box/sing-box check -c /etc/s-box/sb.json
    exit 1
fi

echo
green "2. 检查 ShadowTLS 配置..."

# 提取 shadowtls 配置
shadowtls_config=$(jq '.inbounds[] | select(.type=="shadowtls")' /etc/s-box/sb.json 2>/dev/null)

if [[ -z "$shadowtls_config" || "$shadowtls_config" == "null" ]]; then
    yellow "   ⚠ 未启用 ShadowTLS 协议"
    exit 0
fi

green "   ✓ 已启用 ShadowTLS"

# 提取配置参数
shadowtls_port=$(echo "$shadowtls_config" | jq -r '.listen_port')
shadowtls_version=$(echo "$shadowtls_config" | jq -r '.version')
shadowtls_detour=$(echo "$shadowtls_config" | jq -r '.detour')
shadowtls_password=$(echo "$shadowtls_config" | jq -r '.users[0].password')
handshake_server=$(echo "$shadowtls_config" | jq -r '.handshake.server')
handshake_port=$(echo "$shadowtls_config" | jq -r '.handshake.server_port')

echo
blue "   配置信息："
echo "   - 监听端口: $shadowtls_port"
echo "   - 协议版本: v$shadowtls_version"
echo "   - Detour 目标: $shadowtls_detour"
echo "   - 密码: ${shadowtls_password:0:8}..."
echo "   - 握手服务器: $handshake_server:$handshake_port"

echo
green "3. 检查 detour 目标配置..."

vless_shadowtls=$(jq ".inbounds[] | select(.tag==\"$shadowtls_detour\")" /etc/s-box/sb.json 2>/dev/null)

if [[ -z "$vless_shadowtls" || "$vless_shadowtls" == "null" ]]; then
    red "   ✗ 未找到 detour 目标: $shadowtls_detour"
    exit 1
fi

vless_type=$(echo "$vless_shadowtls" | jq -r '.type')
vless_listen=$(echo "$vless_shadowtls" | jq -r '.listen')
vless_port=$(echo "$vless_shadowtls" | jq -r '.listen_port')

if [[ "$vless_type" == "vless" && "$vless_listen" == "127.0.0.1" ]]; then
    green "   ✓ Detour 目标配置正确"
    echo "   - 类型: $vless_type"
    echo "   - 监听: $vless_listen:$vless_port"
else
    yellow "   ⚠ Detour 目标配置可能有问题"
    echo "   - 类型: $vless_type (应为 vless)"
    echo "   - 监听: $vless_listen (应为 127.0.0.1)"
fi

echo
green "4. 检查端口占用..."

if command -v ss &> /dev/null; then
    if ss -tulnp | grep -q ":$shadowtls_port "; then
        green "   ✓ ShadowTLS 端口 $shadowtls_port 正在监听"
        ss -tulnp | grep ":$shadowtls_port " | head -1
    else
        yellow "   ⚠ ShadowTLS 端口 $shadowtls_port 未监听（服务可能未启动）"
    fi
else
    yellow "   ⚠ 无法检查端口（ss 命令不可用）"
fi

echo
green "5. 测试握手服务器连通性..."

# 测试 ping
if ping -c 2 -W 2 "$handshake_server" &>/dev/null; then
    green "   ✓ 握手服务器可以 ping 通"
else
    yellow "   ⚠ 握手服务器无法 ping 通（可能是正常的，如果服务器禁 ping）"
fi

# 测试 HTTPS 连接
echo "   测试 HTTPS 连接..."
if timeout 5 curl -Is "https://$handshake_server:$handshake_port" &>/dev/null; then
    green "   ✓ HTTPS 连接成功"
else
    red "   ✗ HTTPS 连接失败"
    yellow "   建议更换握手服务器域名"
fi

# 测试 TLS 1.3 支持
echo "   测试 TLS 1.3 支持..."
tls13_test=$(timeout 5 curl -I --tlsv1.3 --tls-max 1.3 -s "https://$handshake_server:$handshake_port" 2>&1)
if echo "$tls13_test" | grep -q "HTTP"; then
    green "   ✓ 支持 TLS 1.3（推荐）"
    # 显示延迟
    latency=$(timeout 5 curl -w "%{time_total}" -o /dev/null -s --tlsv1.3 --tls-max 1.3 "https://$handshake_server:$handshake_port" 2>/dev/null)
    if [[ -n "$latency" ]]; then
        echo "   - 连接延迟: ${latency}s"
        if (( $(echo "$latency < 0.5" | bc -l) )); then
            green "     (延迟良好)"
        elif (( $(echo "$latency < 1.0" | bc -l) )); then
            yellow "     (延迟一般)"
        else
            red "     (延迟较高，建议更换域名)"
        fi
    fi
else
    yellow "   ⚠ 不支持 TLS 1.3 或连接失败"
fi

echo
green "6. 检查防火墙规则..."

if command -v iptables &> /dev/null; then
    if iptables -L INPUT -n 2>/dev/null | grep -q "ACCEPT.*dpt:$shadowtls_port"; then
        green "   ✓ 防火墙已开放端口 $shadowtls_port"
    elif iptables -L INPUT -n 2>/dev/null | grep -q "ACCEPT.*all"; then
        green "   ✓ 防火墙策略为 ACCEPT ALL"
    else
        yellow "   ⚠ 未找到明确的防火墙规则，请确认端口已开放"
    fi
else
    yellow "   ⚠ 无法检查防火墙（iptables 不可用）"
fi

echo
green "7. sing-box 服务状态..."

if command -v systemctl &> /dev/null; then
    if systemctl is-active sing-box &>/dev/null; then
        green "   ✓ sing-box 服务运行中"
    else
        red "   ✗ sing-box 服务未运行"
        echo "   启动命令: systemctl start sing-box"
    fi
elif command -v rc-service &> /dev/null; then
    if rc-service sing-box status | grep -q "started"; then
        green "   ✓ sing-box 服务运行中"
    else
        red "   ✗ sing-box 服务未运行"
        echo "   启动命令: rc-service sing-box start"
    fi
fi

echo
echo "=================================================="
green "检查完成！"
echo "=================================================="
echo

# 显示客户端配置示例
if [[ -f /etc/s-box/shadowtls_config.json ]]; then
    echo
    blue "客户端配置示例（已保存到 /etc/s-box/shadowtls_config.json）："
    echo
    cat /etc/s-box/shadowtls_config.json
fi

echo
blue "推荐的握手服务器域名："
echo "  - captive.apple.com (苹果，默认)"
echo "  - www.microsoft.com (微软)"
echo "  - www.icloud.com (iCloud)"
echo "  - gateway.icloud.com (iCloud Gateway)"
echo
blue "测试其他域名延迟："
echo "  curl -w \"%{time_total}\n\" -o /dev/null -s --tlsv1.3 --tls-max 1.3 https://域名"
echo
