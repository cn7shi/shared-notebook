# 双方记事本

以双方日常记录作为交流媒介的 AI 陪伴记事本。

核心平台：Android / iOS。客户端：Flutter / Dart。架构：前后端分离。

## 当前状态

已完成需求与架构文档。尚未生成客户端工程或实现服务端，不能运行。
GitHub 远端尚未创建；本地文档不代表已推送。

## 目录规划

- mobile/：Flutter 客户端，独立构建。
- server/：独立业务 API、持久化及 AI 适配。
- contracts/：OpenAPI、接口示例及兼容性检查。
- docs/：需求、架构、决策和阶段验证记录。

## 文档

- [需求与验收](docs/requirements.md)
- [架构边界](docs/architecture.md)
- [选型决策](docs/decisions/001-mobile-separated-backend.md)
- [阶段记录](docs/milestones.md)

每个阶段同时提交代码、决策和真实验证结果，然后推送本产品仓库。
