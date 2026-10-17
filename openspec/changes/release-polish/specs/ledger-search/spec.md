# Spec Delta

## MODIFIED Requirements

### Requirement: 搜索 SHALL 匹配备注与关联名称

用户输入关键词时，系统 SHALL 返回备注、分类名、账户名或标签名包含该关键词的交易（不区分大小写）；关键词为空时 SHALL 视为不限关键词。关键词 SHALL 在数据库层先预筛再套用结果上限，MUST NOT 先按"最近 N 笔"截断再在内存里匹配，否则老账永远搜不到。

#### Scenario: 按备注命中

- **WHEN** 用户搜索「超市」
- **THEN** 结果包含备注为「超市采购」的那一笔，不含备注无关的交易

#### Scenario: 按分类名命中

- **WHEN** 用户搜索「餐饮」
- **THEN** 结果包含所有分类为「餐饮」或其二级分类的交易

#### Scenario: 大小写不敏感

- **WHEN** 备注为「Starbucks」，用户搜索「starbucks」
- **THEN** 该笔出现在结果中

#### Scenario: 老账也能搜到

- **WHEN** 账本有 1 万笔，最早的一笔备注是「老账 3」，用户搜索「老账 3」
- **THEN** 能搜到这一笔，即使结果上限只有 2000 条
