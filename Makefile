# Flowback Universal macOS AI Agent Context & Focus Manager Makefile

.PHONY: all build release test clean package dmg install-cli lint website-dev website-build brand-assets verify-brand help

all: build test

help:
	@echo "Flowback Build System"
	@echo "====================="
	@echo "make build         - Compile debug targets"
	@echo "make release       - Compile optimized release targets"
	@echo "make test          - Run full verification test suite (125 tests)"
	@echo "make package       - Package Flowback.app bundle"
	@echo "make dmg           - Build compressed Flowback.dmg installer"
	@echo "make manifest      - Generate release-manifest.json and SHA256SUMS"
	@echo "make install-cli   - Link flowback CLI to PATH"
	@echo "make lint          - Run SwiftLint checks"
	@echo "make website-dev   - Start local HTTP server for Website/"
	@echo "make website-build - Validate website static assets and links"
	@echo "make brand-assets  - Regenerate all vector, PDF, PNG, and ICNS brand assets"
	@echo "make verify-brand  - Audit brand asset dimensions, geometry, and contrast"
	@echo "make clean         - Remove build artifacts and scratch databases"

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

package: release
	bash Scripts/package_app.sh 1.0.0 1 universal

dmg: package
	bash Scripts/create_dmg.sh Flowback-1.0.0.dmg

manifest:
	bash Scripts/generate_manifest.sh 1.0.0

cask:
	bash Scripts/generate_cask.sh 1.0.0

artifacts:
	bash Scripts/package_release_artifacts.sh 1.0.0 universal

validate:
	bash Scripts/validate_release.sh --local 1.0.0

validate-release:
	bash Scripts/validate_release.sh --release 1.0.0

install-cli:
	bash Scripts/install_cli.sh

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
