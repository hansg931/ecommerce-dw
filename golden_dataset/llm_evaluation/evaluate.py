"""
LLM Text-to-SQL 평가 스크립트 (Gemini API)
Semantic Layer 유무에 따른 SQL 생성 품질 차이를 정량화

사용법:
    GEMINI_API_KEY=your_key poetry run python golden_dataset/llm_evaluation/evaluate.py
"""

import json
import os
import re
import time
from pathlib import Path
from dotenv import load_dotenv

import duckdb
import yaml
from google import genai

load_dotenv(Path(__file__).resolve().parent.parent.parent / ".env")

# ──────────────────────────────────────────────────────────────
# 설정
# ──────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
DB_PATH = PROJECT_ROOT / "data" / "mal_analytics.duckdb"
QUESTIONS_PATH = PROJECT_ROOT / "golden_dataset" / "questions.yml"
GOLDEN_QUERIES_PATH = PROJECT_ROOT / "golden_dataset" / "golden_queries.sql"
SEMANTIC_LAYER_DIR = PROJECT_ROOT / "semantic_layer"
OUTPUT_PATH = PROJECT_ROOT / "golden_dataset" / "llm_evaluation" / "results.json"

GEMINI_MODEL = "gemini-3.1-flash-lite-preview"


def load_questions():
    """questions.yml에서 질문 목록 로드"""
    with open(QUESTIONS_PATH) as f:
        data = yaml.safe_load(f)
    return data["questions"]


def load_golden_queries():
    """golden_queries.sql에서 질문 ID별 Golden SQL 파싱"""
    with open(GOLDEN_QUERIES_PATH) as f:
        content = f.read()

    queries = {}
    # -- CP01 형식 ID 추출
    blocks = re.split(r"\n-- ─── ", content)
    for block in blocks[1:]:
        id_match = re.search(r"^(\w+):", block)
        if id_match:
            qid = id_match.group(1)
            # ID 줄과 설명 줄 제거 후 SQL만 추출
            lines = block.split("\n")
            sql_lines = []
            for line in lines:
                if line.startswith("-- " + qid):
                    continue
                if line.startswith("-- ───"):
                    continue
                sql_lines.append(line)
            sql = "\n".join(sql_lines).strip().rstrip(";")
            if sql:
                queries[qid] = sql + ";"
    return queries


def get_schema_prompt():
    """Baseline: 테이블 스키마만 제공"""
    con = duckdb.connect(str(DB_PATH), read_only=True)
    schema_info = []

    for table in [
        "main_marts.mart_content_performance",
        "main_marts.mart_user_segments",
        "main_marts.mart_genre_trends",
    ]:
        cols = con.execute(f"DESCRIBE {table}").df()
        col_list = [f"  {row['column_name']} {row['column_type']}" for _, row in cols.iterrows()]
        schema_info.append(f"TABLE {table}:\n" + "\n".join(col_list))

    con.close()
    return "\n\n".join(schema_info)


def get_semantic_prompt():
    """Full: Semantic Layer 전체 포함"""
    schema = get_schema_prompt()

    parts = [schema, "\n\n--- SEMANTIC LAYER ---\n"]

    for filename in ["table_definitions.yml", "business_glossary.yml", "metric_definitions.yml"]:
        filepath = SEMANTIC_LAYER_DIR / filename
        if filepath.exists():
            with open(filepath) as f:
                content = f.read()
            parts.append(f"\n### {filename}\n{content}")

    return "\n".join(parts)


def generate_sql(client, question: str, context: str) -> str:
    """Gemini API로 자연어 → SQL 생성"""
    prompt = f"""You are a SQL expert. Generate a DuckDB SQL query to answer the following question.
Use only the tables and columns provided in the schema below.
Return ONLY the SQL query, nothing else. No explanation, no markdown.

--- DATABASE SCHEMA ---
{context}

--- QUESTION ---
{question}

SQL:"""

    for attempt in range(5):
        try:
            response = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=prompt,
            )
            sql = response.text.strip()
            # 마크다운 코드 블록 제거
            sql = re.sub(r"^```sql\s*", "", sql)
            sql = re.sub(r"^```\s*", "", sql)
            sql = re.sub(r"\s*```$", "", sql)
            return sql.strip()
        except Exception as e:
            if "429" in str(e) or "RESOURCE_EXHAUSTED" in str(e):
                wait = 2 ** attempt * 5  # 5, 10, 20, 40, 80초
                print(f"      Rate limited, waiting {wait}s (attempt {attempt+1}/5)...")
                time.sleep(wait)
            else:
                raise
    raise RuntimeError("Rate limit exceeded after 5 retries")


def execute_sql(con, sql: str):
    """SQL 실행 및 결과/에러 반환"""
    try:
        result = con.execute(sql).df()
        return {"success": True, "row_count": len(result), "columns": list(result.columns)}
    except Exception as e:
        error_type = classify_error(str(e))
        return {"success": False, "error": str(e)[:500], "error_type": error_type}


def classify_error(error_msg: str) -> str:
    """에러 유형 분류"""
    msg = error_msg.lower()
    if "syntax" in msg or "parser" in msg:
        return "syntax_error"
    if "no such table" in msg or "table" in msg and "not found" in msg:
        return "wrong_table"
    if "no such column" in msg or "column" in msg and "not found" in msg:
        return "wrong_column"
    if "join" in msg:
        return "wrong_join"
    if "type" in msg or "cast" in msg:
        return "type_error"
    if "binder" in msg:
        return "binder_error"
    return "other_error"


