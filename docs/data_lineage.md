# Data Lineage 다이어그램

## 전체 데이터 흐름

```
┌──────────────────────────────────────────────────────────────────┐
│                        RAW CSV FILES                             │
├────────────────┬──────────────┬──────────────┬──────────────────┤
│  anime.csv     │ rating_      │ animelist.   │ anime_with_      │
│  (17.5K)       │ complete.csv │ csv (109M)   │ synopsis.csv     │
│                │ (57M)        │              │ (16.2K)          │
└───────┬────────┴──────┬───────┴──────┬───────┴────────┬─────────┘
        │               │              │                │
        ▼               ▼              ▼                ▼
┌──────────────────────────────────────────────────────────────────┐
│                     STAGING (Views)                               │
├────────────────┬──────────────┬──────────────┬──────────────────┤
│  stg_anime     │ stg_ratings  │ stg_animelist│ stg_anime_       │
│  +snake_case   │ +type check  │ +status name │  synopsis        │
│  +type cast    │              │  mapping     │ +has_synopsis    │
│  +source_      │              │              │ +word_count      │
│   category     │              │              │                  │
│  +digital_     │              │              │                  │
│   native       │              │              │                  │
└───────┬────────┴──────┬───────┴──────┬───────┴────────┬─────────┘
        │               │              │                │
        │    ┌──────────┘              │                │
        │    │    ┌────────────────────┘                │
        ▼    ▼    ▼                                     │
┌──────────────────────────┐                            │
│   int_anime_stats        │                            │
│   (anime + ratings +     │                            │
│    animelist JOIN)        │                            │
│   +completion_rate       │                            │
│   +drop_rate             │                            │
│   +members_tier          │                            │
│   +rating_stats          │                            │
└──────────┬───────────────┘                            │
           │                                            │
        ┌──┴──┐                                         │
        │     │                                         │
        ▼     │         ┌───────────────────────────────┘
┌─────────┐   │         │
│int_genre │   │         │
│_metrics  │   │         │
│+unnest   │   │         │
│ genres   │   │         │
└────┬─────┘   │         │
     │         │         │
     │         │    ┌────┘
     ▼         ▼    ▼
┌─────────┐ ┌───────────────────────────┐
│mart_    │ │ mart_content_performance  │
│genre_   │ │ (anime_stats +            │
│trends   │ │  synopsis JOIN)           │
│         │ │ +performance_score        │
│+trend_  │ │ +score/popularity/        │
│ category│ │  completion ranks         │
│+health  │ │                           │
│ score   │ │                           │
└─────────┘ └───────────────────────────┘

        ┌──────────┬──────────┐
        │          │          │
        ▼          ▼          ▼
┌──────────┐ ┌──────────┐
│stg_anime │ │stg_ratings│
└────┬─────┘ └────┬─────┘
     │            │
     └─────┬──────┘
           ▼
┌──────────────────────┐
│ int_user_profiles    │
│ +rating stats        │
│ +animelist stats     │
│ +top genre           │
│ +user_tier           │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ mart_user_segments   │
│ +rating_tendency     │
│ +viewing_diversity   │
│ +drop_tendency       │
└──────────────────────┘
```

## 모델 의존성 요약

| Mart 모델 | 의존 Intermediate | 의존 Staging |
|---|---|---|
| mart_content_performance | int_anime_stats | stg_anime, stg_ratings, stg_animelist, stg_anime_synopsis |
| mart_user_segments | int_user_profiles | stg_ratings, stg_animelist, stg_anime |
| mart_genre_trends | int_genre_metrics, int_anime_stats | stg_anime, stg_ratings, stg_animelist |
