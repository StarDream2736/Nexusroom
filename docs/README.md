# NexusRoom 文档中心

`docs/` 是 NexusRoom 3.0.0 公开技术文档的统一维护位置。实现、协议、数据模型、配置和开发标准以 [NexusRoom 技术规范与开发标准](NexusRoom.md) 为基线。

## 核心规范

- [NexusRoom 技术规范与开发标准](NexusRoom.md)：系统架构、数据模型、API、WebSocket、媒体、VLAN、UI、安全、开发和发布标准。

## 开发与部署指南

- [Electron 客户端开发指南](guides/client.md)
- [服务端开发指南](guides/server.md)
- [安装与部署指南](guides/deployment.md)

## 构建文档

- [Electron 客户端编译与 Windows x64 打包](build/client-build.md)
- [服务端编译、Docker 构建与打包](build/server-build.md)

## 开源治理

- [项目说明](../README.md)
- [贡献指南](../CONTRIBUTING.md)
- [行为准则](../CODE_OF_CONDUCT.md)
- [安全策略](../SECURITY.md)
- [版本历史](../CHANGELOG.md)
- [MIT License](../LICENSE)

## 维护规则

- 组件目录 README 只作为源码入口，不重复维护长篇技术内容。
- 修改路由、配置、端口、数据库、WebSocket、媒体行为或 UI 约定时，应同步更新核心规范。
- 发布前应检查文档链接、版本号和示例配置是否与源码一致。
