# ShadowTLS 配置修复说明

## 问题诊断

根据 [ShadowTLS 官方 Wiki](https://github.com/ihciah/shadow-tls/wiki) 和 sing-box 文档，原脚本中的 shadowtls 配置存在以下问题：

### 1. 客户端配置错误

**原问题：**
```json
{
  "tag": "vless-shadowtls-$hostname",
  "type": "vless",
  "server": "127.0.0.1",
  "server_port": 1080,  // ❌ 错误：连接到不存在的本地端口
  "uuid": "$uuid",
  "flow": "",
  "detour": "shadowtls-$hostname"
}
```

**问题说明：**
- 客户端 VLESS outbound 配置了 `server_port: 1080`，但没有任何服务监听这个端口
- 使用 `detour` 时，`server` 和 `server_port` 应该设置为虚拟值（通常是 127.0.0.1:0）
- 缺少必要的传输层配置

**修复后：**
```json
{
  "tag": "vless-shadowtls-$hostname",
  "type": "vless",
  "server": "127.0.0.1",
  "server_port": 0,  // ✅ 正确：使用虚拟端口，实际流量通过 detour
  "uuid": "$uuid",
  "flow": "",
  "packet_encoding": "xudp",  // ✅ 添加：UDP 数据包编码
  "transport": {
    "type": "tcp"  // ✅ 添加：明确传输类型
  },
  "detour": "shadowtls-$hostname"
}
```

### 2. 服务器 IP 引用问题

**原问题：**
```json
"server": "$server_ip"  // 可能使用了带方括号的 IPv6 格式
```

**修复后：**
```json
"server": "$cl_hy2_ip"  // ✅ 使用不带方括号的 IP 地址
```

### 3. 分享信息不规范

**原问题：**
- 生成了不标准的 vless:// 链接格式
- shadowtls 参数编码方式不被广泛支持

**修复后：**
- 改为显示详细的配置参数
- 提供完整的 sing-box 客户端配置 JSON 示例
- 便于用户手动配置或导入

## 修复内容

### 1. 客户端 Outbound 配置修复

文件：`sb.sh` (行 1620-1650)

**关键修改：**
1. `server_port` 改为 `0`（虚拟端口）
2. 添加 `packet_encoding: "xudp"` 支持 UDP
3. 添加 `transport` 配置，明确使用 TCP
4. 修正 `server` 地址引用为 `$cl_hy2_ip`

### 2. 节点信息显示优化

文件：`sb.sh` (行 1285-1310)

**修改内容：**
1. 移除不规范的分享链接生成
2. 改为显示详细配置参数：
   - 服务器地址
   - 端口
   - UUID
   - ShadowTLS 密码
   - TLS 握手域名
   - 版本和指纹信息
3. 生成完整的 sing-box 客户端配置示例

## 服务端配置说明（无需修改）

当前服务端配置是正确的：

```json
{
  "type": "shadowtls",
  "tag": "shadowtls-in",
  "listen": "::",
  "listen_port": ${port_shadowtls},
  "detour": "vless-shadowtls-in",  // ✅ 正确：解密后转发到内部 vless
  "version": 3,
  "users": [
    {
      "password": "${shadowtls_password}"
    }
  ],
  "handshake": {
    "server": "${shadowtls_domain}",  // TLS 握手目标域名
    "server_port": 443
  }
}
```

## 工作原理

### ShadowTLS v3 流程：

**服务端：**
1. ShadowTLS inbound 监听外部端口
2. 接收客户端的 TLS 伪装流量
3. 通过 `detour` 将解密后的流量转发到内部 VLESS 服务（监听 127.0.0.1）
4. 如果握手失败，转发到真实的 `handshake.server`（如 captive.apple.com）

**客户端：**
1. VLESS outbound 配置 `detour` 指向 ShadowTLS outbound
2. ShadowTLS outbound 连接到服务器
3. 将 VLESS 流量包装在 TLS 伪装中
4. 与 `handshake.server` 进行真实 TLS 握手来伪装流量

## 使用建议

### 1. 握手域名选择

根据 [官方建议](https://github.com/ihciah/shadow-tls/wiki/How-to-Run#how-to-choose-tls-handshake-server)：

- ✅ **低延迟**：从 VPS 测试 ping 和 curl 延迟
- ✅ **可信任**：选择合法、广泛使用的服务
- ✅ **支持 TLS 1.3**：可以减少延迟

推荐域名：
```bash
# 测试延迟
curl -I --tlsv1.3 --tls-max 1.3 -w "%{time_total}\n" -o /dev/null -s https://captive.apple.com
curl -I --tlsv1.3 --tls-max 1.3 -w "%{time_total}\n" -o /dev/null -s https://www.microsoft.com
curl -I --tlsv1.3 --tls-max 1.3 -w "%{time_total}\n" -o /dev/null -s https://www.icloud.com
```

常用选择：
- `captive.apple.com` (默认)
- `www.microsoft.com`
- `www.icloud.com`
- `gateway.icloud.com`

### 2. 客户端支持

支持 ShadowTLS v3 的客户端：
- ✅ **sing-box**：完整支持，推荐
- ✅ **NekoBox**：支持 v3
- ✅ **v2rayN**（切换 sing-box 内核）
- ❌ **Clash Meta**：不支持 shadowtls

### 3. 性能优化

如果使用 Docker 部署，可以在 `docker-compose.yml` 中添加：

```yaml
security_opt:
  - seccomp:unconfined  # 禁用 seccomp 提高性能
```

环境变量优化：
```bash
export RUST_LOG=error  # 降低日志级别
```

## 验证配置

### 服务端检查

```bash
# 检查 sing-box 配置语法
/etc/s-box/sing-box check -c /etc/s-box/sb.json

# 查看 shadowtls 配置
jq '.inbounds[] | select(.type=="shadowtls")' /etc/s-box/sb.json

# 检查端口监听
ss -tulnp | grep sing-box
```

### 客户端测试

1. 使用 sing-box 客户端导入生成的配置
2. 启动客户端，查看日志
3. 测试连接：
   ```bash
   curl -x socks5://127.0.0.1:1080 https://www.google.com
   ```

## 常见问题排查

### 1. 连接超时

**可能原因：**
- 防火墙未开放端口
- 握手域名延迟过高
- 版本不匹配（确保服务端和客户端都使用 v3）

**解决方法：**
```bash
# 检查防火墙
iptables -L -n | grep <shadowtls_port>

# 测试握手域名
curl -I --tlsv1.3 --tls-max 1.3 -vvv https://<handshake_domain>
```

### 2. TLS 握手失败

**可能原因：**
- 握手域名不可达
- TLS 指纹不匹配

**解决方法：**
- 更换握手域名
- 确认客户端指纹设置为 `chrome`

### 3. UDP 不工作

**确认配置：**
- 客户端添加了 `packet_encoding: "xudp"`
- VLESS 服务端支持 UDP

## 参考资料

- [ShadowTLS 官方 Wiki](https://github.com/ihciah/shadow-tls/wiki)
- [ShadowTLS 使用指南](https://github.com/ihciah/shadow-tls/wiki/How-to-Run)
- [sing-box ShadowTLS 文档](https://sing-box.sagernet.org/configuration/inbound/shadowtls/)
- [sing-box ShadowTLS Outbound](https://sing-box.sagernet.org/configuration/outbound/shadowtls/)

## 修改历史

- 2024-12-24: 修复客户端 detour 配置和节点信息显示
