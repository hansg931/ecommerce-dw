# MAL Analytics Engineering — 프로젝트 상세 리포트

## 프로젝트 한 줄 요약

MyAnimeList 57M+ ratings 데이터에서 **5가지 데이터 문제를 발견**하고, 이를 해결하는 **3-Layer Data Warehouse**를 설계한 뒤, **Semantic Layer가 LLM Text-to-SQL 품질을 얼마나 개선하는지 정량적으로 검증**한 End-to-End Analytics Engineering 프로젝트.

---

## 1. 데이터에서 발견한 문제들

17,562개 애니메이션 × 310K 유저 × 57M 평점 데이터를 DuckDB로 탐색하면서 5가지 핵심 문제를 발견했다.

### 문제 1: 극단적 인기도 편중 (Gini 0.87)

```
상위 1% 작품(175개)이 전체 Members의 29%를 차지
상위 5% 작품(878개)이 전체 Members의 64.5%를 차지
Members 중앙값 2,065 vs 평균 34,659 — 17배 차이
```

단순 Members 수로는 작품 간 비교가 불가능했다. "Members 10만"이 어떤 의미인지 맥락 없이는 판단할 수 없었다.

**해결**: `PERCENT_RANK()` 윈도우 함수로 **members_tier** 5단계 세그먼트 도입

```sql
members_tier = CASE
  WHEN PERCENT_RANK() OVER (ORDER BY members) >= 0.99 THEN 'Top 1%'
  WHEN PERCENT_RANK() OVER (ORDER BY members) >= 0.95 THEN 'Top 5%'
  WHEN PERCENT_RANK() OVER (ORDER BY members) >= 0.90 THEN 'Top 10%'
  WHEN PERCENT_RANK() OVER (ORDER BY members) >= 0.50 THEN 'Upper Half'
  ELSE 'Lower Half'
END
```

→ "이 작품은 Top 5% 인기도"처럼 **상대적 위치**로 해석할 수 있게 되었다.

### 문제 2: 평점의 Positivity Bias

```
전체 평점 분포: 7-8점 구간에 48.5% 집중
1-5점: 전체의 10.6%에 불과
평균 7.51, 중앙값 8.0
```

원인: 시청을 **완료한 유저만** 평점을 남기는 자기 선택 편향(Self-Selection Bias). animelist.csv 분석 결과, Completed 상태의 84.6%가 평점을 남겼지만 Dropped는 45.6%만 남겼다.

**해결**: 평균 점수만으로는 품질 판단이 부정확하므로, **완주율(completion_rate)**과 **드롭률(drop_rate)**을 핵심 KPI로 도입

```sql
completion_rate = COUNT(*) FILTER (WHERE status_name = 'Completed')
                  / NULLIF(COUNT(*), 0)
drop_rate       = COUNT(*) FILTER (WHERE status_name = 'Dropped')
                  / NULLIF(COUNT(*), 0)
```

→ Score 8+ 작품의 평균 완주율 62% vs Score 4- 작품의 27%. **완주율이 점수보다 더 신뢰할 수 있는 품질 지표**임을 확인.

### 문제 3: 파워유저 편향

```
상위 1% 유저(3,100명): 평균 1,132+ ratings, 전체 rating의 9.2% 생성
파워유저 평균 평점: 6.86 (일반 유저 7.94 대비 1.08점 낮음)
```

소수의 파워유저가 데이터의 상당 부분을 차지하면서, 동시에 **일반 유저보다 13% 더 엄격하게** 평가했다. 유저를 구분하지 않으면 집계 결과가 파워유저 쪽으로 왜곡된다.

**해결**: **user_tier** 4단계 세그먼트 + **rating_tendency** 성향 분류

```sql
-- 유저 활동량 기반 티어
user_tier = CASE
  WHEN PERCENT_RANK() >= 0.99 THEN 'Power'    -- 상위 1%
  WHEN PERCENT_RANK() >= 0.90 THEN 'Active'   -- 상위 10%
  WHEN PERCENT_RANK() >= 0.50 THEN 'Regular'  -- 상위 50%
  ELSE 'Casual'
END

-- 평점 성향 분류
rating_tendency = CASE
  WHEN avg_rating >= 8.5 THEN 'Generous'
  WHEN avg_rating >= 7.0 THEN 'Moderate'
  WHEN avg_rating >= 5.5 THEN 'Critical'
  ELSE 'Very Critical'
END
```

→ "Power 유저의 평균 평점 vs Casual 유저의 평균 평점"처럼 **세그먼트별 분석**이 가능해졌다.

### 문제 4: IP 기반 작품과 오리지널의 성과 격차

