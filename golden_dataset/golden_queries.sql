-- ═══════════════════════════════════════════════════
-- Golden SQL Queries — MAL Analytics DW
-- 각 질문 ID에 대응하는 검증된 SQL
-- 실행 환경: DuckDB (mal_analytics.duckdb)
-- ═══════════════════════════════════════════════════

-- ─── CP01: 평균 점수 가장 높은 애니메이션 상위 10개 ───
-- CP01
SELECT name, type, mal_score, members, genres
FROM main_marts.mart_content_performance
WHERE mal_score IS NOT NULL
ORDER BY mal_score DESC
LIMIT 10;

-- ─── CP02: 완주율 가장 높은 TV 애니메이션 상위 10개 ───
-- CP02
SELECT name, mal_score, completion_rate, drop_rate, members
FROM main_marts.mart_content_performance
WHERE type = 'TV'
  AND completion_rate IS NOT NULL
  AND members >= 1000  -- 충분한 샘플 확보
ORDER BY completion_rate DESC
LIMIT 10;

-- ─── CP03: 드롭률 가장 높은 작품과 평균 점수 ───
-- CP03
SELECT name, type, drop_rate, mal_score, members, completion_rate
FROM main_marts.mart_content_performance
WHERE drop_rate IS NOT NULL
  AND members >= 1000
ORDER BY drop_rate DESC
LIMIT 10;

-- ─── CP04: 종합 성과 점수 상위 20개 ───
-- CP04
SELECT name, type, performance_score, mal_score, completion_rate,
       drop_rate, members, members_tier
FROM main_marts.mart_content_performance
WHERE performance_score IS NOT NULL
ORDER BY performance_score DESC
LIMIT 20;

-- ─── CP05: IP 기반 vs 오리지널 성과 비교 ───
-- CP05
SELECT
    source_category,
    COUNT(*) AS anime_count,
    ROUND(AVG(mal_score), 3) AS avg_score,
    ROUND(AVG(completion_rate), 3) AS avg_completion_rate,
    ROUND(AVG(drop_rate), 3) AS avg_drop_rate,
    ROUND(AVG(members), 0) AS avg_members
FROM main_marts.mart_content_performance
WHERE source_category IS NOT NULL
GROUP BY source_category
ORDER BY avg_score DESC;

-- ─── CP06: 인기작(10만+ Members) 중 드롭률 10% 이상 ───
-- CP06
SELECT name, type, members, drop_rate, mal_score, genres
FROM main_marts.mart_content_performance
WHERE members >= 100000
  AND drop_rate >= 0.10
ORDER BY drop_rate DESC;

-- ─── CP07: ONA vs TV 비교 ───
-- CP07
SELECT
    type,
    COUNT(*) AS anime_count,
    ROUND(AVG(mal_score), 3) AS avg_score,
    ROUND(AVG(completion_rate), 3) AS avg_completion_rate,
    ROUND(AVG(drop_rate), 3) AS avg_drop_rate
FROM main_marts.mart_content_performance
WHERE type IN ('ONA', 'TV')
GROUP BY type;

-- ─── CP08: 시놉시스 유무별 비교 ───
-- CP08
SELECT
    has_synopsis,
    COUNT(*) AS anime_count,
    ROUND(AVG(members), 0) AS avg_members,
    ROUND(AVG(mal_score), 3) AS avg_score
FROM main_marts.mart_content_performance
GROUP BY has_synopsis;

-- ─── CP09: 인기도 상위 1% 작품 통계 ───
-- CP09
SELECT
    ROUND(AVG(mal_score), 3) AS avg_score,
    ROUND(AVG(completion_rate), 3) AS avg_completion_rate,
    COUNT(*) AS anime_count,
    genres,
    COUNT(*) AS genre_count
FROM main_marts.mart_content_performance
WHERE members_tier = 'Top 1%'
GROUP BY genres
ORDER BY genre_count DESC
LIMIT 15;

-- ─── CP10: 2010년대 성과 상위 50 스튜디오 분포 ───
-- CP10
WITH top50 AS (
    SELECT *
    FROM main_marts.mart_content_performance
    WHERE start_year BETWEEN 2010 AND 2019
      AND performance_score IS NOT NULL
    ORDER BY performance_score DESC
    LIMIT 50
)
SELECT studios, COUNT(*) AS anime_count, ROUND(AVG(performance_score), 3) AS avg_perf
FROM top50
GROUP BY studios
ORDER BY anime_count DESC
LIMIT 15;

