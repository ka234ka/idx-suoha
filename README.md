# 🚀 IDX 一键部署脚本

这是一个可在 **Google IDX** / VPS 环境一键部署的自动化脚本，支持：
- 固定端口 **2546**
- systemd / 非 systemd 环境自适应启动
- Cloudflare Tunnel 自动重连（可选）
- 幂等执行（可重复运行，不破坏现有配置）
- 部署日志 & 状态保存

---

## 📌 一键部署

在终端执行以下命令即可：
```bash
curl -fsSL https://raw.githubusercontent.com/ka234ka/idx-suoha/main/deploy.sh -o deploy.sh \
  && chmod +x deploy.sh && ./deploy.sh

echo '你的_CF_TOKEN' > ~/.cf_token
