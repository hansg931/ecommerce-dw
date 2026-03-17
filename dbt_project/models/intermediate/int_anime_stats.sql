-- int_anime_stats: 작품별 평점 통계 + 시청 행동 지표
-- rating_complete + anime 메타데이터 조인

with rating_stats as (
    select
        anime_id,
        count(*) as rating_count,
        avg(rating) as avg_rating,
        median(rating) as median_rating,
        stddev(rating) as stddev_rating,
        min(rating) as min_rating,
        max(rating) as max_rating,
        -- 평점 분포 세부
        count(*) filter (where rating >= 8) * 1.0 / count(*) as high_rating_ratio,
        count(*) filter (where rating <= 4) * 1.0 / count(*) as low_rating_ratio
    from {{ ref('stg_ratings') }}
    group by anime_id
),

animelist_stats as (
    select
        anime_id,
        count(*) as total_list_count,
        count(*) filter (where watching_status = 'Completed') as completed_users,
        count(*) filter (where watching_status = 'Watching') as watching_users,
        count(*) filter (where watching_status = 'Dropped') as dropped_users,
        count(*) filter (where watching_status = 'On Hold') as on_hold_users,
        count(*) filter (where watching_status = 'Plan to Watch') as plan_to_watch_users,
        -- 시청 상태 비율
        count(*) filter (where watching_status = 'Completed') * 1.0
            / nullif(count(*), 0) as completion_rate,
        count(*) filter (where watching_status = 'Dropped') * 1.0
            / nullif(count(*), 0) as drop_rate,
        count(*) filter (where watching_status = 'Plan to Watch') * 1.0
            / nullif(count(*), 0) as plan_rate
    from {{ ref('stg_animelist') }}
    group by anime_id
),

anime_meta as (
    select
        anime_id,
        name,
        type,
        genres,
        source_material,
        source_category,
        studios,
        score as mal_score,
        members,
        favorites,
        start_year,
        season,
        episodes,
        is_digital_native,
        -- 인기도 티어 (EDA 인사이트: 상위 1%/5%가 Members의 29%/64.5%)
        case
            when percent_rank() over (order by members) >= 0.99 then 'Top 1%'
            when percent_rank() over (order by members) >= 0.95 then 'Top 5%'
            when percent_rank() over (order by members) >= 0.90 then 'Top 10%'
            when percent_rank() over (order by members) >= 0.50 then 'Upper Half'
            else 'Lower Half'
        end as members_tier
    from {{ ref('stg_anime') }}
)

select
    a.anime_id,
    a.name,
    a.type,
    a.genres,
    a.source_material,
    a.source_category,
    a.studios,
    a.mal_score,
    a.members,
    a.favorites,
    a.start_year,
    a.season,
    a.episodes,
    a.is_digital_native,
    a.members_tier,

    -- 평점 통계 (rating_complete 기준)
    r.rating_count,
    r.avg_rating,
    r.median_rating,
    r.stddev_rating,
    r.min_rating,
    r.max_rating,
    r.high_rating_ratio,
    r.low_rating_ratio,

    -- 시청 행동 (animelist 기준)
    al.total_list_count,
    al.completed_users,
    al.watching_users,
    al.dropped_users,
    al.on_hold_users,
    al.plan_to_watch_users,
    al.completion_rate,
    al.drop_rate,
    al.plan_rate,

    -- 평점 존재 여부
    case when r.rating_count is not null then true else false end as has_ratings

from anime_meta a
left join rating_stats r on a.anime_id = r.anime_id
left join animelist_stats al on a.anime_id = al.anime_id
