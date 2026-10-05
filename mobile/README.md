# 双方记事本 Flutter 客户端

Flutter 3.47.6 / Dart 3.13.5；Android / iOS 为核心平台，Web 为辅助入口。
先在仓库的 server 目录启动独立后端。当前默认模型关闭；页面不包含模拟回复或示例用户数据。

```powershell
flutter pub get --enforce-lockfile
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3300
flutter analyze
flutter test --dart-define=TEST_API_BASE_URL=http://127.0.0.1:3300
```

没有 TEST_API_BASE_URL 时跳过 5 项真实 API 测试，不能据此声称全部验证。测试仅使用合成账户与记录；
真实 API 测试结束后撤销会话，合成记录留在忽略的本地开发数据库中，不上传 Git。

## 分层

- domain：客户端模型、Repository 与本机工作副本接口。
- application：会话、输入恢复、幂等请求、冲突处理、完整授权读取与任务状态。
- data：HTTP / JSON 映射、系统会话存储、Sembast 数据库；仅这一层知道接口路径与存储实现。
- presentation：页面、输入、导航、可见性与交互确认。

页面可以改布局和交互，数据权限、分享版本、上下文失效和生成规则继续由后端执行。
HTTP 客户端为当前契约的手写适配，通过真实 API 测试检查兼容，没有引入自动生成器。

## 本机状态与隐私

会话令牌使用 flutter_secure_storage；工作副本按账户存于 Sembast（Web 为 IndexedDB）。
草稿数据库未额外加密；这不是整库离线缓存。退出账户保留该账户未提交输入。
写请求先持久化原始请求与 UUID，再发 HTTP；返回结果不确定时锁定原请求，用户选择重试或清理。
清理本机请求不会撤销已完成的云端操作，需回到详情刷新核对。版本冲突明确比较双方内容后处理。
角色记忆从已分享日记创建，来源绑定当时版本；撤回或改写后不能继续用旧来源启用记忆。
后台不主动发送消息；只有正在查看且应用在前台时，才每 5 秒刷新已知未完成任务。
其他设备创建的新任务或改动可通过刷新读取。旧对话仍可阅读，但分享/设定改变后不会继续用于角色背景。

## Windows 中文路径与 Android 验证

Gradle 会将目录链接还原到真实路径，因此中文路径下使用独立物理构建目录。
在仓库根运行，脚本只复制 Git 跟踪或未忽略的 mobile 源文件，记录逐文件哈希，不移动原仓库：

```powershell
.\scripts\build-android.ps1 -FlutterSdk C:\path\to\flutter -AndroidSdk C:\path\to\Android\Sdk
.\scripts\build-android.ps1 -FlutterSdk C:\path\to\flutter -AndroidSdk C:\path\to\Android\Sdk -TestDevice emulator-5554
```

第二条验证注册、创建角色、私人日记、分享取消/确认、来源记忆、原文修改撤回、关联对话、
模型关闭时禁用发送、本机输入恢复和记忆失效。需要专用干净测试安装；不要清除自己的真实数据。
设备测试程序和普通应用包不同；普通 APK 在 mobile/build/app/outputs/flutter-apk/app-debug.apk，
对应 build-manifest.json 记录源码提交、输入文件哈希、后端地址及 APK 哈希，均不提交 Git。
调试包使用本机测试服务与调试签名，不是商店发布包。

## 平台边界

Android 调试构建允许本机 HTTP。发布模式要求有效 HTTPS 地址，后端也须独立部署。
iOS 已生成工程、中文名称及 Keychain entitlement；当前 Windows 无法执行 Xcode 构建、签名及 iOS 真机验收。
iOS 本机开发还需由对应 macOS 环境配置网络地址/调试网络策略，不能把 Android 的 10.0.2.2 用于真机。
Web 已保留工程和响应式宽度，尚未进行完整浏览器验收；没有承诺与手机相同的安全存储或后台能力。
