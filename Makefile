# Flowback Universal macOS AI Agent Context & Focus Manager Makefile

.PHONY: all build release test clean package dmg install-cli lint website-dev website-build brand-assets verify-brand validate-version propose-version install-hooks help

all: build test

help:
	@echo "Flowback Build System"
	@echo "====================="
	@echo "make build            - Compile debug targets"
	@echo "make release          - Compile optimized release targets"
	@echo "make test             - Run full verification test suite"
	@echo "make package          - Package Flowback.app bundle"
	@echo "make dmg              - Build compressed Flowback.dmg installer"
	@echo "make manifest         - Generate release-manifest.json and SHA256SUMS"
	@echo "make validate-version - Validate canonical version synchronization"
	@echo "make propose-version  - Propose next version based on commit history"
	@echo "make install-hooks    - Install git pre-commit version validation hook"
	@echo "make install-cli      - Link flowback CLI to PATH"
	@echo "make lint             - Run SwiftLint checks"
	@echo "make website-dev      - Start local HTTP server for Website/"
	@echo "make website-build    - Validate website static assets and links"
	@echo "make brand-assets     - Regenerate all vector, PDF, PNG, and ICNS brand assets"
	@echo "make verify-brand     - Audit brand asset dimensions, geometry, and contrast"
	@echo "make clean            - Remove build artifacts and scratch databases"

brand-assets:
	swift Scripts/generate_brand_assets.swift

verify-brand:
	swift Scripts/verify_brand_assets.swift


build:
	swift build

release:
	bash Scripts/build.sh

test:
	swift run FlowbackTestRunner
	node Scripts/test_opencode_plugin.js

VERSION ?= $(shell cat VERSION 2>/dev/null || echo 0.4.0)
BUILD_NUMBER ?= $(shell cat BUILD 2>/dev/null || echo 1)

package: release
	bash Scripts/package_app.sh $(VERSION) $(BUILD_NUMBER) universal

dmg: package
	bash Scripts/create_dmg.sh Flowback-$(VERSION).dmg

manifest:
	bash Scripts/generate_manifest.sh $(VERSION)

cask:
	bash Scripts/generate_cask.sh $(VERSION)

artifacts:
	bash Scripts/package_release_artifacts.sh $(VERSION) universal

validate-version:
	bash Scripts/validate_version_sync.sh

propose-version:
	bash Scripts/propose_next_version.sh

validate: validate-version
	bash Scripts/validate_release.sh --local $(VERSION)

validate-release: validate-version
	bash Scripts/validate_release.sh --release $(VERSION)

install-cli:
	bash Scripts/install_cli.sh

install-hooks:
	bash Scripts/install_git_hooks.sh

lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint; \
	else \
		echo "swiftlint not installed locally. Run via CI or brew install swiftlint."; \
	fi

website-dev:
	@echo "Serving Website at http://localhost:8080..."
	python3 -m http.server 8080 --directory Website

website-build:
	bash Scripts/test_website.sh

clean:
	rm -rf .build dist release
	rm -f *.sqlite *.sqlite-wal *.sqlite-shm
