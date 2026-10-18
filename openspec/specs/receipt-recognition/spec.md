# receipt-recognition Specification

## Purpose
拍一张小票就能少打几个字：在用户显式开启并配置 API Key 后，把图里的文字交给视觉模型识别，取金额、猜分类、填日期与备注，全部预填到记一笔面板里让用户确认——默认关闭、未开启时不上传，也不替用户直接入账。

## Requirements

### Requirement: 选图后 SHALL 尝试识别

用户在记一笔面板添加图片后，系统 SHALL 尝试用视觉模型识别图中文字，并在有结果时按结果
预填金额、分类、备注与日期；MUST NOT 直接创建交易，保存仍由用户点完成。

MUST NOT 使用设备本地 OCR。仅当用户显式开启视觉识别并保存了 API Key 时，系统 SHALL 调用其
配置的视觉模型；未开启、未保存 Key 或平台不支持时，系统 MUST NOT 发起任何识别请求、也 MUST NOT
上传图片，仅在用户添加图片后提示去设置里配置。

#### Scenario: 认出一张小票

- **WHEN** 用户已开启视觉识别并保存了 API Key，添加一张写着「合计 ¥44.50」「金豆餐厅 消费小票」的截图
- **THEN** 系统把图片发送给配置的视觉模型，面板金额变成 44.50、分类预选「餐饮」、备注填入商家名，且用户可以改

#### Scenario: 没配置时不识别、不上传

- **WHEN** 用户没有开启视觉识别（或没有保存 API Key），添加一张小票图
- **THEN** 不发起任何网络请求，面板提示「视觉识别未开启，可在设置里配置」，其它功能正常

#### Scenario: 已经有输入时不覆盖

- **WHEN** 用户已经填了金额 30 又加了一张图
- **THEN** 金额保持 30，识别只填空白字段（分类/备注）

#### Scenario: 认不出金额

- **WHEN** 图片里没有可识别的金额
- **THEN** 面板给出「没认出金额，手动填一下」的提示，其它输入不变

### Requirement: 视觉识别 SHALL 显式开启且密钥安全保存

视觉识别 SHALL 默认关闭；只有用户在设置中显式开启并保存 API Key 后才 SHALL 生效。

API Key SHALL 保存在系统安全存储（Android Keystore / iOS Keychain），MUST NOT 写入
`app_state`、SQLite、日志、错误提示或遥测；清除 API Key SHALL 同时关闭识别。

#### Scenario: 默认关闭

- **WHEN** 用户首次安装并打开金豆
- **THEN** 视觉识别开关为关闭，添加图片不识别，也不发起网络请求

#### Scenario: 开启但没有 Key 不生效

- **WHEN** 用户打开开关但还没有保存 API Key
- **THEN** 设置页显示「已开启但还没有 API Key：识别不会生效」，添加图片时不上传

#### Scenario: 密钥不落库

- **WHEN** 用户保存 API Key 后检查本地数据库与日志
- **THEN** 看不到明文 Key，只能看到「已保存」这类状态

#### Scenario: 清除 Key 自动关闭

- **WHEN** 用户在设置里清除 API Key
- **THEN** 识别开关同时关闭，之后添加图片不再上传

### Requirement: 视觉识别 SHALL 走 OpenAI 兼容协议且失败不影响记账

视觉识别 SHALL 使用 OpenAI 兼容的 `POST {baseUrl}/chat/completions`：图片 SHALL 以
`image_url` 的 base64 data URL 发送，请求 SHALL 带 `Authorization: Bearer <API Key>`；
服务地址与模型名 SHALL 可配置，默认 `https://api.deepseek.com` 与 `deepseek-flash`，
地址尾部斜杠 SHALL 被归一化。请求 SHALL 关闭推理输出并限制输出长度。

云端请求超时、鉴权失败、限流、服务错误或返回内容不可解析时，系统 SHALL 给出可读提示并保持
金额与分类原样，MUST NOT 阻塞保存；由于不再有本地 OCR，MUST NOT 假装回退到本地识别。
请求与响应日志 MUST NOT 包含 API Key 或图片内容。

#### Scenario: 只改配置就能换厂商

- **WHEN** 用户把 `baseUrl` 改为另一家 OpenAI 兼容服务并改模型名
- **THEN** 识别仍能工作，不需要改代码

#### Scenario: 鉴权失败

- **WHEN** 云端返回 401
- **THEN** 面板提示「视觉识别失败，可以手动填」，金额与分类仍可手动填写并保存

#### Scenario: 超时

- **WHEN** 云端请求超时
- **THEN** 面板提示失败原因，不再等待，用户可继续手动记账

#### Scenario: 畸形响应

- **WHEN** 云端返回 200 但内容不是预期的 JSON
- **THEN** 抛出可读错误（不含 Key 与图片），面板提示手动填，仍可保存

#### Scenario: 没有可用文字

- **WHEN** 云端返回了内容但文字为空、或解析不出金额
- **THEN** 只提示「没认出金额，手动填一下」，仍可保存

### Requirement: 金额 SHALL 优先取合计行

解析 SHALL 优先采用含「合计 / 实付 / 应付 / total」的行里的金额；没有这类行时 SHALL 采用图中最大的金额；
MUST NOT 把小计行的金额当成总额。

#### Scenario: 有合计行

- **WHEN** 识别文本里同时有「¥38.50」「¥6.00」「合计 ¥44.50」
- **THEN** 解析出的金额是 44.50

#### Scenario: 没有合计行

- **WHEN** 识别文本只有「¥38.50」「¥6.00」
- **THEN** 解析出的金额是 38.50（最大的那个）

### Requirement: 分类 SHALL 由关键字推测

解析 SHALL 按商家与文字里的关键字推测分类：餐厅/面馆/咖啡/奶茶/小吃→餐饮，打车/地铁/公交/加油→交通，
超市/便利店/商场→购物，药房/医院→医疗，电影/KTV→娱乐，酒店/机票→旅行；无法推测时 MUST NOT 猜一个错的，保持未选。

#### Scenario: 餐厅

- **WHEN** 文本含「餐厅」「小票」
- **THEN** 推测分类是餐饮

#### Scenario: 猜不出

- **WHEN** 文本只有「¥12.00」
- **THEN** 不预选分类

### Requirement: 识别 SHALL 可插拔且可关闭

识别 SHALL 通过 `ReceiptRecognizer` 接口注入；Web 或不支持的平台 SHALL 使用空实现（不提示、不报错），
测试 SHALL 能注入假识别器。识别失败 MUST NOT 阻塞记账。

#### Scenario: Web 上不识别

- **WHEN** 用户在 Web 版添加图片
- **THEN** 不出现识别相关的提示，也没有报错，其它功能正常

#### Scenario: 识别抛错

- **WHEN** 识别器抛异常
- **THEN** 面板显示「识别失败」一句话，金额与分类保持原样，仍可正常保存
