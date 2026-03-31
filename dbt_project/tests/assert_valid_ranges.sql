-- 범위 테스트: 주요 비율/점수 컬럼이 유효 범위 내인지 검증
-- completion_rate(0~1), drop_rate(0~1), performance_score(0~1), mal_score(1~10)
-- 이 쿼리가 행을 반환하면 테스트 실패

SELECT 'completion_rate' as metric, anime_id, completion_rate as value
FROM {{ ref('mart_content_performance') }}
WHERE completion_rate IS NOT NULL AND (completion_rate < 0 OR completion_rate > 1)

UNION ALL

SELECT 'drop_rate', anime_id, drop_rate
FROM {{ ref('mart_content_performance') }}
WHERE drop_rate IS NOT NULL AND (drop_rate < 0 OR drop_rate > 1)

UNION ALL

SELECT 'performance_score', anime_id, performance_score
FROM {{ ref('mart_content_performance') }}
WHERE performance_score IS NOT NULL AND (performance_score < 0 OR performance_score > 1)

UNION ALL

SELECT 'mal_score', anime_id, mal_score
FROM {{ ref('mart_content_performance') }}
WHERE mal_score IS NOT NULL AND (mal_score < 1 OR mal_score > 10)
