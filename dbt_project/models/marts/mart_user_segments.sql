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
    case
        when avg_rating >= 8.5 then 'Generous'
        when avg_rating >= 7.0 then 'Moderate'
        when avg_rating >= 5.5 then 'Critical'
        else 'Very Critical'
    end as rating_tendency,

    -- 다양성 분류 (unique anime / total ratings)
    case
        when unique_anime_rated >= 500 then 'Explorer'
        when unique_anime_rated >= 100 then 'Regular Viewer'
        when unique_anime_rated >= 30 then 'Selective'
        else 'Newcomer'
    end as viewing_diversity,

    -- 드롭 성향
    case
        when user_drop_rate >= 0.3 then 'High Dropper'
        when user_drop_rate >= 0.1 then 'Moderate Dropper'
        else 'Committed Viewer'
    end as drop_tendency,

    -- 활동 집중도 (rating_count / list_entries)
    total_ratings * 1.0 / nullif(total_list_entries, 0) as rating_engagement_ratio

from user_profiles
