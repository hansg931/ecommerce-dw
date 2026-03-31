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

생성된 SQL을 DuckDB에서 실행하고, Golden Query 결과와 3단계로 비교했다.

### 평가 지표

- **execution_success_rate**: 생성된 SQL이 에러 없이 실행되는 비율
- **structure_match_rate**: 행 수 + 컬럼 수가 Golden Query와 정확히 일치
- **result_match_rate**: 공통 컬럼 기준 정렬 후 50%+ 행의 값이 일치 ← **핵심 지표**

> **메트릭 설계 노트**: 평가 과정에서 `full_match_rate > result_match_rate`라는 논리적 불일치를 발견했다. 원인은 두 지표가 서로 다른 조건을 독립적으로 평가했기 때문. 메트릭 계층을 재설계(structure_match → result_match 순서로 엄격도 증가)하고 전체 재실행했다.

### 전체 결과

| 지표 | Baseline (스키마만) | Full (Semantic Layer) | 차이 |
|------|---------------------|----------------------|------|
| **실행 성공률** | 100.0% (40/40) | 100.0% (40/40) | 0%p |
| **구조 일치율** | 7.5% (3/40) | 5.0% (2/40) | -2.5%p |
| **결과 일치율** | **50.0%** (20/40) | **50.0%** (20/40) | **0%p** |

**핵심 발견**: Semantic Layer가 result_match_rate를 개선하지 못했다. 개선된 케이스 +3건, 퇴보한 케이스 -3건으로 정확히 상쇄되었다.

### 난이도별 결과

| 난이도 | Baseline 결과 일치 | Full 결과 일치 | 차이 |
|--------|-------------------|----------------|------|
| **Easy** (14) | 9/14 (64.3%) | 9/14 (64.3%) | 0%p |
| **Medium** (19) | 10/19 (52.6%) | 10/19 (52.6%) | 0%p |
| **Hard** (7) | 1/7 (14.3%) | 1/7 (14.3%) | 0%p |

### 카테고리별 결과

| 카테고리 | Baseline 일치 | Full 일치 | 차이 |
|----------|-------------|-----------|------|
| 콘텐츠 성과 | 5/10 (50%) | 5/10 (50%) | 0%p |
| 유저 행동 | 5/10 (50%) | 4/10 (40%) | **-10%p** |
| 장르 분석 | 6/8 (75%) | 7/8 (87.5%) | **+12.5%p** |
| 트렌드 | 2/5 (40%) | 1/5 (20%) | **-20%p** |
| 비교/복합 | 2/7 (28.6%) | 3/7 (42.9%) | **+14.3%p** |

→ 장르 분석·비교 카테고리에서 개선되었지만, 유저 행동·트렌드에서 동등하게 퇴보했다.

### 케이스 스터디

#### Case A — Semantic Layer가 효과적인 경우: 동음이의 컬럼 (CP01)

**질문**: "평균 점수가 가장 높은 애니메이션 상위 10개는?"

```sql
-- Baseline: avg_rating 사용 (유저 평점 단순 평균) → Golden과 불일치
SELECT name, avg_rating
FROM mart_content_performance ORDER BY avg_rating DESC LIMIT 10;

-- Full: mal_score 사용 (MAL 공식 가중 평균) ← Golden과 일치
SELECT name, mal_score
FROM mart_content_performance ORDER BY mal_score DESC LIMIT 10;
```

`mal_score`(공식 가중 평균)와 `avg_rating`(단순 평균)은 다른 값을 반환한다. 컬럼명만으로 구별이 어려운 경우 Semantic Layer가 명확한 효과를 보였다.

#### Case B — Semantic Layer가 효과적인 경우: 한국어 용어 매핑 (GA08)

**질문**: "최근 비율(recent_ratio)이 50% 이상인 '신흥 장르'는?"

```sql
-- Baseline: '신흥 장르'를 trend_category 컬럼의 값으로 오해 → 빈 결과
SELECT genre FROM mart_genre_trends
WHERE recent_ratio >= 0.5 AND trend_category = '신흥 장르';

-- Full: recent_ratio 조건만으로 올바르게 필터링 ← Golden과 일치
SELECT genre FROM mart_genre_trends WHERE recent_ratio >= 0.5;
```

Semantic Layer에서 `trend_category`의 accepted_values가 'Growing/Declining/Stable'임을 명시하여 잘못된 필터를 방지했다.

