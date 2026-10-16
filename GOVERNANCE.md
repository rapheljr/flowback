# Project Governance

This document describes how Flowback is governed, how decisions are made, and how contributors can participate in the project's direction.

---

## 1. Project Roles

### Project Lead & Creator
* Current Lead: **Abin Rapheal** ([@rapheljr](https://github.com/rapheljr))
* Responsible for overarching project vision, final architectural review, repository administrative settings, and signing releases.

### Maintainers
Maintainers are active contributors who have demonstrated consistent technical contributions, adherence to code quality and security standards, and constructive community participation. Maintainers have triage and commit access to the repository.

#### Maintainer Responsibilities
* Review and merge pull requests that pass CI and meet code guidelines.
* Triage incoming bug reports and feature proposals.
* Monitor security reports and collaborate on advisories.
* Keep documentation and dependency matrices up to date.

#### Becoming a Maintainer
New maintainers are nominated by an existing maintainer based on sustained contributions (code, code reviews, bug investigations, documentation improvements). Nominations are approved by consensus among active maintainers.

### Contributors
Anyone who submits issues, pull requests, documentation updates, or participates in discussions is a valued contributor.

---

## 2. Decision-Making Process

Flowback follows a consensus-seeking model:

1. **Informal Consensus:** Small bug fixes, documentation clarifications, and test enhancements can be approved and merged by any maintainer after automated CI checks pass.
2. **Substantial Features & Architectural Changes:**
   * Require an open GitHub Issue or RFC Discussion labeled `proposal`.
   * Must outline problem motivation, alternative approaches considered, privacy impact, and macOS permission implications.
   * Require review and sign-off by at least two maintainers (or the Project Lead if single maintainer).
3. **Breaking Changes:**
   * Breaking changes to the IPC protocol (`EVENT_PROTOCOL.md`), CLI command syntax, or public Swift APIs require advance discussion and must follow Semantic Versioning (incrementing the `MAJOR` version).
   * Deprecation notices must precede removal across at least one minor release cycle where feasible.

---

## 3. Release Approval

* Releases follow Semantic Versioning (`MAJOR.MINOR.PATCH`).
* Stable releases require passing full verification test suites, clean linting, artifact checksum validation, and verification on supported macOS versions.
* Release publication is initiated via git tags by the Project Lead or designated maintainers according to [RELEASE.md](RELEASE.md).

---

## 4. Conflict Resolution

* In the event of disagreements regarding technical direction or PR implementation, contributors and maintainers are encouraged to discuss trade-offs objectively using measurable criteria (performance, memory usage, privacy impact, backward compatibility).
* If a consensus cannot be reached, the Project Lead makes the final determination.

---

## 5. Inactive Maintenance & Succession

* If a maintainer becomes inactive for six months or longer without notice, their write permissions may be paused to maintain repository security hygiene.
* In the event the Project Lead steps down or is unable to continue, leadership will be transitioned to the most active maintainer selected by majority vote among active contributors.
