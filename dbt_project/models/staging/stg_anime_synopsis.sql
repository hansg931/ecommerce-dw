-- stg_anime_synopsis: anime_with_synopsis.csv → 시놉시스 텍스트 정제

with source as (
    select * from read_csv_auto('../data/raw/anime_with_synopsis.csv')
)

select
    "MAL_ID" as anime_id,
    "Name" as name,
    try_cast("Score" as double) as score,
    "Genres" as genres,
    "sypnopsis" as synopsis,

    -- 파생 컬럼: 시놉시스 메타데이터
    case
        when "sypnopsis" is null
            or "sypnopsis" = ''
            or "sypnopsis" like 'No synopsis%'
        then false
        else true
    end as has_synopsis,

    length("sypnopsis") as synopsis_length,
    length("sypnopsis") - length(replace("sypnopsis", ' ', '')) + 1 as synopsis_word_count

from source
