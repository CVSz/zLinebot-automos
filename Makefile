install:
	pip install -r backend/api/requirements.txt
	pip install -r backend/worker/requirements.txt
	cd frontend && npm install

lint:
	ruff check backend
	cd frontend && npm run build

test:
	pytest backend/api backend/worker
	cd frontend && npm run build

codemod:
	python scripts/codemods/fix_backend.py
	node scripts/codemods/fix_frontend.js

all: lint test codemod
