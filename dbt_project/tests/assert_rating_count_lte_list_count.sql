-- 비즈니스 규칙: 평점 수(rating_count)는 리스트 등록 수(total_list_count) 이하여야 함
-- rating_complete는 animelist의 부분집합 (완료 시청 + 점수 부여)
-- 이 쿼리가 행을 반환하면 테스트 실패

SELECT anime_id, rating_count, total_list_count
FROM {{ ref('int_anime_stats') }}
WHERE rating_count IS NOT NULL
  AND total_list_count IS NOT NULL
  AND rating_count > total_list_count
