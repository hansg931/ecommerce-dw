# Data Warehouse 설계 문서

## 1. 개요

MyAnimeList(MAL) 2020 데이터셋을 기반으로 한 콘텐츠 플랫폼 Data Warehouse.
DuckDB + dbt-core로 구축한 3-Layer 아키텍처.

## 2. 데이터 소스

| 소스 파일 | 행 수 | 설명 |
|---|---|---|
| anime.csv | 17,562 | 애니메이션 메타데이터 (장르, 스튜디오, 점수 등) |
| rating_complete.csv | 57M | 유저 평점 (시청 완료 + 점수 부여) |
| animelist.csv | 109M | 유저 시청 목록 (시청 상태 포함) |
| anime_with_synopsis.csv | 16,214 | 시놉시스 텍스트 |
| watching_status.csv | 5 | 시청 상태 코드 매핑 |

## 3. 레이어 구조

```
Raw CSV → Staging (View) → Intermediate (Table) → Mart (Table)
```

### Staging Layer (정제, 1:1 매핑)
| 모델 | 소스 | 핵심 변환 |
|---|---|---|
| stg_anime | anime.csv | snake_case, 타입 캐스팅, source_category/is_digital_native 파생 |
| stg_ratings | rating_complete.csv | 타입 검증 (rating 1~10) |
| stg_animelist | animelist.csv | watching_status 코드→이름 매핑 |
| stg_anime_synopsis | anime_with_synopsis.csv | has_synopsis 플래그, word_count 산출 |

### Intermediate Layer (조인, 집계, 파생)
| 모델 | 핵심 로직 | 주요 파생 컬럼 |
|---|---|---|
| int_anime_stats | anime + ratings + animelist 조인 | completion_rate, drop_rate, members_tier |
| int_user_profiles | 유저별 rating/animelist 집계 | user_tier, most_watched_genres |
| int_genre_metrics | 멀티장르 unnest + 집계 | recent_ratio, popular_ratio |

### Mart Layer (비즈니스 질문 답변용)
| 모델 | 비즈니스 질문 | 핵심 KPI |
|---|---|---|
| mart_content_performance | "어떤 콘텐츠가 잘 되고 있나?" | performance_score, completion_rate, drop_rate |
| mart_user_segments | "어떤 유저가 있고 어떻게 행동하나?" | user_tier, rating_tendency, viewing_diversity |
| mart_genre_trends | "장르별 트렌드는?" | trend_category, genre_health_score |

## 4. 핵심 설계 결정 (EDA 기반)

| EDA 인사이트 | 모델링 결정 |
|---|---|
| Members 롱테일 (Gini 0.87) | members_tier 세그먼트 (Top 1%/5%/10%) |
| Score vs 완주율 강한 상관 | completion_rate, drop_rate를 핵심 KPI로 |
| 파워유저 1%가 9.2% ratings | user_tier (Power/Active/Regular/Casual) |
| IP기반 > 오리지널 점수 | source_category 파생 컬럼 |
| ONA 급성장 | is_digital_native 플래그 |
| Positivity Bias | high_rating_ratio, low_rating_ratio 추가 |

## 5. SQL 기법

- **윈도우 함수**: `PERCENT_RANK()` (members_tier, user_tier), `RANK()` (순위)
- **CTE 체이닝**: 모든 intermediate/mart 모델
- **CASE 분기**: source_category, rating_tendency, trend_category
- **LATERAL + UNNEST**: 멀티 장르 파싱 (genre_metrics, genre_trends)
- **FILTER 절**: 조건부 집계 (completion_rate, high_rating_ratio)

## 6. 데이터 품질 테스트

24개 테스트 전체 통과:
- `unique`: anime_id, user_id, genre (각 PK)
- `not_null`: 모든 PK + 필수 컬럼
- `accepted_values`: type, watching_status
