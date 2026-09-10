SHELL := /bin/bash
CARGO ?= cargo
PYTHON ?= python3
REFERENCE ?= receipts/reference-20260910T194106Z

.PHONY: build lint check reference
build:
	$(CARGO) build --workspace --locked

lint:
	$(CARGO) fmt --all --check
	$(CARGO) clippy --workspace --all-targets --locked -- -D warnings
	$(PYTHON) -m py_compile experiments/gate_001/reference.py experiments/gate_001/check.py

check: build
	$(PYTHON) experiments/gate_001/check.py "$(REFERENCE)"

reference: build
	$(PYTHON) experiments/gate_001/reference.py