-- ─── UB01: 유저 티어별 평균 평점과 유저 수 ───
-- UB01
SELECT
    user_tier,
    COUNT(*) AS user_count,
    ROUND(AVG(avg_rating), 3) AS avg_rating,
    ROUND(AVG(total_ratings), 0) AS avg_total_ratings
FROM main_marts.mart_user_segments
GROUP BY user_tier
ORDER BY avg_total_ratings DESC;

-- ─── UB02: 파워유저 vs 나머지 평균 평점 차이 ───
-- UB02
SELECT
    CASE WHEN user_tier = 'Power' THEN 'Power' ELSE 'Others' END AS user_group,
    COUNT(*) AS user_count,
    ROUND(AVG(avg_rating), 3) AS avg_rating,
    ROUND(AVG(total_ratings), 0) AS avg_total_ratings
FROM main_marts.mart_user_segments
GROUP BY 1
ORDER BY avg_rating;

-- ─── UB03: 평점 성향별 유저 수와 비율 ───
-- UB03
SELECT
    rating_tendency,
    COUNT(*) AS user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM main_marts.mart_user_segments
GROUP BY rating_tendency
ORDER BY user_count DESC;

-- ─── UB04: 가장 많은 작품을 본 유저 상위 10명 ───
-- UB04
SELECT user_id, total_ratings, avg_rating, viewing_diversity,
       user_tier, rating_tendency, most_watched_genres
FROM main_marts.mart_user_segments
ORDER BY total_ratings DESC
LIMIT 10;

-- ─── UB05: Explorer 유저의 완주율/드롭률 ───
-- UB05
SELECT
    viewing_diversity,
    COUNT(*) AS user_count,
    ROUND(AVG(user_completion_rate), 3) AS avg_completion_rate,
    ROUND(AVG(user_drop_rate), 3) AS avg_drop_rate,
    ROUND(AVG(avg_rating), 3) AS avg_rating
FROM main_marts.mart_user_segments
WHERE viewing_diversity = 'Explorer'
GROUP BY viewing_diversity;

-- ─── UB06: High Dropper가 가장 많이 시청한 장르 ───
-- UB06
SELECT most_watched_genres, COUNT(*) AS user_count
FROM main_marts.mart_user_segments
WHERE drop_tendency = 'High Dropper'
GROUP BY most_watched_genres
ORDER BY user_count DESC
LIMIT 10;

-- ─── UB07: 유저 티어별 완주율/드롭률/참여율 비교 ───
-- UB07
SELECT
    user_tier,
    COUNT(*) AS user_count,
    ROUND(AVG(user_completion_rate), 3) AS avg_completion,
    ROUND(AVG(user_drop_rate), 3) AS avg_drop,
    ROUND(AVG(rating_engagement_ratio), 3) AS avg_engagement
FROM main_marts.mart_user_segments
GROUP BY user_tier
ORDER BY user_count DESC;

-- ─── UB08: 평균 평점 9+ 유저 ───
-- UB08
SELECT
    COUNT(*) AS user_count,
    ROUND(AVG(total_ratings), 1) AS avg_total_ratings,
    ROUND(AVG(user_completion_rate), 3) AS avg_completion_rate
FROM main_marts.mart_user_segments
WHERE avg_rating >= 9.0;

-- ─── UB09: Generous vs Critical 유저 시청 작품 수 비교 ───
-- UB09
SELECT
    rating_tendency,
    COUNT(*) AS user_count,
    ROUND(AVG(unique_anime_rated), 1) AS avg_unique_anime,
    ROUND(AVG(total_ratings), 1) AS avg_total_ratings
FROM main_marts.mart_user_segments
WHERE rating_tendency IN ('Generous', 'Critical')
GROUP BY rating_tendency;

-- ─── UB10: 총 시청 에피소드 상위 5명 ───
-- UB10
SELECT user_id, total_watched_episodes, total_ratings, avg_rating,
       user_tier, viewing_diversity
FROM main_marts.mart_user_segments
ORDER BY total_watched_episodes DESC
LIMIT 5;

-- ─── GA01: 작품 수 상위 10 장르 ───
-- GA01
SELECT genre, anime_count, ROUND(avg_mal_score, 3) AS avg_score, total_members
FROM main_marts.mart_genre_trends
ORDER BY anime_count DESC
LIMIT 10;

-- ─── GA02: 평균 MAL 점수 상위 5 장르 ───
-- GA02
SELECT genre, ROUND(avg_mal_score, 3) AS avg_score, anime_count, total_ratings
FROM main_marts.mart_genre_trends
ORDER BY avg_mal_score DESC
LIMIT 5;

