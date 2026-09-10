SHELL := /bin/bash
CARGO ?= cargo
PYTHON ?= python3
REBAR3 ?= rebar3
REFERENCE ?= receipts/reference-20260910T194106Z

.PHONY: build lint check reference otp-build otp-check ownership-check protocol-check receipt-check witness-check
build:
	$(CARGO) build --workspace --locked

lint:
	$(CARGO) fmt --all --check
	$(CARGO) clippy --workspace --all-targets --locked -- -D warnings
	$(PYTHON) -m py_compile experiments/gate_001/reference.py experiments/gate_001/check.py
	$(PYTHON) -m py_compile experiments/ownership_001/run.py experiments/ownership_001/protocol_check.py
	$(PYTHON) -m py_compile experiments/receipt_001/run.py
	$(PYTHON) -m py_compile experiments/witness_001/run.py

otp-build:
	cd erlang/pty_lab && $(REBAR3) compile

otp-check: otp-build
	cd erlang/pty_lab && $(REBAR3) eunit
	cd erlang/pty_lab && $(REBAR3) xref

protocol-check: build
	$(PYTHON) experiments/ownership_001/protocol_check.py

ownership-check: build otp-build
	$(PYTHON) experiments/ownership_001/run.py

receipt-check: build otp-build
	$(PYTHON) experiments/receipt_001/run.py

witness-check: build otp-build
	$(PYTHON) experiments/witness_001/run.py

check: build
	$(PYTHON) experiments/gate_001/check.py "$(REFERENCE)"

reference: build
	$(PYTHON) experiments/gate_001/reference.py
