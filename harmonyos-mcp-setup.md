# 鸿蒙 MCP 配置指南

## 1. MCP 配置文件已创建

`.mcp.json` 内容：
```json
{
  "mcpServers": {
    "harmonyos": {
      "command": "npx",
      "args": ["-y", "harmonyos-mcp@latest"],
      "env": {
        "NODE_PATH": "/opt/homebrew/lib/node_modules"
      }
    }
  }
}
```

## 2. 使用方法

### 方式一：在 Codex 中使用
重启 Codex，MCP 服务器会自动加载。然后可以调用：
```
list_mcp_resources
read_mcp_resource
```

### 方式二：手动测试
```bash
npx -y harmonyos-mcp@latest
```

## 3. 可能需要的配置

如果需要连接真机或模拟器，可能需要配置：

### 环境变量
```bash
export HARMONYOS_SDK_PATH=/path/to/sdk
export HARMONYOS_DEVICE_ID=device-id
```

### HDC 配置
确保 hdc 工具可用：
```bash
hdc list targets
```

## 4. 验证安装

运行以下命令验证：
```bash
npx -y harmonyos-mcp@latest --help
```

## 5. 常见问题

### 问题 1：npx 找不到包
- 检查 npm 源：`npm config get registry`
- 尝试切换源：`npm config set registry https://registry.npmmirror.com`

### 问题 2：连接设备失败
- 确保设备已连接：`hdc list targets`
- 检查 USB 调试是否开启

### 问题 3：权限问题
- 确保 Developer Mode 已开启
- 信任调试设备

## 6. 下一步

重启 Codex 后，我可以帮你：
1. 列出可用资源
2. 读取设备信息
3. 调试应用
4. 查看日志
