-- Things to learn from this lab:
-- STRUCT and ARRAY data types and use cases
-- How saving historical data with structured data types can be useful since you can perform
-- calculations (in this case, between seasons) without group by, window functions, or joins.
-- Since all the info is in the same row, any map-reduce operation can be done in the map step.


SELECT * FROM player_seasons;

CREATE TYPE season_stats AS (
    season INTEGER,
    gp INTEGER,
    pts REAL,
    reb REAL,
    ast REAL
);

CREATE TABLE players (
                         player_name TEXT,
                         height TEXT,
                         college TEXT,
                         country TEXT,
                         draft_year TEXT,
                         draft_round TEXT,
                         draft_number TEXT,
                         season_stats season_stats[],
                         current_season INTEGER,
                         PRIMARY KEY (player_name, current_season)
);


INSERT INTO players (
    WITH yesterday AS (
    SELECT * FROM players
    WHERE current_season = 2000
),
    today AS (
    SELECT * FROM player_seasons
    WHERE season = 2001
)
SELECT 
    COALESCE(t.player_name, y.player_name) AS player_name,
    COALESCE(t.height, y.height) AS height,
    COALESCE(t.college, y.college) AS college,
    COALESCE(t.country, y.country) AS country,
    COALESCE(t.draft_year, y.draft_year) AS draft_year,
    COALESCE(t.draft_round, y.draft_round) AS draft_round,
    COALESCE(t.draft_number, y.draft_number) AS draft_number,
    CASE WHEN y.season_stats IS NULL 
        THEN ARRAY[ROW (
            t.season,
            t.gp,
            t.pts,
            t.reb,
            t.ast
            )::season_stats] 
        WHEN t.season IS NOT NULL THEN y.season_stats || ARRAY[ROW (
                t.season,
                t.gp,
                t.pts,
                t.reb,
                t.ast
            )::season_stats]
        ELSE y.season_stats
    END AS season_stats,
    COALESCE(t.season, y.current_season + 1) AS current_season
FROM today t FULL OUTER JOIN yesterday y ON t.player_name = y.player_name
);

SELECT * FROM players
WHERE current_season = 2001
  AND player_name = 'Michael Jordan';

SELECT player_name,
       (UNNEST(season_stats)).* AS season_stats
FROM players
WHERE current_season = 2001;


---------

DROP TABLE players;

CREATE TYPE scoring_class AS ENUM ('star', 'good', 'average', 'bad');

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
                         PRIMARY KEY (player_name, current_season)
);


INSERT INTO players (
    WITH yesterday AS (
        SELECT * FROM players
        WHERE current_season = 2000
    ),
    today AS (
             SELECT * FROM player_seasons
             WHERE season = 2001
         )
    SELECT
        COALESCE(t.player_name, y.player_name) AS player_name,
    COALESCE(t.height, y.height) AS height,
    COALESCE(t.college, y.college) AS college,
    COALESCE(t.country, y.country) AS country,
    COALESCE(t.draft_year, y.draft_year) AS draft_year,
    COALESCE(t.draft_round, y.draft_round) AS draft_round,
    COALESCE(t.draft_number, y.draft_number) AS draft_number,
    CASE WHEN y.season_stats IS NULL
                 THEN ARRAY[ROW (
                t.season,
                t.gp,
                t.pts,
                t.reb,
                t.ast
                )::season_stats]
             WHEN t.season IS NOT NULL THEN y.season_stats || ARRAY[ROW (
                 t.season,
                 t.gp,
                 t.pts,
                 t.reb,
                 t.ast
                 )::season_stats]
             ELSE y.season_stats
            END AS season_stats,
    CASE WHEN t.pts > 20 THEN 'star'
             WHEN t.pts > 15 THEN 'good'
             WHEN t.pts > 10 THEN 'average'
             ELSE 'bad'
        END::scoring_class AS scoring_class,
    CASE WHEN t.season IS NOT NULL THEN 0
             ELSE y.years_since_last_season + 1
        END AS years_since_last_season,
    COALESCE(t.season, y.current_season + 1) AS current_season
    FROM today t FULL OUTER JOIN yesterday y ON t.player_name = y.player_name
);



SELECT * FROM players
WHERE current_season = 2001
  and player_name = 'Michael Jordan';

SELECT
    player_name,
    CASE WHEN (season_stats[1]::season_stats).pts = 0 THEN 1 ELSE
        (season_stats[CARDINALITY(season_stats)]::season_stats).pts / 
        (season_stats[1]::season_stats).pts END AS improvement
FROM players
WHERE current_season = 2001;