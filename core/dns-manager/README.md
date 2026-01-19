# DNS Manager

自动 DNS 记录管理服务，监听 Docker 容器启动事件并自动在 Cloudflare 创建 A 记录。

## 快速开始

### 运行单元测试

```bash
# 安装依赖
pip install -r requirements.txt

# 运行所有测试
python -m pytest tests/ -v

# 运行特定测试文件
python -m pytest tests/test_utils.py -v

# 查看测试覆盖率
python -m pytest tests/ --cov=. --cov-report=html
```

### 本地开发

```bash
# 设置环境变量
export DOMAIN=example.com
export CF_DNS_API_TOKEN=your-token
export LOG_LEVEL=DEBUG

# 运行服务
python dns_manager.py
```

### Docker 构建

```bash
# 构建镜像
docker build -t dns-manager:latest .

# 运行容器
docker run -d \
  --name dns-manager \
  -e DOMAIN=example.com \
  -e CF_DNS_API_TOKEN=your-token \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  dns-manager:latest
```

## 模块说明

- `dns_manager.py` - 主程序，编排所有组件
- `utils.py` - 工具函数（IPv4 检测、日志配置）
- `cloudflare_client.py` - Cloudflare API 客户端
- `docker_monitor.py` - Docker 事件监听器
- `tests/` - 单元测试

## API 端点

- `GET /health` - 健康检查，返回服务状态和统计信息
- `GET /metrics` - Prometheus 指标
- `POST /sync` - 手动触发全量同步

## 环境变量

| 变量名 | 必需 | 默认值 | 说明 |
|--------|------|--------|------|
| `DOMAIN` | 是 | - | 基础域名 |
| `CF_DNS_API_TOKEN` | 是* | - | Cloudflare API Token |
| `CF_API_EMAIL` | 是* | - | Cloudflare 账号邮箱 |
| `CF_API_KEY` | 是* | - | Cloudflare Global API Key |
| `LOG_LEVEL` | 否 | INFO | 日志级别 |

*需要 `CF_DNS_API_TOKEN` 或 (`CF_API_EMAIL` + `CF_API_KEY`)

## 信号处理

- `SIGUSR1` - 触发全量同步
- `SIGTERM` - 优雅关闭

## 开发指南

### 添加新功能

1. 编写测试 (`tests/test_*.py`)
2. 实现功能
3. 运行测试确保通过
4. 更新文档

### 代码风格

遵循 PEP 8 规范:

```bash
# 检查代码风格
flake8 *.py

# 自动格式化
black *.py
```

### 提交规范

使用语义化提交信息:

- `功能: 添加 XXX 功能`
- `修复: 修复 XXX 问题`
- `文档: 更新 XXX 文档`
- `测试: 添加 XXX 测试`

## 常见问题

**Q: 如何调试 API 调用？**

设置 `LOG_LEVEL=DEBUG` 查看详细日志。

**Q: 如何模拟容器启动事件？**

参考 `tests/test_docker_monitor.py` 中的 mock 示例。

**Q: 如何测试 Cloudflare API？**

使用 `@patch` 装饰器 mock API 调用，避免真实调用。

## 许可证

MIT License