-- ─── GA03: 장르 건강도 상위 10개 ───
-- GA03
SELECT genre, ROUND(genre_health_score, 3) AS health_score,
       anime_count, ROUND(avg_mal_score, 3) AS avg_score,
       trend_category, ROUND(recent_ratio, 3) AS recent_ratio
FROM main_marts.mart_genre_trends
WHERE genre_health_score IS NOT NULL
ORDER BY genre_health_score DESC
LIMIT 10;

-- ─── GA04: 성장 중인 장르 ───
-- GA04
SELECT genre, trend_category,
       ROUND(count_growth_rate, 3) AS growth_rate,
       anime_count, ROUND(avg_mal_score, 3) AS avg_score
FROM main_marts.mart_genre_trends
WHERE trend_category = 'Growing'
ORDER BY count_growth_rate DESC;

-- ─── GA05: 감소 중인 장르 ───
-- GA05
SELECT genre, trend_category,
       ROUND(count_growth_rate, 3) AS growth_rate,
       ROUND(score_change, 3) AS score_change,
       anime_count
FROM main_marts.mart_genre_trends
WHERE trend_category = 'Declining'
ORDER BY count_growth_rate ASC;

-- ─── GA06: 완주율 최고 vs 드롭률 최고 장르 ───
-- GA06
(SELECT 'Highest Completion' AS category, genre,
        ROUND(avg_completion_rate, 3) AS rate, anime_count
 FROM main_marts.mart_genre_trends
 ORDER BY avg_completion_rate DESC LIMIT 5)
UNION ALL
(SELECT 'Highest Drop' AS category, genre,
        ROUND(avg_drop_rate, 3) AS rate, anime_count
 FROM main_marts.mart_genre_trends
 ORDER BY avg_drop_rate DESC LIMIT 5);

-- ─── GA07: 총 Members 상위 5 장르의 인기 작품 비율 ───
-- GA07
SELECT genre, total_members, ROUND(popular_ratio, 3) AS popular_ratio,
       anime_count, ROUND(avg_mal_score, 3) AS avg_score
FROM main_marts.mart_genre_trends
ORDER BY total_members DESC
LIMIT 5;

-- ─── GA08: 신흥 장르 (recent_ratio > 50%) ───
-- GA08
SELECT genre, ROUND(recent_ratio, 3) AS recent_ratio,
       anime_count, trend_category, ROUND(avg_mal_score, 3) AS avg_score
FROM main_marts.mart_genre_trends
WHERE recent_ratio > 0.50
ORDER BY recent_ratio DESC;

-- ─── TR01: 연도별 작품 수 (2000년 이후) ───
-- TR01
SELECT start_year, COUNT(*) AS anime_count
FROM main_marts.mart_content_performance
WHERE start_year >= 2000 AND start_year IS NOT NULL
GROUP BY start_year
ORDER BY start_year;

-- ─── TR02: ONA 연도별 증가 추이 ───
-- TR02
SELECT start_year, COUNT(*) AS ona_count
FROM main_marts.mart_content_performance
WHERE type = 'ONA' AND start_year >= 2000 AND start_year IS NOT NULL
GROUP BY start_year
ORDER BY start_year;

-- ─── TR03: 2015 전후 평균 점수 비교 ───
-- TR03
SELECT
    CASE WHEN start_year >= 2015 THEN '2015+' ELSE 'Before 2015' END AS period,
    COUNT(*) AS anime_count,
    ROUND(AVG(mal_score), 3) AS avg_score
FROM main_marts.mart_content_performance
WHERE start_year IS NOT NULL AND mal_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- ─── TR04: 시즌별 비교 ───
-- TR04
SELECT season, COUNT(*) AS anime_count,
       ROUND(AVG(mal_score), 3) AS avg_score
FROM main_marts.mart_content_performance
WHERE season IS NOT NULL
GROUP BY season
ORDER BY avg_score DESC;

-- ─── TR05: 연도별 평균 드롭률 추이 ───
-- TR05
SELECT start_year, COUNT(*) AS anime_count,
       ROUND(AVG(drop_rate), 4) AS avg_drop_rate,
       ROUND(AVG(completion_rate), 4) AS avg_completion_rate
FROM main_marts.mart_content_performance
WHERE start_year >= 2000
  AND start_year IS NOT NULL
  AND drop_rate IS NOT NULL
GROUP BY start_year
ORDER BY start_year;

