-- stg_anime_synopsis: anime_with_synopsis.csv → 시놉시스 텍스트 정제

with source as (
    select * from {{ source('raw', 'anime_with_synopsis') }}
)

select
    "MAL_ID" as anime_id,
    "Name" as name,
    try_cast("Score" as double) as score,
    "Genres" as genres,
    "sypnopsis" as synopsis,  -- Note: "sypnopsis" is a typo in the original CSV; kept as-is for source fidelity

    -- 파생 컬럼: 시놉시스 메타데이터
    case
        when "sypnopsis" is null
            or "sypnopsis" = ''
            or "sypnopsis" like 'No synopsis%'
        then false
        else true
    end as has_synopsis,

    length("sypnopsis") as synopsis_length,
    case
        when "sypnopsis" is not null
            and trim("sypnopsis") != ''
            and "sypnopsis" not like 'No synopsis%'
        then array_length(string_split(trim("sypnopsis"), ' '))
        else 0
    end as synopsis_word_count

from source
