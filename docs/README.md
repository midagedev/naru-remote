# Documentation

The repository root holds what a reader or a contributor needs first: the
[README](../README.md), [CONTRIBUTING](../CONTRIBUTING.md),
[SECURITY](../SECURITY.md), the working queue in
[NEXT_STEPS.md](../NEXT_STEPS.md), and the two agent entry points
([CLAUDE.md](../CLAUDE.md), [AGENTS.md](../AGENTS.md)). Everything else is here.

## Product

| Document | What it is |
| --- | --- |
| [PRODUCT_SPEC.md](PRODUCT_SPEC.md) | The product specification — what Naru Remote is for and where its boundaries are. Korean. |
| [BRANDING.md](BRANDING.md) | Name, voice, palette, and the usage rules the UI is reviewed against. Korean. |
| [PRODUCT_QUALITY_TARGETS.md](PRODUCT_QUALITY_TARGETS.md) | The numeric bars a release has to clear, and what "green" means for each. Korean. |
| [ROADMAP.md](ROADMAP.md) | How the product was built, phase by phase. **Not** feature status and **not** the queue — see the table at its head. |

## Engineering

| Document | What it is |
| --- | --- |
| [SPEC_DRIVEN_DEVELOPMENT.md](SPEC_DRIVEN_DEVELOPMENT.md) | How a change gets from an observation to a landed commit through `specs/`. |
| [AGENTIC_DEVELOPMENT_METHODOLOGY.md](AGENTIC_DEVELOPMENT_METHODOLOGY.md) | How this codebase is developed with AI agents — the delegation rules, the gates, and the incidents each rule came from. Korean. |
| [PERFORMANCE_PARITY_ANALYSIS.md](PERFORMANCE_PARITY_ANALYSIS.md) | Why the frame rate is what it is. Point-in-time analysis; the Apple VNC server's produce rate is the ceiling. Korean. |
| [runbooks/](runbooks/) | Step-by-step operational procedures, starting with [shipping to TestFlight](runbooks/testflight-release.md). |
| [store-screenshots.md](store-screenshots.md) | How the App Store captures are produced. |

## Records

These are dated snapshots, kept because the reasoning is worth more than the
tidiness. They describe a moment, not the present.

| Document | What it is |
| --- | --- |
| [release/](release/) | The run-up to the first App Store submission — listing copy, submission checklist, launch kit. All `1.0.0 (build 1)`, all carrying a banner saying so. |
| [research/](research/) | Investigations that fed a decision. |

Feature-level truth lives in `specs/<n>-<slug>/spec.md` — each carries a
**Status** line, and each records not only what was fixed but why the existing
gates could not catch it.

## A note on language

The engineering and product documents are largely Korean, because that is the
language they were thought in. The reader-facing surface — README,
CONTRIBUTING, SECURITY, the specs under `specs/`, and every code comment — is
English. Making the rest bilingual is a queued item, not an oversight; it is
tracked in `NEXT_STEPS.md`.
