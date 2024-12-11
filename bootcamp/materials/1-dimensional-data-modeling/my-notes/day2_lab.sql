--- Learnings
--- 1. SCD tables can track multiple dimensions at once


-- PREP (the lab starts below)

CREATE TABLE players (
    player_name TEXT,
    height TEXT,
    college TEXT,
    country TEXT,
    draft_year TEXT,
    draft_round TEXT,
    draft_number TEXT,
    season_stats season_stats[],
    scoring_class scoring_class,
    years_since_last_season INTEGER,
    current_season INTEGER,
    is_active BOOLEAN,
    PRIMARY KEY (player_name, current_season)
);


INSERT INTO players
WITH years AS (
    SELECT *
    FROM GENERATE_SERIES(1996, 2022) AS season
), p AS (
    SELECT
        player_name,
        MIN(season) AS first_season
    FROM player_seasons
    GROUP BY player_name
), players_and_seasons AS (
    SELECT *
    FROM p
             JOIN years y
                  ON p.first_season <= y.season
), windowed AS (
    SELECT
        pas.player_name,
        pas.season,
        ARRAY_REMOVE(
                ARRAY_AGG(
                        CASE
                            WHEN ps.season IS NOT NULL
                                THEN ROW(
                            ps.season,
                            ps.gp,
                            ps.pts,
                            ps.reb,
                            ps.ast
                            )::season_stats
                            END)
                        OVER (PARTITION BY pas.player_name ORDER BY COALESCE(pas.season, ps.season)),
                NULL
        ) AS seasons
    FROM players_and_seasons pas
             LEFT JOIN player_seasons ps
                       ON pas.player_name = ps.player_name
                           AND pas.season = ps.season
    ORDER BY pas.player_name, pas.season
), static AS (
    SELECT
        player_name,
        MAX(height) AS height,
        MAX(college) AS college,
        MAX(country) AS country,
        MAX(draft_year) AS draft_year,
        MAX(draft_round) AS draft_round,
        MAX(draft_number) AS draft_number
    FROM player_seasons
    GROUP BY player_name
)
SELECT
    w.player_name,
    s.height,
    s.college,
    s.country,
    s.draft_year,
    s.draft_round,
    s.draft_number,
    seasons AS season_stats,
    CASE
        WHEN (seasons[CARDINALITY(seasons)]::season_stats).pts > 20 THEN 'star'
        WHEN (seasons[CARDINALITY(seasons)]::season_stats).pts > 15 THEN 'good'
        WHEN (seasons[CARDINALITY(seasons)]::season_stats).pts > 10 THEN 'average'
        ELSE 'bad'
        END::scoring_class AS scoring_class,
        w.season - (seasons[CARDINALITY(seasons)]::season_stats).season as years_since_last_active,
    w.season,
    (seasons[CARDINALITY(seasons)]::season_stats).season = season AS is_active
FROM windowed w
         JOIN static s
              ON w.player_name = s.player_name;



SELECT player_name, scoring_class, is_active
FROM players
WHERE current_season = 2022;

-- Start of the lab
-- SCD table

DROP TABLE players_scd;
CREATE TABLE players_scd (
    player_name TEXT,
    scoring_class scoring_class, --- SCD Dimension
    is_active BOOLEAN,  --- SCD Dimension
    start_season INTEGER,
    end_season INTEGER,
    current_season INTEGER,
    PRIMARY KEY (player_name, current_season, start_season)
);


-- Method 1: Compute with full dataset
-- not actually that bad for dimensional data; it worked fine in Airbnb with millions of users (maybe not for billions)

INSERT INTO players_scd
with with_previous AS (
    SELECT
        player_name,
        current_season,
        scoring_class,
        is_active,
        LAG(scoring_class, 1) over (PARTITION BY player_name ORDER BY current_season) AS previous_scoring_class,
        LAG(is_active, 1) over (PARTITION BY player_name ORDER BY current_season) AS previous_is_active
    FROM players
    WHERE current_season <= 2021
),
with_indicators AS (
    SELECT
        *, 
        CASE WHEN scoring_class <> previous_scoring_class OR is_active <> previous_is_active
            THEN 1
            ELSE 0
        END AS change_indicator
    FROM with_previous
),
with_streaks AS (
    SELECT 
        *,
        SUM(change_indicator) OVER (PARTITION BY player_name ORDER BY current_season) AS streak_identifier
    FROM with_indicators
)
SELECT 
    player_name,
    scoring_class,
    is_active,
    MIN(current_season) AS start_season,
    MAX(current_season) AS end_season,
    2021 as current_season --- This is the state of players as of 2021, this would be injected by the ETL process
FROM with_streaks
GROUP BY player_name, streak_identifier, scoring_class , is_active
ORDER BY player_name, streak_identifier;


-- Method 2: Incremental computation
-- Processes the compacted historical data and adds the new data
CREATE TYPE scd_type AS (
    scoring_class scoring_class,
    is_active BOOLEAN,
    start_season INTEGER,
    end_season INTEGER
);
WITH last_season_scd AS (
    SELECT
        *
    FROM players_scd
    WHERE current_season = 2021
    AND end_season = 2021
), 
historical_scd AS (
    SELECT
        player_name,
        scoring_class,
        is_active,
        start_season,
        end_season
    FROM players_scd
    WHERE current_season = 2021
      AND end_season < 2021
),
this_season_data AS (
    SELECT
        *
    FROM players
    WHERE current_season = 2022
),
unchanged_records AS (
    SELECT
        ts.player_name,
        ts.scoring_class,
        ts.is_active,
        ls.start_season,
        ts.current_season as end_season
    from this_season_data ts
    JOIN last_season_scd ls
    ON ts.player_name = ls.player_name
    WHERE ts.scoring_class = ls.scoring_class
    AND ts.is_active = ls.is_active
    ),
changed_records AS (
    SELECT
        ts.player_name,
        
        UNNEST(ARRAY [
            ROW(ls.scoring_class, ls.is_active, ls.start_season, ls.end_season)::scd_type,
            ROW(ts.scoring_class, ts.is_active, ts.current_season, ts.current_season)::scd_type
        ]) as records
    from this_season_data ts
    LEFT JOIN last_season_scd ls
    ON ts.player_name = ls.player_name
    WHERE (ts.scoring_class <> ls.scoring_class
    OR ts.is_active <> ls.is_active)
),
unnested_changed_records AS (
    SELECT 
        player_name,
        (records).scoring_class,
        (records).is_active,
        (records).start_season,
        (records).end_season
    FROM changed_records
),
new_records AS (
    SELECT
        ts.player_name,
        ts.scoring_class,
        ts.is_active,
        ts.current_season as start_season,
        ts.current_season as end_season
    FROM this_season_data ts
    LEFT JOIN last_season_scd ls
        ON ts.player_name = ls.player_name
    WHERE ls.player_name IS NULL
)
SELECT * from historical_scd
UNION ALL 
SELECT * from unchanged_records
UNION ALL
SELECT * from unnested_changed_records
UNION ALL
SELECT * from new_records


;