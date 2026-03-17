# MAL Analytics Engineering Project

MyAnimeList(MAL) 공개 데이터셋을 활용한 콘텐츠 플랫폼 Data Warehouse 설계 + LLM Golden Dataset 구축 프로젝트.

## Quick Start

```bash
# 환경 설정
poetry install

# dbt 실행
cd dbt_project
poetry run dbt run --profiles-dir .
poetry run dbt test --profiles-dir .

# LLM 평가 (Gemini API 키 필요)
GEMINI_API_KEY=your_key poetry run python golden_dataset/llm_evaluation/evaluate.py
```

## 프로젝트 구조

```
├── data/raw/                    # MAL 원본 CSV (57M+ ratings)
├── notebooks/                   # EDA 노트북 3개
│   ├── 01_eda_anime.ipynb       # 메타데이터 분석
│   ├── 02_eda_ratings.ipynb     # 평점/인터랙션 분석
│   └── 03_eda_reviews.ipynb     # 시놉시스 텍스트 분석
├── dbt_project/                 # dbt + DuckDB DW
│   └── models/
│       ├── staging/             # raw → 정제 (4 views)
│       ├── intermediate/        # 조인/집계 (3 tables)
│       └── marts/               # 비즈니스 테이블 (3 tables)
├── semantic_layer/              # 테이블/용어/지표 정의
├── golden_dataset/              # 40개 질문 + Golden SQL + LLM 평가
└── docs/                        # 설계 문서
```

## 기술 스택

DuckDB · dbt-core · Python · Gemini API

## 데이터셋

[MyAnimeList Recommendation Database 2020](https://www.kaggle.com/datasets/hernan4444/anime-recommendation-database-2020) — 17,562 anime, 310K users, 57M ratings