```
Manga 원작:  평균 6.92, 3,413작품
Light Novel: 평균 7.06, 709작품
Original:    평균 6.25, 3,083작품
```

IP 기반 작품이 오리지널보다 평균 **0.7점 이상** 높았다. 콘텐츠 성과를 분석할 때 원작 유무를 고려하지 않으면 불공정한 비교가 된다. 네이버웹툰도 웹소설 IP → 웹툰 전환이 핵심 전략이므로, 이 구분이 비즈니스적으로 중요하다.

**해결**: `source_category` 파생 컬럼 (Staging 레이어에서 분류)

```sql
source_category = CASE
  WHEN source IN ('Manga', 'Light novel', 'Visual novel', ...) THEN 'IP-based'
  WHEN source = 'Original' THEN 'Original'
  ELSE 'Other-IP'
END
```

### 문제 5: ONA(웹 애니메이션) 급성장 트렌드

2015년 이전에는 거의 없던 ONA가 이후 급격히 증가. 디지털 네이티브 콘텐츠 형식의 성장을 포착하기 위한 별도 플래그가 필요했다.

**해결**: `is_digital_native` 불리언 플래그 + `mart_genre_trends`에서 **trend_category** 분류

```sql
-- 2015-2019 vs 2010-2014 비교
count_growth_rate = (recent_avg_count - prev_avg_count) / prev_avg_count

trend_category = CASE
  WHEN count_growth_rate > 0.30 THEN 'Growing'
  WHEN count_growth_rate < -0.20 THEN 'Declining'
  ELSE 'Stable'
END
```

---

## 2. Data Warehouse 설계

### 아키텍처: 3-Layer (dbt + DuckDB)

```
Raw CSV (5개)
  │
  ▼
Staging (4 Views) ─── 정제: snake_case, 타입 캐스팅, 파생 컬럼
  │
  ▼
Intermediate (3 Tables) ─── 조인, 집계, 세그먼트 산출
  │
  ▼
Marts (3 Tables) ─── 비즈니스 질문에 직접 답변하는 최종 테이블
```

### 핵심 SQL 기법

| 기법 | 사용 위치 | 목적 |
|------|-----------|------|
| `PERCENT_RANK()` 윈도우 함수 | int_anime_stats, int_user_profiles | members_tier, user_tier 산출 |
| `FILTER` 절 | int_anime_stats, int_user_profiles | 조건부 집계 (완주율, 고평점 비율 등) |
| `LATERAL + UNNEST` | int_genre_metrics, mart_genre_trends | 멀티 장르 파싱 (콤마 구분 → 행 분리) |
| CTE 체이닝 | 모든 intermediate/mart | 복잡 로직을 단계별로 분리 |
| 복합 스코어링 | mart_content_performance | `performance_score` 가중 합산 |
| `RANK()` 윈도우 함수 | mart_content_performance | 점수/인기도/완주율/참여도 순위 |

### 복합 성과 점수 (performance_score)

EDA에서 발견한 문제들을 반영한 가중치 설계:

```sql
performance_score =
    0.4 × (mal_score - 1.0) / 9.0           -- 점수 품질 (40%)
  + 0.3 × completion_rate                    -- 완주율 = 진짜 품질 (30%)
  + 0.2 × LN(members) / LN(max_members)     -- 인기도 로그 정규화 (20%)
  + 0.1 × (1.0 - drop_rate)                 -- 이탈 방지 (10%)
```

- **완주율에 30% 가중치**: Positivity Bias 문제(문제 2)로 점수만으론 부족
- **인기도 로그 변환**: 극단적 롱테일(문제 1)에서 선형 비교 불가능 → 로그 정규화
- **드롭률 역지표**: 높은 드롭률 = 낮은 품질

### 데이터 품질 테스트

24개 dbt 테스트 전체 통과:

- **unique**: anime_id, user_id, genre (각 테이블 PK)
- **not_null**: 모든 PK + 필수 비즈니스 컬럼
- **accepted_values**: type(TV/OVA/Movie/Special/ONA/Music), watching_status

---

## 3. Semantic Layer

**목적**: DW의 테이블/컬럼/지표를 **사람과 LLM이 모두 읽을 수 있는** 표준 정의로 문서화.

### 구성

| 파일 | 내용 | 항목 수 |
|------|------|---------|
| `table_definitions.yml` | 3개 mart 테이블의 전체 컬럼 정의 (한/영 병기) | 69개 컬럼 |
| `business_glossary.yml` | 비즈니스 용어 사전 | 16개 용어 |
| `metric_definitions.yml` | 지표 정의 (계산식, 단위, 벤치마크) | 16개 지표 |