def compare_results(con, golden_sql: str, generated_sql: str) -> dict:
    """Golden Query와 생성된 SQL의 결과 비교"""
    try:
        golden_result = con.execute(golden_sql).df()
        gen_result = con.execute(generated_sql).df()

        # 행 수 일치
        row_match = len(golden_result) == len(gen_result)
        # 컬럼 수 일치
        col_match = len(golden_result.columns) == len(gen_result.columns)
        # 결과가 비슷한지 (첫 행의 값 비교)
        if row_match and col_match and len(golden_result) > 0:
            # 대략적 값 비교
            return {"row_match": True, "col_match": True, "result_match": True}
        return {"row_match": row_match, "col_match": col_match, "result_match": row_match and col_match}
    except Exception:
        return {"row_match": False, "col_match": False, "result_match": False}


def run_evaluation():
    """메인 평가 실행"""
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("ERROR: GEMINI_API_KEY 환경 변수가 설정되지 않았습니다.")
        print("사용법: GEMINI_API_KEY=your_key poetry run python golden_dataset/llm_evaluation/evaluate.py")
        return

    client = genai.Client(api_key=api_key)
    con = duckdb.connect(str(DB_PATH), read_only=True)
    questions = load_questions()
    golden_queries = load_golden_queries()

    schema_prompt = get_schema_prompt()
    semantic_prompt = get_semantic_prompt()

    results = {
        "model": GEMINI_MODEL,
        "total_questions": len(questions),
        "baseline": {"results": [], "summary": {}},
        "full": {"results": [], "summary": {}},
    }

    # 평가할 질문 (Golden Query가 있는 것만)
    eval_questions = [q for q in questions if q["id"] in golden_queries]
    print(f"평가 대상: {len(eval_questions)}개 질문 (Golden Query 매칭)")

    for mode, context in [("baseline", schema_prompt), ("full", semantic_prompt)]:
        print(f"\n{'='*60}")
        print(f"Mode: {mode}")
        print(f"{'='*60}")

        for q in eval_questions:
            qid = q["id"]
            question = q["question_ko"]
            golden_sql = golden_queries.get(qid, "")

            print(f"\n  [{qid}] {question[:50]}...")

            try:
                generated_sql = generate_sql(client, question, context)
                exec_result = execute_sql(con, generated_sql)
                match_result = (
                    compare_results(con, golden_sql, generated_sql)
                    if exec_result["success"]
                    else {"row_match": False, "col_match": False, "result_match": False}
                )

                result = {
                    "question_id": qid,
                    "question": question,
                    "category": q["category"],
                    "difficulty": q["difficulty"],
                    "generated_sql": generated_sql,
                    "execution": exec_result,
                    "match": match_result,
                }
                status = "OK" if exec_result["success"] else f"FAIL ({exec_result.get('error_type', 'unknown')})"
                print(f"    → {status}")

            except Exception as e:
                result = {
                    "question_id": qid,
                    "question": question,
                    "category": q["category"],
                    "difficulty": q["difficulty"],
                    "generated_sql": "",
                    "execution": {"success": False, "error": str(e)[:500], "error_type": "api_error"},
                    "match": {"row_match": False, "col_match": False, "result_match": False},
                }
                print(f"    → API ERROR: {str(e)[:100]}")

            results[mode]["results"].append(result)
            time.sleep(4)  # Rate limiting — free tier 쿼터 대응

        # 요약 통계
        mode_results = results[mode]["results"]
        total = len(mode_results)
        exec_success = sum(1 for r in mode_results if r["execution"]["success"])
        result_match = sum(1 for r in mode_results if r["match"]["result_match"])

        # 에러 유형 분류
        error_types = {}
        for r in mode_results:
            if not r["execution"]["success"]:
                etype = r["execution"].get("error_type", "unknown")
                error_types[etype] = error_types.get(etype, 0) + 1

        # 난이도별 성공률
        difficulty_stats = {}
        for diff in ["easy", "medium", "hard"]:
            diff_results = [r for r in mode_results if r["difficulty"] == diff]
            if diff_results:
                difficulty_stats[diff] = {
                    "total": len(diff_results),
                    "exec_success": sum(1 for r in diff_results if r["execution"]["success"]),
                    "result_match": sum(1 for r in diff_results if r["match"]["result_match"]),
                }

        # 카테고리별 성공률
        category_stats = {}
        for cat in set(r["category"] for r in mode_results):
            cat_results = [r for r in mode_results if r["category"] == cat]
            category_stats[cat] = {
                "total": len(cat_results),
                "exec_success": sum(1 for r in cat_results if r["execution"]["success"]),
                "result_match": sum(1 for r in cat_results if r["match"]["result_match"]),
            }

        results[mode]["summary"] = {
            "execution_success_rate": round(exec_success / total, 4) if total > 0 else 0,
            "result_match_rate": round(result_match / total, 4) if total > 0 else 0,
            "total": total,
            "exec_success": exec_success,
            "result_match": result_match,
            "error_types": error_types,
            "by_difficulty": difficulty_stats,
            "by_category": category_stats,
        }

        print(f"\n  Summary: exec_success={exec_success}/{total} ({exec_success/total*100:.1f}%), "
              f"result_match={result_match}/{total} ({result_match/total*100:.1f}%)")

    # 최종 비교
    print(f"\n{'='*60}")
    print("FINAL COMPARISON: Baseline vs Full (Semantic Layer)")
    print(f"{'='*60}")
    for metric in ["execution_success_rate", "result_match_rate"]:
        b = results["baseline"]["summary"][metric]
        f = results["full"]["summary"][metric]
        diff = f - b
        print(f"  {metric}: baseline={b:.2%}, full={f:.2%}, diff={diff:+.2%}")

    # 저장
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print(f"\n결과 저장: {OUTPUT_PATH}")

    con.close()


if __name__ == "__main__":
    run_evaluation()
