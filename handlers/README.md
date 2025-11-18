# Handlers 目录

## 📋 概述

handlers 目录模拟 Ansible 的 handlers 机制，用于定义可重用的任务处理程序。这些处理程序可以被脚本触发，实现模块化的任务执行。

## 🎯 设计原则

### 1. 幂等性
所有 handlers 必须是幂等的，可以安全地重复执行。

### 2. 模块化
每个 handler 专注于单一职责，便于测试和维护。

### 3. 可触发
handlers 可以被脚本中的特定事件触发执行。

### 4. 错误处理
每个 handler 包含完善的错误处理机制。

## 📁 文件结构

```
handlers/
├── README.md                 # 本文档
├── handler_common.sh         # 通用 handler 函数
├── podman_restart.handler    # Podman 重启处理程序
├── sysctl_reload.handler     # 系统参数重载处理程序
├── service_restart.handler   # 服务重启处理程序
└── container_cleanup.handler # 容器清理处理程序
```

## 🔧 使用方法

### 在脚本中触发 handler
```bash
# 加载 handlers
source ./banb/handlers/handler_common.sh

# 触发 handler
handler_trigger "podman_restart"
```

### 直接执行 handler
```bash
# 直接执行特定 handler
./banb/handlers/podman_restart.handler
```

## 📝 Handler 开发规范

每个 handler 文件应该：
- 使用 `.handler` 扩展名
- 包含完整的错误处理
- 支持 dry-run 模式
- 提供帮助文档
- 返回适当的退出代码
