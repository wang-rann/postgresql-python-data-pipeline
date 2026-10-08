-- =====================================================
-- PostgreSQL 数据库构建及数据质量评估
-- 内容：建表 -> 导入数据 -> 数据质量检查
-- =====================================================


-- ============ 1. 清理旧表（先删子表，再删父表，避免外键阻止删除）============
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS regions;


-- ============ 2. 创建表 ============

-- 地区表
CREATE TABLE regions (
    region_id   SERIAL PRIMARY KEY,
    region_name VARCHAR(100) NOT NULL
);

-- 用户表
CREATE TABLE users (
    user_id     SERIAL PRIMARY KEY,
    age         INT,
    gender      VARCHAR(10),
    region_id   INT,                     -- 允许为空：部分用户没有地区信息
    signup_date DATE,
    CONSTRAINT fk_users_region
        FOREIGN KEY (region_id) REFERENCES regions (region_id)
);

-- 产品表
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    category   VARCHAR(50),
    unit_price NUMERIC(10, 2)
);

-- 交易表
CREATE TABLE transactions (
    transaction_id   SERIAL PRIMARY KEY,
    user_id          INT,
    product_id       INT,
    amount           INT NOT NULL,       -- 注意：源数据金额带两位小数，INT 会四舍五入；如需保留，改为 NUMERIC(12, 2)
    transaction_date DATE,               -- 注意：源数据带时间，DATE 会丢掉时间；如需保留，改为 TIMESTAMP
    CONSTRAINT fk_transactions_user
        FOREIGN KEY (user_id) REFERENCES users (user_id),
    CONSTRAINT fk_transactions_product
        FOREIGN KEY (product_id) REFERENCES products (product_id)
);

-- 先为 product_id 设计外键，保证交易只能引用 products 表中已有的商品。
-- 导入数据时发现：存在孤儿记录（product_id 不在 products 表中），违反外键约束，导入失败。
-- 为了保留这些记录、并在后续的数据质量检查和清洗中处理，放宽该约束。
-- 孤儿记录由下方的“完整性检查”查出。
ALTER TABLE transactions DROP CONSTRAINT fk_transactions_product;


-- ============ （在这里导入四张表的数据，顺序：regions -> users -> products -> transactions）============


-- ============ 3. 数据质量检查 ============

-- 3.1 缺失值统计
SELECT SUM(CASE WHEN age IS NULL THEN 1 ELSE 0 END) AS null_age_count
FROM users;

SELECT SUM(CASE WHEN region_id IS NULL THEN 1 ELSE 0 END) AS null_region_id_count
FROM users;

-- 3.2 异常金额检测
SELECT *
FROM transactions
WHERE amount <= 0;

-- 3.3 完整性检查：product_id 不在 products 表中的孤儿记录
SELECT t.*
FROM transactions t
LEFT JOIN products p ON t.product_id = p.product_id
WHERE p.product_id IS NULL
  AND t.product_id IS NOT NULL;

-- 3.4 完整性检查：product_id 为空的交易
SELECT *
FROM transactions
WHERE product_id IS NULL;

-- 3.5 年龄是否合理
SELECT *
FROM users
WHERE age < 0 OR age > 100;

-- 3.6 重复交易检查（用户、商品、金额、日期都相同）
SELECT user_id, product_id, amount, transaction_date, COUNT(*) AS cnt
FROM transactions
GROUP BY user_id, product_id, amount, transaction_date
HAVING COUNT(*) > 1;
