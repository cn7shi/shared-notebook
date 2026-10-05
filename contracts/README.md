# 双方记事本 API v1

契约：`openapi.json`，运行后在 `/api/docs` 查看。成功返回 `{ data: ... }`，列表为 `{ data: { items, nextCursor } }`。
错误为 `{ error: { code, message, requestId } }`。除注册/登录外的业务接口要求 Bearer 会话令牌。
资源归属由会话推导，不接受客户端 ownerId。

## 手机端接入顺序

1. 注册/登录，安全保存 accessToken；读取 capabilities 判断生成是否可用。
2. 创建角色；用户日记默认私有。
3. 保存日记后，调用角色的 grants 接口分享精确 entryRevision；首次 grant revision 为 0。
4. 创建角色会话，可附 entryId；发送消息返回 202 和 job，按 job.id 查询状态。
5. succeeded 时通过 resultId 读取对应角色日记，或刷新会话消息；failed / cancelled 显示原因。
6. 日记或分享冲突时先读最新版本，再让用户选择。撤回不能在后台静默反向重试成分享。

业务写操作需要 UUID v4 `Idempotency-Key`。一次操作重试复用原键与原请求体。
同键不同内容返回 `IDEMPOTENCY_MISMATCH`；同键相同内容返回资源**当前**状态，不再次应用旧变更。
`GET /operations/{key}` 可恢复 resourceKind / resourceId，不返回正文或内部摘要。
所有列表默认 30、最多 100，游标必须用于同账户、同集合。消息返回新到旧，客户端阅读时按 sequence 排序。

## 关键状态与错误

| 标识 | 客户端行为 |
| --- | --- |
| REVISION_CONFLICT | 读取最新内容，明确选择后用新操作键保存 |
| ENTRY_NOT_SHARED / INVALID_SOURCE | 检查分享状态和来源版本；不能自动分享 |
| GENERATION_BUSY | 继续查询现有任务，避免重复提交 |
| PROVIDER_NOT_CONFIGURED | 原消息仍保存；等待服务商接入，不能显示为生成成功 |
| PROVIDER_FAILURE / PROVIDER_TIMEOUT | 保留原消息，允许明确重试 |
| WORKER_INTERRUPTED | 旧 worker 已失效；外部请求可能已执行，重试可能产生供应商费用 |
| CONTEXT_CHANGED | 旧任务作废，读取新分享状态后发起新的生成 |
| STALE_TURN / NOT_RETRYABLE | 不重试旧任务，用户可发送新消息 |
| INVALID_MODEL_RESULT | 结果未发布；空白或超长结果被拒绝 |

任务状态为 pending / running / succeeded / failed / cancelled；resultId 只在成功时有值。
任务 sources 记录直接引用的日记版本；上下文代次处理旧对话和角色日记的间接依赖，不是完整逐句溯源。
`author=character` 的日记属于角色设定内的虚构内容，不应在页面呈现为真实人物的生活记录。

模型接口默认关闭。要接入真实服务，在服务器实现 `ModelProvider` 并传给 `createApp`；必须处理 AbortSignal、
保留稳定错误且避免记录正文/密钥。需要另行验证供应商接口、费用、内容输出和中文陪伴体验。
不能通过 `.env` 填一个任意地址就宣称已接入真实模型；目前没有 HTTP 供应商适配实现。

`npm run contract` 更新契约，`npm test` 比较运行时和文件是否一致，并验证真实 PostgreSQL 业务行为。
