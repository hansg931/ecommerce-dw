-- mart_genre_trends: 장르 트렌드 분석 테이블
-- 비즈니스 질문: "장르별 트렌드는 어떻게 변하고 있나?" 에 답변

with genre_base as (
    select * from {{ ref('int_genre_metrics') }}
),

-- 장르별 연도별 트렌드 (int_anime_stats → genre explode → 연도별 집계)
anime_exploded as (
    select
        a.anime_id,
        a.start_year,
        a.mal_score,
        a.members,
        a.completion_rate,
        trim(g.genre) as genre
    from {{ ref('int_anime_stats') }} a,
        lateral (select unnest(string_split(a.genres, ',')) as genre) g
    where a.genres is not null
        and a.genres != 'Unknown'
        and a.start_year is not null
        and a.start_year >= 2000
        and trim(g.genre) != ''
),

genre_yearly as (
    select
        genre,
        start_year,
        count(*) as anime_count,
        avg(mal_score) as avg_score,
        sum(members) as total_members,
        avg(completion_rate) as avg_completion_rate
    from anime_exploded
    group by genre, start_year
),

-- 장르별 최근 5년 vs 이전 비교
genre_trend_comparison as (
    select
        genre,
        avg(anime_count) filter (where start_year between 2015 and 2019) as recent_avg_count,
        avg(avg_score) filter (where start_year between 2015 and 2019) as recent_avg_score,
        avg(anime_count) filter (where start_year between 2010 and 2014) as prev_avg_count,
        avg(avg_score) filter (where start_year between 2010 and 2014) as prev_avg_score
    from genre_yearly
    group by genre
)

select
    gb.genre,
    gb.anime_count,
    gb.avg_mal_score,
    gb.avg_user_rating,
    gb.total_members,
    gb.avg_members,
    gb.avg_completion_rate,
    gb.avg_drop_rate,
    gb.total_ratings,
    gb.recent_ratio,
    gb.popular_ratio,

    -- 성장 트렌드
    gtc.recent_avg_count,
    gtc.prev_avg_count,
    case
        when gtc.prev_avg_count > 0
        then (gtc.recent_avg_count - gtc.prev_avg_count) / gtc.prev_avg_count
    end as count_growth_rate,

    case
        when gtc.prev_avg_score > 0
        then gtc.recent_avg_score - gtc.prev_avg_score
    end as score_change,

    -- 트렌드 분류
    case
        when gtc.prev_avg_count > 0
            and (gtc.recent_avg_count - gtc.prev_avg_count) / gtc.prev_avg_count > 0.3
        then 'Growing'
        when gtc.prev_avg_count > 0
            and (gtc.recent_avg_count - gtc.prev_avg_count) / gtc.prev_avg_count < -0.2
        then 'Declining'
        else 'Stable'
    end as trend_category,

    -- 장르 건강도 점수 (성장 + 품질 + 인기)
    coalesce(
        0.3 * gb.recent_ratio
        + 0.3 * (gb.avg_mal_score - 5.0) / 5.0
        + 0.2 * gb.popular_ratio
        + 0.2 * gb.avg_completion_rate,
        null
    ) as genre_health_score

from genre_base gb
left join genre_trend_comparison gtc on gb.genre = gtc.genre
