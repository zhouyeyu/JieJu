# JieJu Cross-platform Contracts

这里是 macOS、Windows 和未来其他客户端之间的数据事实来源。`v1/` 内的 JSON Schema 一旦发布，
只允许向后兼容修正；破坏性变化必须创建 `v2/`，不能直接覆盖旧字段。

## 规则

- Swift、C#、Rust 和 Web 代码都从这些契约实现自己的类型，不互相引用平台类型。
- API Key、访问令牌和本机文件绝对路径不属于共享设置或同步数据。
- Reader Web 与原生外壳只传 JSON 消息，禁止直接暴露平台对象。
- 阅读位置使用稳定 locator；动态页码只用于显示，不能作为跨设备唯一位置。
- 修改 Schema 时必须同步更新示例、对应平台测试、`manifest.json` 和本目录版本说明。

`v1` 固定初始阅读与解句结构。`v2` 为 learning library 增加生词条目，并通过引用复用未变化的
v1 定义；`v3` 增加复习卡片与只追加的复习日志。已有版本目录保持不可变，App 必须显式迁移。
