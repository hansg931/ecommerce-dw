-- int_genre_metrics: 장르별 지표 (멀티장르 unnest 처리)

with anime_genres as (
    select
        a.anime_id,
        a.name,
        a.type,
        a.mal_score,
        a.members,
        a.start_year,
        a.rating_count,
        a.avg_rating,
        a.completion_rate,
        a.drop_rate,
        a.members_tier,
        trim(unnest(string_split(a.genres, ','))) as genre
    from {{ ref('int_anime_stats') }} a
    where a.genres is not null and a.genres != 'Unknown'
)

select
    genre,

    -- 작품 수
    count(distinct anime_id) as anime_count,

    -- 점수 통계
    avg(mal_score) as avg_mal_score,
    avg(avg_rating) as avg_user_rating,

    -- 인기도
    sum(members) as total_members,
    avg(members) as avg_members,

    -- 시청 행동
    avg(completion_rate) as avg_completion_rate,
    avg(drop_rate) as avg_drop_rate,

    -- 시간 트렌드
    min(start_year) as earliest_year,
    max(start_year) as latest_year,

    -- 평가 활동
    avg(rating_count) as avg_rating_count,
    sum(rating_count) as total_ratings,

    -- 최근 트렌드 (2015년 이후 작품 비율)
    count(*) filter (where start_year >= 2015) * 1.0
        / nullif(count(*), 0) as recent_ratio,

    -- 인기 작품 비율 (상위 10% 비율)
    count(*) filter (where members_tier in ('Top 1%', 'Top 5%', 'Top 10%')) * 1.0
        / nullif(count(*), 0) as popular_ratio

from anime_genres
where genre != ''
group by genre
having count(distinct anime_id) >= 10