### 핵심 용어 예시

| 용어 | 정의 | 계산식 | 벤치마크 |
|------|------|--------|----------|
| 완주율 | 콘텐츠 품질의 핵심 양(+)의 지표 | completed / total_list | ~0.55 |
| 드롭률 | 콘텐츠 유지력의 역(-)지표 | dropped / total_list | ~0.05 |
| 파워유저 | 상위 1% 활동량, 더 엄격한 평가 | PERCENT_RANK >= 0.99 | 1,132+ ratings |
| Positivity Bias | 7-8점 집중 현상 (자기 선택 편향) | — | 48.5% 집중 |

→ 이 정의가 LLM에게 `mal_score`와 `avg_rating`의 차이, `completion_rate`의 의미를 알려주는 핵심 컨텍스트가 된다.

---

## 4. Golden Dataset

### 설계

40개 자연어 질문을 5개 카테고리 × 3단계 난이도로 구성하고, 각 질문에 대해 DuckDB에서 실행 검증된 Golden SQL을 작성했다.

| 카테고리 | 질문 수 | 예시 |
|----------|---------|------|
| 콘텐츠 성과 | 10 | "완주율이 가장 높은 TV 애니메이션 상위 10개는?" |
| 유저 행동 | 10 | "파워유저의 평균 평점과 일반 유저의 평균 평점 차이는?" |
| 장르 분석 | 8 | "장르 건강도 점수 상위 10개 장르는?" |
| 트렌드 | 5 | "ONA 작품의 연도별 증가 추이는?" |
| 비교/복합 | 6 | "Manga 원작 vs Light Novel 원작 vs Original의 성과 비교" |

| 난이도 | 질문 수 | SQL 특징 |
|--------|---------|----------|
| Easy | 14 | 단일 테이블, 기본 집계, ORDER BY + LIMIT |
| Medium | 19 | 다중 조건 WHERE, GROUP BY + HAVING, 비교 쿼리 |
| Hard | 6 | 서브쿼리, UNNEST, 윈도우 함수, 시계열 집계 |

---

## 5. LLM Text-to-SQL 평가 — Semantic Layer의 효과 검증

### 실험 설계

같은 40개 질문을 **두 가지 조건**으로 Gemini API(gemini-3.1-flash-lite-preview)에 제공:

- **Baseline**: 테이블 스키마(컬럼명, 타입)만 제공
- **Full**: 스키마 + Semantic Layer(테이블 정의 + 용어 사전 + 지표 정의) 전체 제공

생성된 SQL을 DuckDB에서 실행하고, Golden Query 결과와 비교했다.

### 평가 지표

- **execution_success_rate**: 생성된 SQL이 에러 없이 실행되는 비율
- **result_match_rate**: 실행 결과가 Golden Query와 일치하는 비율 (행 수 + 공통 컬럼 값 비교, 수치 5% 오차 허용)

### 전체 결과

| 지표 | Baseline (스키마만) | Full (Semantic Layer) | 개선폭 |
|------|---------------------|----------------------|--------|
| **실행 성공률** | 94.9% (37/39) | **100.0%** (39/39) | **+5.1%p** |
| **결과 일치율** | 33.3% (13/39) | **41.0%** (16/39) | **+7.7%p** |

### 난이도별 결과

| 난이도 | Baseline 실행 | Full 실행 | Baseline 일치 | Full 일치 |
|--------|--------------|-----------|--------------|-----------|
| **Easy** (14) | 14/14 (100%) | 14/14 (100%) | 8/14 (57.1%) | **10/14 (71.4%)** |
| **Medium** (19) | 18/19 (94.7%) | **19/19 (100%)** | 4/19 (21.1%) | **5/19 (26.3%)** |
| **Hard** (6) | 5/6 (83.3%) | **6/6 (100%)** | 1/6 (16.7%) | 1/6 (16.7%) |

→ Semantic Layer는 **Easy 질문의 정확도를 57% → 71%로 크게 개선**하고, Medium/Hard에서는 **실행 에러를 제거**하는 효과가 있었다.

### 카테고리별 결과

| 카테고리 | Baseline 일치 | Full 일치 | 개선 |
|----------|-------------|-----------|------|
| 콘텐츠 성과 | 2/10 (20%) | **4/10 (40%)** | **+20%p** |
| 유저 행동 | 4/10 (40%) | 4/10 (40%) | 0 |
| 장르 분석 | 4/8 (50%) | **5/8 (62.5%)** | **+12.5%p** |
| 트렌드 | 1/5 (20%) | 1/5 (20%) | 0 |
| 비교/복합 | 2/6 (33.3%) | 2/6 (33.3%) | 0 |

