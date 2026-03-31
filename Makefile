.PHONY: run test evaluate all clean

run:
	cd dbt_project && poetry run dbt run

test:
	cd dbt_project && poetry run dbt test

evaluate:
	poetry run python golden_dataset/llm_evaluation/evaluate.py

all: run test evaluate

clean:
	cd dbt_project && poetry run dbt clean
