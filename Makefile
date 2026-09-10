SHELL := /bin/bash
CARGO ?= cargo
PYTHON ?= python3
REBAR3 ?= rebar3
MIX ?= mix
export MIX_REBAR3 := $(shell command -v $(REBAR3))
REFERENCE ?= receipts/reference-20260910T194106Z

.PHONY: build lint check reference otp-build otp-check ownership-check protocol-check receipt-check witness-check isolation-check elixir-build elixir-test elixir-check
build:
	$(CARGO) build --workspace --locked

lint:
	$(CARGO) fmt --all --check
	$(CARGO) clippy --workspace --all-targets --locked -- -D warnings
	$(PYTHON) -m py_compile experiments/gate_001/reference.py experiments/gate_001/check.py
	$(PYTHON) -m py_compile experiments/ownership_001/run.py experiments/ownership_001/protocol_check.py
	$(PYTHON) -m py_compile experiments/receipt_001/run.py
	$(PYTHON) -m py_compile experiments/witness_001/run.py
	$(PYTHON) -m py_compile experiments/isolation_001/run.py experiments/elixir_001/run.py experiments/ls_001/run.py

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

isolation-check: build otp-build
	$(PYTHON) experiments/isolation_001/run.py

elixir-build:
	cd elixir/pty_lab_ex && $(MIX) deps.get
	cd elixir/pty_lab_ex && $(MIX) compile --warnings-as-errors

elixir-test: elixir-build
	cd elixir/pty_lab_ex && $(MIX) format --check-formatted
	cd elixir/pty_lab_ex && $(MIX) test --warnings-as-errors

elixir-check: build elixir-build
	$(PYTHON) experiments/elixir_001/run.py

check: build
	$(PYTHON) experiments/gate_001/check.py "$(REFERENCE)"

reference: build
	$(PYTHON) experiments/gate_001/reference.py

.PHONY: ls-check
ls-check: build elixir-build
	$(PYTHON) experiments/ls_001/run.py
