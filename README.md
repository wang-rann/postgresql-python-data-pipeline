# PostgreSQL 数据库构建与 Python 数据管道清洗

**PostgreSQL Database & Python Data Pipeline: Multi-table Extraction and Data Cleaning**

用 PostgreSQL 建立 4 张关联的交易数据表，评估数据质量，再用 Python（psycopg2 + pandas）跨表提取分析数据集，查明缺失值与异常值的**来源**并完成清洗，输出可直接用于分析的干净数据。

![Python](https://img.shields.io/badge/Python-3.x-blue) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-database-blue) ![pandas](https://img.shields.io/badge/pandas-cleaning-lightgrey)

---

## 1. 项目简介

分析之前，数据通常分散在多张表里，并且存在缺失、孤儿记录和异常值。本项目模拟这个典型场景：

1. 在 PostgreSQL 中建立地区、用户、商品、交易四张表，并写 SQL 检查数据质量；
2. 用 `LEFT JOIN` 把四张表合并成一个分析数据集（1000 条交易记录）；
3. 在 Python 中逐项排查问题，记录每一步清洗的依据和损失的样本量。

## 2. 技术栈

| 类别 | 工具 |
|---|---|
| 数据库 | PostgreSQL |
| 语言与库 | Python、psycopg2、pandas |
| SQL 技能点 | 建表与主外键约束、多表 `LEFT JOIN`、`CASE WHEN` 缺失统计、数据质量检查 |

## 3. 数据

数据为课程提供的模拟数据，共 4 张表。**原始数据未上传**，表结构与规模如下：

| 表 | 行数 | 主要字段 |
|---|---|---|
| `transactions` | 1000 | `transaction_id`、`user_id`、`product_id`、`transaction_date`、`amount` |
| `users` | 200 | `user_id`、`age`、`gender`、`region_id`、`signup_date` |
| `products` | 50 | `product_id`、`name`、`category`、`unit_price` |
| `regions` | 5 | `region_id`、`region_name`（华北、华东、华南、西南、西北） |

关联关系：

```
transactions ──(user_id)──▶ users ──(region_id)──▶ regions
      └──────(product_id)──▶ products
```

> 设计时为 `transactions.product_id` 建立了外键，但导入数据时发现有 20 条交易引用了商品表中不存在的商品，违反约束，因此放宽该外键，把这些孤儿记录保留下来，在数据质量检查与清洗环节处理。实际生产设计中应保留外键，并在入库前先校验。

## 4. 数据管道流程

```
连接数据库 → 跨表提取（LEFT JOIN）→ 检查初始状况 → 异常值处理 → 缺失值处理 → 复查
```

| 步骤 | 做法 |
|---|---|
| 连接数据库 | `psycopg2` 建立连接，封装为函数并做异常处理；密码在运行时通过 `getpass` 输入，不写入代码 |
| 跨表提取 | 以 `transactions` 为主表 `LEFT JOIN` 用户、商品、地区表，保留全部交易，得到 `age`、`region_name`、`category`、`amount`、`transaction_date` 五个字段 |
| 初始检查 | `df.info()` 与 `df.isnull().sum()` |
| 异常值 | 删除 `amount ≤ 0` 的交易 |
| 年龄缺失 | 用中位数填充 |
| 地区、类别缺失 | 直接删除（原因见下节） |
| 复查 | 再次统计缺失值，确认全部为 0 |

## 5. 数据质量发现

本项目所用数据提取后共 **1000** 条交易记录。逐项排查后，问题的来源如下：

| 问题 | 条数 | 占比 | 真实原因 | 处理 |
|---|---|---|---|---|
| `amount ≤ 0` | 50 | 5.0% | 全部为负值（最小约 −99），无零值 | 删除 |
| `age` 缺失 | 131 | 13.1% | 200 位用户中有 24 位年龄为空 | 中位数填充 |
| `region_name` 缺失 | 65 | 6.5% | 12 位用户的 `region_id` 本身为空（源数据缺失，并非关联失败） | 删除 |
| `category` 缺失 | 50 | 5.0% | 30 条交易的 `product_id` 为空；20 条交易的 `product_id` 不在商品表中（11 个不同编号） | 删除 |

- 年龄范围为 18–59 岁，没有不合理取值；交易记录无重复。
- 清洗过程：**1000 → 950（删除负金额）→ 839（删除地区或类别缺失）**，最终保留约 83.9% 的样本。

## 6. 清洗决策与取舍

- **年龄用中位数填充**：对极值不敏感，比均值更稳健。代价是 13.1% 的记录被统一为同一个值，会压缩年龄分布的方差。
- **地区、类别缺失直接删除**：缺失无法由其他字段推断，用 `Unknown` 填充会混入没有分析意义的类别。代价是又损失了 111 条真实交易（占 950 条的 11.7%）。如果后续分析不依赖地区或类别，可以改成用 `Unknown` 保留这些样本。
- **负金额直接删除**：前提是负值为录入错误。如果它们其实是退款，应单独保留并标记，而不是删除。

## 7. 局限与改进方向

- **数据类型精度损失**：源数据的金额带两位小数（如 8841.05），但建表时 `amount` 为 `INT`，小数被四舍五入；`transaction_date` 源数据带时间，建表为 `DATE` 后时间被丢弃。改进：金额用 `NUMERIC(12,2)`，时间用 `TIMESTAMP`。
- **外键不完整**：`product_id` 的外键被放宽，导致孤儿记录进入数据库。改进：保留外键，在入库前先校验并单独处理孤儿记录。
- **异常值只处理了一类**：只检查了负金额，没有检查金额偏大的极端值（最大约 4.96 万），可以用 IQR 或分位数方法评估。
- **缺失值的处理没有按分组细化**：年龄可按地区或类别分组填充，而不是统一用整体中位数。
- **工程化**：用 SQLAlchemy 替代原生连接以消除 pandas 的兼容性警告；把清洗步骤封装成函数，并保存清洗后的数据。
- **可扩展**：在 SQL 中补充分析查询（按地区、类别、月份汇总，用窗口函数做排名与环比），形成“建库 → 清洗 → 分析”的完整流程。

## 8. 仓库结构

```
├── README.md
├── 01_schema_and_quality_checks.sql     # 建表与数据质量检查
├── data_pipeline_and_cleaning.ipynb     # Python 数据管道与清洗
└── requirements.txt
```

## 9. 如何运行

1. 安装 PostgreSQL，并确认有可用的数据库（默认使用 `postgres` 库的 `public` 模式）。
2. 执行 `01_schema_and_quality_checks.sql` 的第 1–2 节（删除旧表并建表）。
3. 准备数据：因课程数据不对外公开，原始数据未上传。请使用提供的数据，或按第 3 节的表结构自行准备模拟数据，导入顺序为 `regions → users → products → transactions`。
   导入后再执行脚本第 3 节的数据质量检查。
4. 安装依赖：
   ```bash
   pip install -r requirements.txt
   ```
5. 运行 `data_pipeline_and_cleaning.ipynb`，第一个单元格会弹出输入框，输入数据库密码即可（密码不会被保存）。

> Notebook 中已保留运行结果，不运行也可以直接查看。

## 10. 说明

本项目为课程项目，数据为模拟数据，仅用于学习与展示数据库操作和数据清洗方法。

**联系方式**：wangran002@suss.edu.sg 
