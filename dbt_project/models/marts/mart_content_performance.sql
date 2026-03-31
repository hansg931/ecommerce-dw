-- mart_content_performance: 콘텐츠 성과 종합 테이블
-- 비즈니스 질문: "어떤 콘텐츠가 잘 되고 있나?" 에 답변

with anime_stats as (
    select * from {{ ref('int_anime_stats') }}
),

synopsis_info as (
    select
        anime_id,
        has_synopsis,
        synopsis_word_count
    from {{ ref('stg_anime_synopsis') }}
)

select
    a.anime_id,
    a.name,
    a.type,
    a.genres,
    a.source_material,
    a.source_category,
    a.studios,
    a.start_year,
    a.season,
    a.episodes,
    a.is_digital_native,

    -- 품질 지표
    a.mal_score,
    a.avg_rating,
    a.median_rating,
    a.stddev_rating,
    a.high_rating_ratio,
    a.low_rating_ratio,

    -- 인기도 지표
    a.members,
    a.members_tier,
    a.favorites,
    a.rating_count,

    -- 시청 행동 지표 (핵심 KPI)
    a.completion_rate,
    a.drop_rate,
    a.plan_rate,
    a.completed_users,
    a.dropped_users,
    a.watching_users,

    -- 메타데이터 품질
    s.has_synopsis,
    s.synopsis_word_count,
    a.has_ratings,

    -- 종합 순위
    rank() over (order by a.mal_score desc nulls last) as score_rank,
    rank() over (order by a.members desc nulls last) as popularity_rank,
    rank() over (order by a.completion_rate desc nulls last) as completion_rank,
    rank() over (order by a.rating_count desc nulls last) as engagement_rank,

    -- 성과 점수 (정규화된 종합 지표)
    -- Score(40%) + Completion Rate(30%) + log(Members)(20%) + low Drop Rate(10%)
    --
    -- 가중치 근거 (상관 분석 결과):
    --   score↔completion = -0.03 (거의 독립 → 상호보완적, 둘 다 포함 합리적)
    --   score↔log(members) = 0.70 (중복 있으나 가중치 0.4 vs 0.2로 차등 부여)
    --   completion↔drop = -0.50 (역지표 관계 확인 → drop_rate 10%로 보조 지표화)
    -- 민감도 분석: 대안 가중치(0.3/0.3/0.2/0.2)와 Top 10 순위 비교 시
    --   상위 6위까지 동일, 7~10위 미세 변동 → 현재 가중치는 로버스트
    coalesce(
        0.4 * (a.mal_score - 1.0) / 9.0
        + 0.3 * coalesce(a.completion_rate, 0)
        + 0.2 * (ln(greatest(a.members, 1)) / ln(2600000))  -- MAX(members)=2,589,552; 근사값 사용 (차이 0.4%). 프로덕션 전환 시 윈도우 함수 동적화 검토
        + 0.1 * (1.0 - coalesce(a.drop_rate, 0)),
        null
    ) as performance_score

from anime_stats a
left join synopsis_info s on a.anime_id = s.anime_id
