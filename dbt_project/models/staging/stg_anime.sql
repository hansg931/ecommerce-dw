-- stg_anime: anime.csv → 정제된 애니메이션 메타데이터
-- 컬럼명 snake_case, 타입 캐스팅, 파생 컬럼 추가

with source as (
    select * from read_csv_auto('../data/raw/anime.csv')
),

cleaned as (
    select
        -- PK
        "MAL_ID" as anime_id,

        -- 기본 메타데이터
        "Name" as name,
        "English name" as english_name,
        "Japanese name" as japanese_name,
        "Type" as type,
        "Source" as source_material,
        "Studios" as studios,
        "Genres" as genres,
        "Rating" as age_rating,
        "Duration" as duration,

        -- 수치형 캐스팅
        try_cast("Score" as double) as score,
        try_cast("Episodes" as integer) as episodes,
        try_cast("Ranked" as double) as ranked,
        try_cast("Popularity" as integer) as popularity_rank,

        -- 유저 행동 집계
        try_cast("Members" as integer) as members,
        try_cast("Favorites" as integer) as favorites,
        try_cast("Watching" as integer) as watching_count,
        try_cast("Completed" as integer) as completed_count,
        try_cast("On-Hold" as integer) as on_hold_count,
        try_cast("Dropped" as integer) as dropped_count,
        try_cast("Plan to Watch" as integer) as plan_to_watch_count,

        -- 점수 분포
        try_cast("Score-10" as double) as score_10_count,
        try_cast("Score-9" as double) as score_9_count,
        try_cast("Score-8" as double) as score_8_count,
        try_cast("Score-7" as double) as score_7_count,
        try_cast("Score-6" as double) as score_6_count,
        try_cast("Score-5" as double) as score_5_count,
        try_cast("Score-4" as double) as score_4_count,
        try_cast("Score-3" as double) as score_3_count,
        try_cast("Score-2" as double) as score_2_count,
        try_cast("Score-1" as double) as score_1_count,

        -- 시간 정보
        "Aired" as aired,
        "Premiered" as premiered,

        -- 파생 컬럼: 연도 추출
        try_cast(
            regexp_extract("Aired", '(\d{4})', 1) as integer
        ) as start_year,

        -- 파생 컬럼: 시즌 추출
        case
            when "Premiered" is not null and "Premiered" != 'Unknown'
            then split_part("Premiered", ' ', 1)
        end as season,

        -- 파생 컬럼: 소스 카테고리 (IP기반 vs 오리지널)
        case
            when "Source" in ('Manga', 'Light novel', 'Visual novel', 'Novel', 'Web manga')
            then 'IP-based'
            when "Source" = 'Original'
            then 'Original'
            when "Source" = 'Unknown'
            then null
            else 'Other-IP'
        end as source_category,

        -- 파생 컬럼: 디지털 네이티브 여부
        case
            when "Type" in ('ONA')
            then true
            else false
        end as is_digital_native

    from source
)

select * from cleaned