#### Case C — Semantic Layer가 오히려 방해가 되는 경우: 과잉 명세 (CP06)

**질문**: "Members가 10만 이상인 인기작 중 드롭률이 10% 이상인 작품은?"

```sql
-- Baseline: name만 반환 → Golden과 일치
SELECT name FROM mart_content_performance
WHERE members >= 100000 AND drop_rate >= 0.1;

-- Full: Semantic Layer를 참고해 컬럼을 추가 반환 → Golden과 불일치
SELECT name, members, drop_rate FROM mart_content_performance
WHERE members >= 100000 AND drop_rate >= 0.1;
```

Semantic Layer의 컬럼 설명이 LLM으로 하여금 "유용한 컬럼을 추가 반환"하도록 유도했고, 이것이 exact match를 깼다.

#### Case D — Semantic Layer가 오히려 방해가 되는 경우: accepted_values 과잉 필터 (UB03)

**질문**: "평점 성향별(Generous/Moderate/Critical) 유저 수와 비율은?"

```sql
-- Baseline: 전체 데이터 집계 → Golden과 일치
SELECT rating_tendency, COUNT(*) AS user_count,
       COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS user_percentage
FROM mart_user_segments GROUP BY rating_tendency;

-- Full: accepted_values 참조로 불필요한 WHERE 추가 → 행 수 변경으로 불일치
SELECT rating_tendency, COUNT(*) AS user_count,
       COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS user_percentage
FROM mart_user_segments
WHERE rating_tendency IN ('Generous', 'Moderate', 'Critical')
GROUP BY rating_tendency;
```

Semantic Layer가 `accepted_values`를 명시함으로써 LLM이 불필요한 필터를 추가했다.

### 발견: 구조 일치율이 낮은 이유

structure_match_rate가 7.5%에 불과한 것은 LLM이 "틀린 쿼리"를 작성해서가 아니다. 실제로 result_match_rate가 50%인 케이스 대부분(17/20)이 structure_match=False였다 — 즉, **LLM은 질문에 올바르게 답하지만 Golden Query와 다른 컬럼 조합을 선택**한다.

이는 Golden Query 설계의 문제이기도 하다: Golden Query가 최소 필요 컬럼만 반환하는 반면, LLM은 "도움이 될 것 같은" 추가 컬럼을 포함하는 경향이 있다. Text-to-SQL 평가에서 exact schema match보다 **결과값 일치**를 핵심 지표로 삼아야 한다는 설계 원칙을 확인했다.

### 결론: Semantic Layer의 효과 조건

| 조건 | Semantic Layer 효과 |
|------|---------------------|
| 컬럼명이 모호하거나 동음이의어가 있을 때 | **효과 있음** (CP01) |
| 한국어/비즈니스 용어를 컬럼 값으로 매핑해야 할 때 | **효과 있음** (GA08) |
| 컬럼명이 이미 의미를 충분히 전달할 때 | **효과 없음** |
| accepted_values 명시가 불필요한 필터를 유도할 때 | **역효과** (UB03) |
| 컬럼 설명이 LLM의 SELECT 범위를 확장할 때 | **역효과** (CP06) |

→ **잘 설계된 mart 컬럼명은 그 자체가 Semantic Layer다.** `completion_rate`, `drop_rate`, `avg_rating`처럼 명확한 이름을 가진 컬럼에서는 Semantic Layer의 한계 기여(marginal value)가 0에 수렴했다. Semantic Layer의 효과는 스키마 설계의 품질에 반비례한다.

---

## 6. 프로젝트 수치 요약

| 항목 | 수치 |
|------|------|
| 원본 데이터 규모 | 17.5K anime, 310K users, 57M ratings, 109M list entries |
| dbt 모델 수 | 10개 (staging 4 + intermediate 3 + mart 3) |
| 데이터 품질 테스트 | 30개 전체 통과 |
| Semantic Layer 정의 | 74개 컬럼 + 16개 용어 + 13개 지표 |
| Golden Dataset | 40개 질문 + 40개 검증된 SQL |
| LLM 평가 | 실행 성공률 100% / 결과 일치율 50% (Baseline = Full) |

## 기술 스택

DuckDB · dbt-core · dbt-duckdb · Python · Gemini API (google-genai)
