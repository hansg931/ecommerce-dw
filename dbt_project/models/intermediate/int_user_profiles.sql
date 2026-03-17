-- int_user_profiles: 유저별 프로필 (평점 행동 + 선호 장르 + 활동 수준)

with user_rating_stats as (
    select
        r.user_id,
        count(*) as total_ratings,
        avg(r.rating) as avg_rating,
        stddev(r.rating) as stddev_rating,
        min(r.rating) as min_rating,
        max(r.rating) as max_rating,
        median(r.rating) as median_rating,
        -- 평점 경향
        count(*) filter (where r.rating >= 8) * 1.0 / count(*) as high_rating_ratio,
        count(*) filter (where r.rating <= 4) * 1.0 / count(*) as low_rating_ratio,
        count(distinct r.anime_id) as unique_anime_rated
    from {{ ref('stg_ratings') }} r
    group by r.user_id
),

user_animelist_stats as (
    select
        user_id,
        count(*) as total_list_entries,
        count(*) filter (where watching_status = 'Completed') as completed_count,
        count(*) filter (where watching_status = 'Watching') as watching_count,
        count(*) filter (where watching_status = 'Dropped') as dropped_count,
        count(*) filter (where watching_status = 'Plan to Watch') as plan_to_watch_count,
        -- 완주 비율
        count(*) filter (where watching_status = 'Completed') * 1.0
            / nullif(count(*), 0) as user_completion_rate,
        -- 드롭 비율
        count(*) filter (where watching_status = 'Dropped') * 1.0
            / nullif(count(*), 0) as user_drop_rate,
        -- 총 시청 에피소드
        sum(watched_episodes) as total_watched_episodes
    from {{ ref('stg_animelist') }}
    group by user_id
),

-- 유저별 가장 많이 본 장르 (Top 1)
user_top_genre as (
    select
        r.user_id,
        a.genres as top_genres,
        row_number() over (
            partition by r.user_id
            order by count(*) desc
        ) as genre_rank
    from {{ ref('stg_ratings') }} r
    join {{ ref('stg_anime') }} a on r.anime_id = a.anime_id
    where a.genres is not null and a.genres != 'Unknown'
    group by r.user_id, a.genres
)

select
    urs.user_id,

    -- 평점 행동
    urs.total_ratings,
    urs.avg_rating,
    urs.stddev_rating,
    urs.median_rating,
    urs.min_rating,
    urs.max_rating,
    urs.high_rating_ratio,
    urs.low_rating_ratio,
    urs.unique_anime_rated,

    -- 시청 행동 (animelist)
    ual.total_list_entries,
    ual.completed_count,
    ual.watching_count,
    ual.dropped_count,
    ual.plan_to_watch_count,
    ual.user_completion_rate,
    ual.user_drop_rate,
    ual.total_watched_episodes,

    -- 선호 장르
    utg.top_genres as most_watched_genres,

    -- 유저 티어 (EDA 인사이트: 파워유저 1%가 9.2% ratings)
    case
        when percent_rank() over (order by urs.total_ratings) >= 0.99 then 'Power'
        when percent_rank() over (order by urs.total_ratings) >= 0.90 then 'Active'
        when percent_rank() over (order by urs.total_ratings) >= 0.50 then 'Regular'
        else 'Casual'
    end as user_tier

from user_rating_stats urs
left join user_animelist_stats ual on urs.user_id = ual.user_id
left join user_top_genre utg
    on urs.user_id = utg.user_id and utg.genre_rank = 1
