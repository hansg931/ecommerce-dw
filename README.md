# MAL Analytics Engineering Project

MyAnimeList 57M+ ratings 데이터를 활용한 콘텐츠 플랫폼 **Data Warehouse 설계** + **LLM Text-to-SQL Golden Dataset** 구축 프로젝트.

## 핵심 결과

- **EDA에서 5가지 데이터 문제 발견** → DW 모델링 방향 결정
  - 인기도 편중 (Gini 0.87), Positivity Bias (7-8점 48.5%), 파워유저 편향 (1%가 9.2%), IP > 오리지널 (+0.7점), ONA 급성장
- **10개 dbt 모델** (3-Layer), 24개 테스트 전체 통과
- **Semantic Layer가 LLM SQL 생성 품질을 개선**: 실행 성공률 94.9% → **100%**, 결과 일치율 33.3% → **41.0%**

## 프로젝트 구조

```
├── notebooks/                   # Phase 1: EDA (DuckDB로 57M rows 직접 분석)
│   ├── 01_eda_anime.ipynb       # 메타데이터 — 롱테일, 장르, 스튜디오
│   ├── 02_eda_ratings.ipynb     # 57M 평점 — 스파시티, 파워유저, Positivity Bias
│   └── 03_eda_reviews.ipynb     # 시놉시스 텍스트 분석
├── dbt_project/                 # Phase 2: DW 모델링
│   └── models/
│       ├── staging/             # 4 views — 정제, 타입 캐스팅, 파생 컬럼
│       ├── intermediate/        # 3 tables — 조인, 집계, 세그먼트 산출
│       └── marts/               # 3 tables — 비즈니스 질문 답변용
├── semantic_layer/              # Phase 3: 테이블/용어/지표 정의 (한/영 병기)
├── golden_dataset/              # Phase 3: 40개 질문 + Golden SQL
│   └── llm_evaluation/          # Phase 4: Gemini API 평가 결과
└── docs/                        # 설계 문서 + 프로젝트 상세 리포트
```

## Quick Start

```bash
poetry install

# dbt 실행
cd dbt_project
poetry run dbt run --profiles-dir .
poetry run dbt test --profiles-dir .

# LLM 평가 (Gemini API 키 필요)
GEMINI_API_KEY=your_key poetry run python golden_dataset/llm_evaluation/evaluate.py
```

## EDA → 모델링 결정 흐름

| 발견한 문제 | 해결 | 적용 위치 |
|-------------|------|-----------|
| Members Gini 0.87 (극단적 롱테일) | `PERCENT_RANK()` → members_tier 5단계 | int_anime_stats |
| 7-8점 48.5% 집중 (Positivity Bias) | 완주율/드롭률을 핵심 KPI로 도입 | int_anime_stats |
| 파워유저 1%가 ratings 9.2% 차지 | user_tier 4단계 + rating_tendency 분류 | int_user_profiles |
| IP 기반 작품 > 오리지널 (+0.7점) | source_category 파생 컬럼 | stg_anime |
| ONA 2015년 이후 급성장 | is_digital_native + trend_category | stg_anime, mart_genre_trends |

## LLM 평가 결과 (Gemini 3.1 Flash Lite Preview)

| 지표 | Baseline (스키마만) | Full (+ Semantic Layer) | 개선 |
|------|---------------------|------------------------|------|
| 실행 성공률 | 94.9% | **100.0%** | +5.1%p |
| 결과 일치율 | 33.3% | **41.0%** | +7.7%p |

→ 상세 분석: [`docs/project_summary.md`](docs/project_summary.md)

## 기술 스택

DuckDB · dbt-core · dbt-duckdb · Python · Gemini API

## 데이터셋

[MyAnimeList Recommendation Database 2020](https://www.kaggle.com/datasets/hernan4444/anime-recommendation-database-2020) — 17,562 anime, 310K users, 57M ratings