-- ─── CM01: 스튜디오별 평균 점수 상위 10개 (20작품+) ───
-- CM01
SELECT studios, COUNT(*) AS anime_count,
       ROUND(AVG(mal_score), 3) AS avg_score,
       ROUND(AVG(completion_rate), 3) AS avg_completion
FROM main_marts.mart_content_performance
WHERE studios != 'Unknown' AND mal_score IS NOT NULL
GROUP BY studios
HAVING COUNT(*) >= 20
ORDER BY avg_score DESC
LIMIT 10;

-- ─── CM02: Action vs Romance 비교 ───
-- CM02
SELECT
    genre,
    ROUND(avg_mal_score, 3) AS avg_score,
    ROUND(avg_completion_rate, 3) AS completion_rate,
    total_members,
    anime_count
FROM main_marts.mart_genre_trends
WHERE genre IN ('Action', 'Romance');

-- ─── CM03: 활동 수준별 평점 성향 비교 (인기 작품 소비 프록시) ───
-- CM03
-- 유저 활동 수준(user_tier)을 인기 작품 소비의 프록시로 활용
-- Power/Active 유저는 더 많은 작품을 시청하므로 인기 작품 노출 비율이 높음
SELECT
    user_tier,
    rating_tendency,
    COUNT(*) AS user_count,
    ROUND(AVG(avg_rating), 3) AS avg_avg_rating,
    ROUND(AVG(unique_anime_rated), 1) AS avg_anime_count,
    ROUND(AVG(user_completion_rate), 4) AS avg_completion_rate
FROM main_marts.mart_user_segments
GROUP BY user_tier, rating_tendency
ORDER BY user_tier, rating_tendency;

-- ─── CM04: 2000년대 vs 2010년대 비교 ───
-- CM04
SELECT
    CASE
        WHEN start_year BETWEEN 2000 AND 2009 THEN '2000s'
        WHEN start_year BETWEEN 2010 AND 2019 THEN '2010s'
    END AS decade,
    COUNT(*) AS anime_count,
    ROUND(AVG(drop_rate), 4) AS avg_drop_rate,
    ROUND(AVG(completion_rate), 4) AS avg_completion_rate,
    ROUND(AVG(mal_score), 3) AS avg_score
FROM main_marts.mart_content_performance
WHERE start_year BETWEEN 2000 AND 2019
GROUP BY 1
ORDER BY 1;

-- ─── CM05: Manga vs Light Novel vs Original 비교 ───
-- CM05
SELECT
    source_material,
    COUNT(*) AS anime_count,
    ROUND(AVG(mal_score), 3) AS avg_score,
    ROUND(AVG(completion_rate), 3) AS avg_completion,
    ROUND(AVG(members), 0) AS avg_members
FROM main_marts.mart_content_performance
WHERE source_material IN ('Manga', 'Light novel', 'Original')
GROUP BY source_material
ORDER BY avg_score DESC;

-- ─── CM06: 에피소드 수 구간별 점수/완주율 ───
-- CM06
SELECT
    CASE
        WHEN episodes = 1 THEN '1 ep (Movie/Special)'
        WHEN episodes BETWEEN 2 AND 12 THEN '2-12 eps (1 cour)'
        WHEN episodes BETWEEN 13 AND 26 THEN '13-26 eps (2 cour)'
        WHEN episodes BETWEEN 27 AND 52 THEN '27-52 eps (long)'
        WHEN episodes > 52 THEN '52+ eps (very long)'
    END AS episode_range,
    COUNT(*) AS anime_count,
    ROUND(AVG(mal_score), 3) AS avg_score,
    ROUND(AVG(completion_rate), 3) AS avg_completion
FROM main_marts.mart_content_performance
WHERE episodes IS NOT NULL AND mal_score IS NOT NULL
GROUP BY 1
ORDER BY avg_score DESC;

-- ─── CM07: 상위 1% vs 전체 장르 분포 비교 ───
-- CM07
WITH top1_genres AS (
    SELECT
        trim(unnest(string_split(genres, ','))) AS genre,
        'Top 1%' AS segment
    FROM main_marts.mart_content_performance
    WHERE members_tier = 'Top 1%'
),
all_genres AS (
    SELECT
        trim(unnest(string_split(genres, ','))) AS genre,
        'All' AS segment
    FROM main_marts.mart_content_performance
    WHERE genres IS NOT NULL AND genres != 'Unknown'
)
SELECT genre, segment, COUNT(*) AS cnt
FROM (SELECT * FROM top1_genres UNION ALL SELECT * FROM all_genres)
WHERE genre != ''
GROUP BY genre, segment
ORDER BY genre, segment;
