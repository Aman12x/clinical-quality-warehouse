PY := .venv/bin/python
DBT := cd dbt && ../.venv/bin/dbt

.PHONY: setup data load build reconcile model all

setup:
	uv venv -p 3.12 .venv && uv pip install -p .venv -r requirements.txt

# 1,171-patient Synthea sample (used by CI); `make generate` builds the larger population
data:
	mkdir -p data/raw && curl -sL -o data/sample.zip https://synthetichealth.github.io/synthea-sample-data/downloads/synthea_sample_data_csv_apr2020.zip && unzip -o -q data/sample.zip -d data/raw

generate:
	mkdir -p tools && curl -sL -o tools/synthea.jar https://github.com/synthetichealth/synthea/releases/download/v3.0.0/synthea-with-dependencies.jar
	java -jar tools/synthea.jar -p 5000 -s 42 -cs 42 --exporter.csv.export=true --exporter.fhir.export=false \
	  --exporter.hospital.fhir.export=false --exporter.practitioner.fhir.export=false \
	  --exporter.baseDirectory=data/synthea_out Massachusetts

load:
	$(PY) scripts/load_raw.py

build:
	$(DBT) build --profiles-dir .

reconcile:
	$(PY) scripts/reconcile.py

model:
	$(PY) scripts/train_readmission.py

all: load build reconcile model