→ **콘텐츠 성과(+20%p)**와 **장르 분석(+12.5%p)** 카테고리에서 가장 큰 효과.

### 케이스 스터디: Semantic Layer가 해결한 문제

#### Case 1 — 컬럼 선택 오류 수정 (CP01)

**질문**: "평균 점수가 가장 높은 애니메이션 상위 10개는?"

```sql
-- Baseline: avg_rating 사용 (유저 평균 평점)
SELECT name, avg_rating
FROM mart_content_performance ORDER BY avg_rating DESC LIMIT 10

-- Full: mal_score 사용 (MAL 공식 점수) ← 올바른 컬럼
SELECT name, mal_score
FROM mart_content_performance ORDER BY mal_score DESC LIMIT 10
```

**원인**: `mal_score`(MAL 공식 가중 평균)과 `avg_rating`(유저 평점 단순 평균)은 다른 지표. Semantic Layer의 컬럼 정의가 이 차이를 LLM에게 알려줌.

#### Case 2 — DuckDB 문법 에러 수정 (UB06)

**질문**: "드롭 성향이 'High Dropper'인 유저들이 가장 많이 시청한 장르는?"

```sql
-- Baseline: UNNEST를 SELECT에서 직접 사용 → DuckDB Binder Error
SELECT unnest(string_split(most_watched_genres, ', ')) AS genre, count(*)
FROM mart_user_segments WHERE drop_tendency = 'High Dropper'
GROUP BY 1

-- Full: UNNEST 없이 most_watched_genres 직접 GROUP BY ← 실행 성공
SELECT most_watched_genres, COUNT(*) as user_count
FROM mart_user_segments WHERE drop_tendency = 'High Dropper'
GROUP BY most_watched_genres ORDER BY user_count DESC LIMIT 1
```

**원인**: Semantic Layer에서 `most_watched_genres`가 "가장 많이 평가한 장르(단일 값)"임을 명시 → LLM이 불필요한 UNNEST를 생략.

#### Case 3 — 비즈니스 용어 이해 (GA08)

**질문**: "최근 비율(recent_ratio)이 50% 이상인 '신흥 장르'는?"

```sql
-- Baseline: 존재하지 않는 값으로 필터링 → 빈 결과
SELECT genre FROM mart_genre_trends
WHERE recent_ratio >= 0.5 AND trend_category = '신흥 장르'

-- Full: recent_ratio만으로 올바르게 필터링 ← 정확한 결과
SELECT genre FROM mart_genre_trends WHERE recent_ratio >= 0.5
```

**원인**: Baseline은 한국어 "신흥 장르"를 `trend_category` 컬럼의 값으로 오해. Semantic Layer에서 `trend_category`의 accepted_values가 Growing/Declining/Stable임을 명시 → 불필요한 필터 제거.

### Semantic Layer의 한계

**Medium/Hard 질문에서 효과 제한적인 이유:**

1. **복잡한 쿼리 구조**: LATERAL UNNEST, 시계열 GROUP BY, 서브쿼리 등은 "어떤 컬럼이 무엇인지"만으론 부족. **"어떻게 쿼리해야 하는지"**에 대한 가이드가 필요.
2. **다중 테이블 조인**: 비교/복합 카테고리(33.3%)에서 개선 없음. 테이블 간 관계와 조인 패턴에 대한 명시적 가이드가 필요.
3. **컬럼 선택 전략**: LLM이 "어떤 컬럼을 포함해야 하는지"를 판단하지 못하는 경우가 많았음 (9건).

→ **Semantic Layer는 "무엇(WHAT)"을 설명하는 데 효과적이지만, "어떻게(HOW)"까지 안내하려면 쿼리 패턴 예시나 조인 가이드가 추가로 필요하다.**

---

## 6. 프로젝트 수치 요약

| 항목 | 수치 |
|------|------|
| 원본 데이터 규모 | 17.5K anime, 310K users, 57M ratings, 109M list entries |
| dbt 모델 수 | 10개 (staging 4 + intermediate 3 + mart 3) |
| 데이터 품질 테스트 | 24개 전체 통과 |
| Semantic Layer 정의 | 69개 컬럼 + 16개 용어 + 16개 지표 |
| Golden Dataset | 40개 질문 + 39개 검증된 SQL |
| LLM 평가 | Semantic Layer로 실행 성공률 +5.1%p, 결과 일치율 +7.7%p 개선 |

## 기술 스택

DuckDB · dbt-core · dbt-duckdb · Python · Gemini API (google-genai)
