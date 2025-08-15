# suoha（固定端口 2546 + 持久化 + 健康检查 + systemd）

- 固定端口：2546（与 Cloudflare Zero Trust 的 Service: http://localhost:2546 对齐）
- 持久化：/opt/suoha/port.txt 与 /opt/suoha/env
- 健康检查：每分钟检查一次，异常自动重启
- 自启动：systemd 管理

## 快速安装
```bash
sudo bash install.sh
