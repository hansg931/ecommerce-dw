# 프로젝트 요약 — MAL Analytics Engineering

## 프로젝트 목표

MyAnimeList 공개 데이터셋(57M+ ratings)을 활용하여 콘텐츠 플랫폼의 Data Warehouse를 설계하고, LLM Data Agent용 Golden Dataset을 구축하는 End-to-End Analytics Engineering 프로젝트.

## 기술 스택

- **DW 엔진**: DuckDB (로컬, 대용량 CSV 직접 처리)
- **모델링**: dbt-core + dbt-duckdb (3-Layer: staging → intermediate → mart)
- **EDA**: Python + DuckDB + seaborn/matplotlib (nbclient 세션 기반)
- **LLM 검증**: Gemini API (Text-to-SQL 품질 평가)

## 핵심 성과

### 1. Data Warehouse (10개 dbt 모델, 24개 테스트 전체 통과)
- **Staging**: 4개 소스 CSV → snake_case, 타입 캐스팅, 파생 컬럼
- **Intermediate**: 작품 통계, 유저 프로필, 장르 메트릭 (57M+ rows 처리)
- **Mart**: 콘텐츠 성과, 유저 세그먼트, 장르 트렌드 (3개 비즈니스 테이블)

### 2. 핵심 SQL 기법
- 윈도우 함수: `PERCENT_RANK()`, `RANK()`, `ROW_NUMBER()`
- CTE 체이닝: 모든 intermediate/mart 모델
- LATERAL + UNNEST: 멀티 장르 파싱
- FILTER 절: 조건부 집계 (완주율, 드롭률, 고평점 비율)

### 3. EDA 인사이트 (5개 핵심 → 모델링 방향 결정)
1. **극단적 롱테일**: Members Gini 0.87, 상위 1%가 29% 차지 → members_tier 도입
2. **완주율 = 품질 KPI**: Score↔Completion 강한 양의 상관 → performance_score 설계
3. **파워유저 편향**: 상위 1% 유저가 9.2% ratings, 더 엄격한 평가 → user_tier 세그먼트
4. **IP 기반 우위**: Manga 원작(7.0) > Original(6.3) → source_category 파생
5. **ONA 급성장**: 디지털 네이티브 콘텐츠 트렌드 → is_digital_native 플래그

### 4. Semantic Layer (3개 정의 파일)
- 테이블/컬럼 정의: 한국어+영어 병기, LLM 판독 가능
- 비즈니스 용어 사전: 완주율, 드롭률, 파워유저, Positivity Bias 등
- 지표 정의: 계산식, 단위, 벤치마크 포함

### 5. Golden Dataset (40개 질문 + SQL)
- 5개 카테고리: 콘텐츠 성과, 유저 행동, 장르 분석, 트렌드, 비교
- 난이도 3단계: Easy/Medium/Hard
- 전체 DuckDB 실행 검증 완료

### 6. LLM Text-to-SQL 평가 프레임워크
- Baseline: 스키마만 제공 vs Full: Semantic Layer 포함
- 지표: execution_success_rate, result_match_rate
- 에러 패턴 분류: syntax_error, wrong_table, wrong_column 등

## 네이버웹툰 JD 매핑

| JD 업무 | 프로젝트 대응 |
|---|---|
| DW 모델링 실습 | 3-Layer dbt 모델 (staging/intermediate/mart) |
| Semantic Layer 구축 | table_definitions + business_glossary + metric_definitions |
| Golden Dataset 구축 | 40개 질문 + Golden SQL + 실행 검증 |
| LLM Data Agent 품질 | Gemini API Text-to-SQL 평가 (Semantic Layer 유무 비교) |
