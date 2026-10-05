# 三款记事本阶段进展报告

更新日期：2026-10-05（Asia/Hong_Kong）。

三款产品均已实现独立后端和 Flutter 核心流程，并通过 Android 模拟器核心场景验证。当前交付是可运行的开发版，尚未完成真机、iOS 和生产发布验收。

本报告同步保存在三个独立仓库。此次只整理文档；下列测试结果来自已完成的验收记录，没有将文档更新记成新一轮代码测试。

## 产品进展

| 产品 | 已实现的主要能力 | 已完成验证 | 当前交付位置 |
| --- | --- | --- | --- |
| ZeroNote | 笔记读写、自动保存、草稿恢复、版本冲突、归零预览/取消/确认、旧保存不能恢复已归零内容 | 后端 14/14；Flutter 17/17，含 6 项真实 API；Android 完整流程及切后台、强制停止后恢复 | [评审分支](https://github.com/cn7shi/zeronote/tree/review/zeronote-m2-20261005)，报告前快照 `986eb78` |
| 层叠笔记 | 原文草稿、A/B 面、原文历史层、B 面手动整理/导入、历史回看、本机输入和请求恢复 | 后端 14/14；Flutter 16/16，含 5 项真实 API；Android 两层原文、B 面版本和普通包草稿重启恢复 | [main](https://github.com/cn7shi/layered-notes/tree/main)，报告前快照 `23b5edc` |
| 双方记事本 | 角色、私人日记、分享/撤回、关联对话、来源记忆、生成任务状态、本机草稿和请求恢复 | 后端 19/19；Flutter 21/21，含 5 项真实 API；Android 分享与撤回、记忆失效、关联对话及普通包重启恢复 | [main](https://github.com/cn7shi/shared-notebook/tree/main)，报告前快照 `41bb50e` |

三个 Flutter 工程的静态检查均通过。Android 验收各包含一个完整集成场景及独立的普通应用恢复检查，不能等同于所有机型与全部异常组合均已覆盖。

ZeroNote 的 M2 代码在评审分支，main 仍为 M1 后端版本；“已推送”不代表已经合并到 main。另外两款 M2 已在 main。代码和文档分阶段提交，安装包、数据库、会话和密钥不进入仓库。

## 已落实的重要决策及原因

1. **移动端优先，使用 Flutter。** Android / iOS 共享界面与应用层代码，分别保留平台工程；Web 是辅助入口。共享代码不替代各平台验收。
2. **前后端分离。** 页面通过控制器与 Repository 调用独立 API；归属、事务、历史保护、分享权限和生成任务由后端处理。这样改页面和交互时，不需要重写数据规则。
3. **稳定接口与可靠恢复。** 使用 REST / OpenAPI、版本号和幂等请求。结果不明时保留原请求，冲突由用户选择，避免重复创建或覆盖其他设备修改；本机草稿不等于完整离线同步。
4. **层叠笔记的 B 面不要求 AI。** B 面是整理后的对话，当前支持手动编辑和粘贴导入。首版整段文本交互仍可调整，模型服务不是保存或回看的前提。
5. **双方记事本先做可替换的服务端模型接口。** 供应商仍待选择，默认关闭。页面可保留想说的话，但禁用新发送和生成；没有将测试替身或示例回复当作真实 AI 效果。
6. **分享必须明确确认。** 日记默认私有，授权绑定角色与内容版本。改写或撤回后，旧授权和来源记忆失效，后续模型上下文排除相关旧内容；不承诺收回已发给供应商的历史请求。
7. **Windows 使用独立物理构建副本。** 绕过中文父目录给 Android 构建带来的限制，保留原仓库路径，并记录源码与 APK 哈希来核对构建输入。

详细理由与代价分别见：
[ZeroNote 决策](https://github.com/cn7shi/zeronote/tree/review/zeronote-m2-20261005/docs/decisions)、
[层叠笔记决策](https://github.com/cn7shi/layered-notes/tree/main/docs/decisions)、
[双方记事本决策](https://github.com/cn7shi/shared-notebook/tree/main/docs/decisions)。

## 评审与验证证据

- ZeroNote 使用 OpenCodeReview 1.12.12 委托模式完成自查，发现的两项 P2 恢复问题已修复并补回归。该模式由当前助手执行复查，没有配置独立审查模型。见[修复记录](https://github.com/cn7shi/zeronote/blob/review/zeronote-m2-20261005/docs/reviews/2026-10-05-recovery-fix.md)和[Android 验收](https://github.com/cn7shi/zeronote/blob/review/zeronote-m2-20261005/docs/reviews/2026-10-05-android-validation.md)。
- ZeroNote [后端 CI](https://github.com/cn7shi/zeronote/actions/runs/37312880013) 通过；该运行只证明后端和契约，不代表手机端设备验收。
- 层叠笔记 [Flutter 与真实 API CI](https://github.com/cn7shi/layered-notes/actions/runs/37325422502) 通过。详见[阶段记录](https://github.com/cn7shi/layered-notes/blob/main/docs/milestones.md)。
- 双方记事本 [后端 CI](https://github.com/cn7shi/shared-notebook/actions/runs/37329477949) 和[最终 Flutter 与真实 API CI](https://github.com/cn7shi/shared-notebook/actions/runs/37334865064) 均通过。首轮 Flutter CI 的测试已通过，但缓存收尾失败；关闭可选缓存后完整重跑通过，没有跳过测试。详见[阶段记录](https://github.com/cn7shi/shared-notebook/blob/main/docs/milestones.md)。
- 三款均已有 Android 调试安装包及构建/校验记录，需要对应开发后端。它们不是可直接分发给公众使用的生产包。

## 尚未完成与下一阶段

| 事项 | 当前边界 |
| --- | --- |
| iOS | 已有工程；尚未执行 macOS / Xcode 构建、签名及设备验收 |
| Android 真机 | 尚待真实中文输入法、长文本、弱网、厂商后台限制等验证；模拟器结果不能替代 |
| 真实 AI | 双方记事本尚未选择/接入供应商，多日背景延续、回复质量、费用与超时需随后评估 |
| 交互细化 | 三款页面仍可调整；层叠笔记改名已有后端接口，手机端暂未提供入口 |
| 离线能力 | 已有草稿与待确认请求恢复，尚无完整离线同步；本机草稿数据库未额外加密 |
| 正式发布 | HTTPS 生产服务、备份恢复、邮箱验证/密码找回/账户删除、正式图标、商店签名及发布仍待完成 |
| 辅助 Web | 保留辅助工程/预览能力，尚未完成完整浏览器验收 |

后续先验证 Android 真机与 iOS 平台，再围绕实际使用反馈调整交互。双方记事本的真实模型接入在确定供应商后推进，密钥只放服务端配置。
