# 架构约束：移动端优先、前后端分离

日期：2026-10-05（Asia/Hong_Kong）

## 已确认的用户要求

- Android 和 iOS 是核心平台；Web 仅作为辅助入口。
- 三款产品使用三个独立 GitHub 仓库，分别分阶段推送。
- 页面、交互和操作流程可能大改；数据操作与核心业务规则必须独立于页面。
- 记录重要决策的理由、替代方案、代价和验证方式。

## 分层与依赖

Flutter 页面 → 页面状态 / ViewModel → Repository 接口 → HTTP 客户端
→ 服务端 Controller → 应用用例 / 业务规则 → 数据访问接口 → PostgreSQL

页面只处理展示、输入、导航和动画。页面不得直接访问数据库、直接调用模型服务，
也不得决定资源归属、历史版本修改规则或分享权限。客户端可做即时输入校验，
服务端必须独立完成相同约束及权限校验。

服务端按业务模块组织。Controller 负责 HTTP 边界，用例负责业务，
数据库和 AI 供应商由适配器接入。三款产品各自运行和部署，
每个仓库包含 mobile/、server/、contracts/ 和 docs/；目录同仓不等于运行时耦合。

客户端的页面状态、API 数据对象、服务端数据库模型分别定义。
例如修改卡片颜色、布局或编辑流程不应改变笔记接口；
新增真正的业务能力可以扩展接口，不承诺后端永远不变。

## 技术选型

- 客户端：Flutter + Dart，优先验证中文输入、手机键盘、应用生命周期及触控。
- 服务端提案：NestJS + TypeScript，独立 HTTP 服务。
- 服务端数据库提案：PostgreSQL；使用迁移管理结构，以事务和约束保证一致性。
- 接口：REST + OpenAPI，明确字段、错误、权限和版本兼容规则。
- Dart API 客户端可从 OpenAPI 生成，页面只依赖上层 Repository。
- AI 调用、密钥、上下文筛选、任务状态和供应商适配全部在服务端。
- 客户端本地数据用于草稿与缓存；云端已保存记录以服务端为准。
  完整离线同步不是本阶段已完成的能力，实施时另写冲突与删除同步决策。

## 接口稳定性

1. 使用 /api/v1；兼容性增加优先，破坏性变更必须提供迁移方案和过渡期。
2. 不直接将 ORM / 数据库行序列化为公开接口。
3. 用户身份从已验证的认证信息得到，不能信任客户端提交的 ownerId。
4. 每次读写都校验资源归属，关联实体也需属于同一授权范围。
5. 更新携带预期 revision；冲突返回明确错误，不静默覆盖另一端修改。
6. 创建、归零、AI 生成等可能重试的操作设计幂等键及请求内容校验。
7. 时间用 UTC 存储，客户端按当地时区展示；标识符不携带用户隐私。
8. 列表使用稳定排序和游标分页；错误包含稳定 code、message、requestId。
9. AI 长任务返回任务标识，结果可查询；关闭页面后任务状态仍可恢复。
10. 自动化测试验证接口约定和业务约束，不绑定页面布局。

## 实施与验证顺序

需求与约束 → 数据模型 → OpenAPI → 服务端业务与测试 → Flutter 接入 → 真机验证。

每个里程碑同时提交源代码、决策、验证结果，并推送对应产品仓库。
未执行的测试明确标为未验证。数据迁移验证升级路径，兼容旧客户端。

当前仅完成设计文档，没有运行中的应用、API、数据库迁移或生成客户端。

## 环境现状

当前开发机是 Windows，存在 Android SDK，Flutter 尚未在命令路径和已检查位置发现。
iOS 构建依赖 macOS / Xcode；后续可以配置 macOS 构建环境，
但编译成功不能替代 iOS 真机输入和生命周期验证。

## 参考

- Flutter 架构：https://docs.flutter.dev/app-architecture/guide
- Flutter iOS 构建：https://docs.flutter.dev/deployment/ios
- NestJS OpenAPI：https://docs.nestjs.com/openapi/introduction
- PostgreSQL 约束：https://www.postgresql.org/docs/current/ddl-constraints.html
- Dart 客户端生成：https://openapi-generator.tech/docs/generators/dart-dio/
