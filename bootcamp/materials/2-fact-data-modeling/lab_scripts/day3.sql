CREATE TABLE array_metrics (
    user_id NUMERIC,
    month_start DATE,
    metric_name TEXT,
    metric_array REAL[],
    PRIMARY KEY (user_id, month_start, metric_name)
);


INSERT INTO array_metrics
WITH daily_aggregate AS (
    SELECT
        user_id,
        DATE(event_time) AS date,
        COUNT(*) AS num_site_hits
    FROM events
    WHERE DATE(event_time) = DATE('2023-01-03')
    AND user_id IS NOT NULL
    GROUP BY user_id, DATE(event_time)
), yesterday_array AS (
    SELECT *
    FROM array_metrics
    WHERE month_start = DATE('2023-01-01')
)
SELECT 
    COALESCE(da.user_id, ya.user_id) AS user_id,
    COALESCE(ya.month_start, DATE_TRUNC('month', da.date)) AS month_start,
    'site_hits' AS metric_name,
    CASE WHEN ya.metric_array IS NOT NULL
        THEN ya.metric_array || ARRAY[COALESCE(da.num_site_hits, 0)]
        ELSE ARRAY_FILL(0, ARRAY[date-DATE(DATE_TRUNC('month', da.date))]) || ARRAY[COALESCE(da.num_site_hits, 0)]
    END AS metric_array
FROM daily_aggregate da
    FULL OUTER JOIN yesterday_array ya ON da.user_id = ya.user_id
ON CONFLICT (user_id, month_start, metric_name) DO UPDATE
    SET metric_array = EXCLUDED.metric_array;
;

SELECT *
FROM array_metrics;


-- Example of how to go back to daily aggregates with this

WITH agg AS (
    SELECT 
        metric_name,
        month_start,
        ARRAY[
            SUM(metric_array[1]),
            SUM(metric_array[2]),
            SUM(metric_array[3])
        ] AS summed_array
    FROM array_metrics
    GROUP BY metric_name, month_start
)
SELECT 
    metric_name,
    month_start + CAST(index AS INT) - 1 AS date,
    elem as value
FROM agg CROSS JOIN UNNEST(agg.summed_array) WITH ORDINALITY AS a(elem, index)

