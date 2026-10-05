# 双方记事本

以双方日常记录作为交流媒介的 AI 陪伴记事本。

核心平台：Android / iOS。客户端：Flutter / Dart。架构：前后端分离。

## 当前状态

已实现独立后端：账户、角色、个人日记、逐篇分享/撤回、关联对话、来源记忆、持久化生成任务与请求回执。
默认模型接口关闭；未配置服务商时任务明确失败，不会返回假生成内容。Flutter 客户端尚未实现。
权限与生成规则已用真实 PostgreSQL 测试，最新结果见阶段记录。
已创建独立私有仓库：https://github.com/cn7shi/shared-notebook。阶段推送以远端提交验证为准。

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
- [功能与完成边界](docs/features.md)
- [分享和生成决策](docs/decisions/002-consent-and-generation-boundaries.md)
- [API 接入说明](contracts/README.md)

每个阶段同时提交代码、决策和真实验证结果，然后推送本产品仓库。

## 本地启动

需要 Node.js 24.15+，首次安装会获取开发用 PostgreSQL 二进制。三个产品的数据库、端口和账户独立。

```powershell
cd server
npm ci
npm run dev
```

接口文档：<http://127.0.0.1:3300/api/docs>，健康检查：<http://127.0.0.1:3300/health>。
开发服务仅监听本机，PostgreSQL 使用 54393 端口；数据与本地数据库口令存于忽略的 `server/.local/`。
使用 Ctrl+C 正常停止服务与数据库。当前并未部署到公网。

```powershell
npm test          # 临时真实 PostgreSQL + HTTP；自动清理此次合成数据
npm run contract # 更新已提交的 OpenAPI；无须启动数据库
```

生产环境使用独立 PostgreSQL，按 `server/.env.example` 配置，执行 `npm run build`、`npm run migrate`、`npm start`。
API 前需要 HTTPS。当前未实现生产备份、账户删除/密码找回/邮箱验证、多实例共享限流、费用额度管理和商店发布。
模型服务商尚待选择；未来在服务端装配 ModelProvider，不能让手机直接持有模型密钥。
