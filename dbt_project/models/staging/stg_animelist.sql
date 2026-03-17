-- stg_animelist: animelist.csv → 시청 상태 포함 유저 행동 데이터 (109M rows)
-- watching_status 코드를 이름으로 매핑

with source as (
    select * from read_csv_auto('../data/raw/animelist.csv')
)

select
    user_id,
    anime_id,
    rating,
    watching_status as watching_status_code,
    case watching_status
        when 1 then 'Watching'
        when 2 then 'Completed'
        when 3 then 'On Hold'
        when 4 then 'Dropped'
        when 6 then 'Plan to Watch'
        else 'Unknown'
    end as watching_status,
    watched_episodes
from source
