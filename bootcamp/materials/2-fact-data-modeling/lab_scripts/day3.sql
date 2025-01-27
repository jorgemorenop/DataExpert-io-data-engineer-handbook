select * from events;

CREATE TABLE users_cumulated (
    user_id TEXT,
    -- List of dates in the past where the user was active
    dates_active DATE[],
    date DATE,
    PRIMARY KEY (user_id, date)
);

INSERT INTO users_cumulated
WITH yesterday AS (
    SELECT 
        *
    FROM users_cumulated
    WHERE date = DATE('2023-01-27')
),
    today AS (
    SELECT 
        user_id::TEXT,
        DATE(CAST(event_time AS TIMESTAMP)) as date_active
    FROM events
    WHERE DATE(CAST(event_time AS TIMESTAMP)) = DATE('2023-01-28')
        AND user_id IS NOT NULL
    GROUP BY user_id, DATE(CAST(event_time AS TIMESTAMP))
)
SELECT 
    COALESCE(t.user_id, y.user_id) as user_id,
    CASE WHEN y.dates_active IS NULL THEN ARRAY[t.date_active]
        WHEN t.date_active IS NULL THEN y.dates_active
        ELSE t.date_active || y.dates_active
    END as dates_active,
    COALESCE(t.date_active, y.date + INTERVAL '1 DAY') as date
FROM today t
FULL OUTER JOIN yesterday y 
    ON t.user_id = y.user_id;


SELECT *
FROM users_cumulated
WHERE date = DATE('2023-01-28')
LIMIT 100;


-- You can use now this cumulated table to extract information like
    -- was the user active yesterday?
    -- was the user active in the last month? and week?
    -- how many days in a row has the user been active?
    -- how many days in the last month has the user been active?
-- (Each month is considered of 28 days here so there's the same amount of dow)
-- We use bitwise operators to check if the user was active on a given date

WITH users AS (
    SELECT * 
    FROM users_cumulated
    WHERE date = DATE('2023-01-28')
),
series AS (
    SELECT * FROM generate_series(DATE('2023-01-01'), DATE('2023-01-28'), INTERVAL '1 DAY') as series_date
),
placeholder_ints AS (
    SELECT 
        CASE WHEN dates_active @> ARRAY [DATE(series_date)]
            THEN CAST(POW(2, 32-(date-DATE(series_date))) AS BIGINT) 
            ELSE 0
        END as placeholder_int_value,
        *
    FROM users CROSS JOIN series
),
user_activity AS (
    SELECT
        user_id,
        CAST(CAST(SUM(placeholder_int_value) AS BIGINT) AS BIT(32)) as active_days
    FROM placeholder_ints
    GROUP BY user_id 
)
SELECT 
    user_id,
    active_days,
    BIT_COUNT(active_days) as dim_num_active_days_last_month,
    BIT_COUNT(active_days) > 0 as dim_is_active_last_month,
    BIT_COUNT(active_days & B'11111110000000000000000000000000') as dim_num_active_days_last_week,
    BIT_COUNT(active_days & B'11111110000000000000000000000000') > 0 as dim_is_active_last_week,
    BIT_COUNT(active_days & B'10000000000000000000000000000000') > 0 as dim_is_active_last_day
FROM user_activity
WHERE user_id = '137925124111668560'

