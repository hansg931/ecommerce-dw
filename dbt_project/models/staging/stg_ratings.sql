-- stg_ratings: rating_complete.csv → 정제된 유저 평점 데이터
-- 완료 시청 + 점수 부여한 레코드만 포함 (57M rows)

with source as (
    select * from read_csv_auto('../data/raw/rating_complete.csv')
)

select
    user_id,
    anime_id,
    rating
from source
where rating between 1 and 10
