--

-- There's duplicated data so we need to remove it

SELECT game_id, team_id, player_id, count(*)
FROM game_details
group by game_id, team_id, player_id 
having count(*) > 1;


-- Create DDL
CREATE TABLE fct_game_details (
    dim_game_date date,
    dim_season int,
    dim_team_id int,
    dim_player_id int,
    dim_player_name text,
    dim_start_position text,
    dim_is_playing_at_home boolean,
    dim_did_not_play boolean,
    dim_did_not_dress boolean,
    dim_not_with_team boolean,
    m_minutes REAL,
    m_fgm int,
    m_fga int,
    m_fg3m int,
    m_fg3a int,
    m_oreb int,
    m_dreb int,
    m_reb int,
    m_ast int,
    m_stl int,
    m_blk int,
    m_turnovers int,
    m_pf int,
    m_pts int,
    m_plus_minus int,
    PRIMARY KEY (dim_game_date, dim_team_id, dim_player_id)
);


INSERT INTO fct_game_details
WITH deduped AS (
    SELECT
        gd.*,
        g.game_date_est,
        g.season,
        g.home_team_id,
        ROW_NUMBER() OVER (PARTITION BY gd.game_id, team_id, player_id ORDER BY g.game_date_est) AS row_num
    FROM game_details gd
             -- Since we don't have a when, we need to join with the games table to get the date
             JOIN games g on gd.game_id = g.game_id
)
SELECT
    game_date_est as dim_game_date,
    season as dim_season,
    team_id as dim_team_id,
    player_id as dim_player_id,
    player_name as dim_player_name,
    start_position as dim_start_position,
    team_id = home_team_id AS dim_is_playing_at_home,
    COALESCE(POSITION('DNP' IN comment), 0) > 0 AS dim_did_not_play,
    COALESCE(POSITION('DND' IN comment), 0) > 0 AS dim_did_not_dress,
    COALESCE(POSITION('NWT' IN comment), 0) > 0 AS dim_not_with_team,
    CAST(SPLIT_PART(min, ':', 1)::INT AS REAL) + CAST(SPLIT_PART(min, ':', 2)::INT AS REAL)/60 m_minutes,
    fgm AS m_fgm,
    fga AS m_fga,
    fg3m AS m_fg3m,
    fg3a AS m_fg3a,
    oreb AS m_oreb,
    dreb AS m_dreb,
    reb AS m_reb,
    ast AS m_ast,
    stl AS m_stl,
    blk AS m_blk,
    "TO" as m_turnovers,
    pf as m_pf,
    pts as m_pts,
    plus_minus as m_plus_minus
FROM deduped WHERE row_num = 1;

-- Usage example - find the bailed rate of each player
SELECT dim_player_name,
       COUNT(*) as num_games,
       COUNT(CASE WHEN dim_not_with_team THEN 1 END) as bailed_num,
       CAST(COUNT(CASE WHEN dim_not_with_team THEN 1 END) AS REAL) / COUNT(*) as bailed_rate
FROM fct_game_details
GROUP BY dim_player_name;