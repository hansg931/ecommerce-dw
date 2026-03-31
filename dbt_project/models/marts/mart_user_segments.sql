-- mart_user_segments: 유저 세그먼트 테이블
-- 비즈니스 질문: "어떤 유저가 있고, 어떻게 행동하나?" 에 답변

with user_profiles as (
    select * from {{ ref('int_user_profiles') }}
)

select
    user_id,

    -- 활동 수준
    user_tier,
    total_ratings,
    unique_anime_rated,
    total_list_entries,
    total_watched_episodes,

    -- 평점 행동
    avg_rating,
    stddev_rating,
    median_rating,
    high_rating_ratio,
    low_rating_ratio,

    -- 시청 행동
    completed_count,
    watching_count,
    dropped_count,
    plan_to_watch_count,
    user_completion_rate,
    user_drop_rate,

    -- 선호도
    most_watched_genres,

    -- 평점 성향 분류
    -- 임계치 근거: avg_rating 분포 p25=7.37, p50=7.92, p75=8.50
    --   8.5 = p75 (상위 25%), 7.0 < p25 (하위 ~13%), 5.5 (극단적 엄격 ~1%)
    --   세그먼트 분포: Generous 25% / Moderate 62% / Critical 12% / Very Critical 1%
    case
        when avg_rating >= 8.5 then 'Generous'
        when avg_rating >= 7.0 then 'Moderate'
        when avg_rating >= 5.5 then 'Critical'
        else 'Very Critical'
    end as rating_tendency,

    -- 다양성 분류 (unique anime rated 기준)
    -- 임계치 근거: unique_anime_rated 분포 p50=113, p75=238, p90=429, p95=601
    --   500 ≈ p95 (상위 5%), 100 ≈ p50 (상위 50%), 30 ≈ p20
    --   세그먼트 분포: Explorer 7% / Regular 47% / Selective 27% / Newcomer 19%
    case
        when unique_anime_rated >= 500 then 'Explorer'
        when unique_anime_rated >= 100 then 'Regular Viewer'
        when unique_anime_rated >= 30 then 'Selective'
        else 'Newcomer'
    end as viewing_diversity,

    -- 드롭 성향
    -- 임계치 근거: user_drop_rate 분포 p50=0.02, p75=0.05, p90=0.10, p99=0.25
    --   0.1 = p90 (상위 10%만 Moderate 이상), 0.3 > p99 (상위 0.5%만 High)
    --   세그먼트 분포: High 0.5% / Moderate 10% / Committed 90%
    --   대부분의 유저는 드롭 비율이 매우 낮음 (mean=0.04)
    case
        when user_drop_rate >= 0.3 then 'High Dropper'
        when user_drop_rate >= 0.1 then 'Moderate Dropper'
        else 'Committed Viewer'
    end as drop_tendency,

    -- 활동 집중도 (rating_count / list_entries)
    total_ratings * 1.0 / nullif(total_list_entries, 0) as rating_engagement_ratio

from user_profiles
