# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: 选图后 SHALL 尝试本地识别`
- TO: `### Requirement: 选图后 SHALL 尝试识别`

## MODIFIED Requirements

### Requirement: 选图后 SHALL 尝试识别

用户在记一笔面板添加图片后，系统 SHALL 尝试识别文字，并按结果预填金额、分类、备注与日期；
MUST NOT 直接创建交易，保存仍由用户点完成。

识别来源 SHALL 按配置选择：默认、云端识别未开启、或未保存 API Key 时，系统 SHALL 在设备本地识别，
不联网、不上传图片；仅当用户显式开启云端识别时，系统 SHALL 调用其配置的视觉模型。

#### Scenario: 认出一张小票

- **WHEN** 用户添加一张写着「合计 ¥44.50」「金豆餐厅 消费小票」的截图
- **THEN** 面板金额变成 44.50、分类预选「餐饮」、备注填入商家名，且用户可以改

#### Scenario: 默认只在本机识别

- **WHEN** 用户没有开启云端识别，添加一张小票图
- **THEN** 识别在设备本地完成，不发送任何网络请求

#### Scenario: 开启云端后走视觉模型

- **WHEN** 用户已开启云端识别并保存了 API Key，添加一张小票图
- **THEN** 系统把图片发送给配置的视觉模型，并用返回的文字预填金额、分类、备注与日期

#### Scenario: 已经有输入时不覆盖

- **WHEN** 用户已经填了金额 30 又加了一张图
- **THEN** 金额保持 30，识别只填空白字段（分类/备注）

#### Scenario: 认不出金额

- **WHEN** 图片里没有可识别的金额
- **THEN** 面板给出「没认出金额，手动填一下」的提示，其它输入不变

## ADDED Requirements

### Requirement: 云端识别 SHALL 显式开启且密钥安全保存

云端识别 SHALL 默认关闭；只有用户在设置中显式开启并保存 API Key 后才 SHALL 生效。

API Key SHALL 保存在系统安全存储（Android Keystore / iOS Keychain），MUST NOT 写入
`app_state`、SQLite、日志、错误提示或遥测；关闭云端识别后 MUST NOT 再上传任何图片。

#### Scenario: 默认关闭

- **WHEN** 用户首次安装并打开金豆
- **THEN** 云端识别开关为关闭，识别只在本机进行

#### Scenario: 密钥不落库

- **WHEN** 用户保存 API Key 后检查本地数据库与日志
- **THEN** 看不到明文 Key，只能看到「已配置」这类状态

#### Scenario: 关闭即停止上传

- **WHEN** 用户关闭云端识别开关后再添加图片
- **THEN** 不发起云端请求，只使用本地识别

### Requirement: 云端识别 SHALL 走 OpenAI 兼容协议并在失败时回退本地

云端识别 SHALL 使用 OpenAI 兼容的 `POST {baseUrl}/chat/completions`：图片 SHALL 以
`image_url` 的 base64 data URL 发送，请求 SHALL 带 `Authorization: Bearer <API Key>`；
服务地址与模型名 SHALL 可配置，默认 `https://api.deepseek.com` 与 `deepseek-flash`。

云端请求超时、返回错误或没有可用文字时，系统 SHALL 回退到本地识别；两种来源都失败时
MUST NOT 阻塞记账。请求与响应日志 MUST NOT 包含 API Key 或图片内容。

#### Scenario: 只改配置就能换厂商

- **WHEN** 用户把 `baseUrl` 改为另一家 OpenAI 兼容服务并改模型名
- **THEN** 识别仍能工作，不需要改代码

#### Scenario: 超时回退

- **WHEN** 云端请求超时
- **THEN** 系统改用本地识别，面板仍可正常保存

#### Scenario: 鉴权失败

- **WHEN** 云端返回 401
- **THEN** 面板提示「云端识别失败，已用本地识别」，金额与分类仍可手动填写

#### Scenario: 两种来源都没认出

- **WHEN** 云端与本地都没有返回可用文字
- **THEN** 只提示「没认出金额，手动填一下」，仍可保存
