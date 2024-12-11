-- 3 - Graph databases

-- DDLs
CREATE TYPE vertex_type
AS ENUM ('player', 'team', 'game');


CREATE TABLE vertices
(
    identifier TEXT,
    type       vertex_type,
    properties JSON,
    PRIMARY KEY (identifier, type)
);

CREATE TYPE edge_type
AS ENUM (
    'plays_against',
    'shares_team',
    'plays_in',
    'plays_on'
    );

CREATE TABLE edges (
                       subject_identifier TEXT,
                       subject_type vertex_type,
                       object_identifier TEXT,
                       object_type vertex_type,
                       edge_type edge_type,
                       properties JSON,
                       PRIMARY KEY (
                                    subject_identifier,
                                    subject_type,
                                    object_identifier,
                                    object_type,
                                    edge_type
                           )
);

---
-- Add vertices
--- 

-- Add game vertices
INSERT INTO vertices
SELECT
    game_id as identifier,
    'game'::vertex_type as type,
        json_build_object(
                'pts_home', pts_home,
                'pts_away', pts_away,
                'winning_team', CASE WHEN home_team_wins = 1 THEN home_team_id ELSE visitor_team_id END
        ) as properties
from games;

-- Add player vertices
INSERT INTO vertices
WITH players_agg AS (select player_id                   as identifier,
                            MAX(player_name)            AS player_name,
                            COUNT(*)                    as number_of_games,
                            SUM(pts)                    as total_points,
                            ARRAY_AGG(DISTINCT team_id) as teams
                     FROM game_details
                     GROUP BY player_id)
SELECT
    identifier,
    'player'::vertex_type as type,
        json_build_object(
            'player_name', player_name,
                'number_of_games', number_of_games,
                'total_points', total_points,
                'teams', teams
            )
FROM players_agg;

-- Add team vertices
INSERT INTO vertices
WITH teams_deduped AS (
    SELECT *, ROW_NUMBER() over (PARTITION BY team_id) as row_num FROM teams    -- For some reason it's dedupled although it should be, it's not part of the lab
)
SELECT
    team_id as identifier,
    'team'::vertex_type as type,
        json_build_object(
            'abbreviation', abbreviation,
                'nickname', nickname,
                'city', city,
                'arena', arena,
                'year_founded', yearfounded

            )
FROM teams_deduped
WHERE row_num = 1;


----
-- Add Edges
----

-- Add plays_in edges
INSERT INTO edges
WITH deduped AS (
    SELECT *, ROW_NUMBER() over (PARTITION BY player_id, game_id) as row_num FROM game_details    -- For some reason it's dedupled although it should be, it's not part of the lab
)
SELECT
    player_id AS subject_identifier,
    'player'::vertex_type AS subject_type,
        game_id AS object_identifier,
    'game'::vertex_type as object_type,
        'plays_in'::edge_type as edge_type,
        json_build_object(
                'start_position', start_position,
                'pts', pts,
                'team_id', team_id,
                'team_abbreviation', team_abbreviation
        ) AS properties
FROM deduped
WHERE row_num = 1;


-- Example: 
SELECT
    v.properties->>'player_name' as player_name, 
    MAX(cast(e.properties->>'pts' as int)) as max_pts
FROM vertices v
         JOIN edges e ON e.subject_identifier = v.identifier AND e.subject_type = v.type
GROUP BY 1
ORDER BY 2 desc NULLS LAST;


-- Add plays_against and shares_team edges
INSERT INTO edges
WITH deduped AS (
    SELECT *, ROW_NUMBER() over (PARTITION BY player_id, game_id) as row_num FROM game_details    -- For some reason it's dedupled although it should be, it's not part of the lab
),
     filtered AS (
         SELECT * FROM deduped WHERE row_num = 1
     )
SELECT
    f1.player_id as subject_identifier,
    'player'::vertex_type as subject_type,
        f2.player_id as object_identifier,
    'player'::vertex_type as object_type,
        CASE WHEN f1.team_abbreviation = f2.team_abbreviation THEN 'shares_team'::edge_type ELSE 'plays_against'::edge_type END as edge_type,
    json_build_object(
            'num_games', COUNT(*),
            'subject_pts', SUM(f1.pts),
            'object_pts', SUM(f2.pts),
            'subject_name', MAX(f1.player_name),
            'object_name', MAX(f2.player_name)
    ) as properties
FROM filtered f1
         JOIN filtered f2 ON f1.game_id = f2.game_id AND f1.player_id <> f2.player_id
-- WHERE f1.player_id > f2.player_id   -- For deduplication (A, B) and (B, A) are the same
GROUP BY 1, 2, 3, 4, 5; -- Don't do this aggregation in production, it's just for the sake of the example

-- Try it out
with player_stats as (
    SELECT v.properties ->> 'player_name'                   as player_name,
               e.properties ->> 'object_name'                             as teammate_name,
             CAST(v.properties ->> 'number_of_games' AS REAL) as number_of_games,
             CAST(v.properties ->> 'total_points' AS REAL)    as total_points,
             e.properties->>'subject_pts'                        as pts_alongside,
             e.properties->>'num_games'                         as num_games_allongside
    FROM vertices v
        JOIN edges e ON e.subject_identifier = v.identifier AND e.subject_type = v.type
    WHERE v.type = 'player'
      AND e.edge_type = 'shares_team'

)
select
    player_name,
    teammate_name,
    total_points / number_of_games as avg_pts_career,
    pts_alongside::REAL / num_games_allongside::REAL as avg_pts_alongside
from player_stats
where number_of_games <> 0 and num_games_allongside::REAL <> 0;