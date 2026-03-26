# DCBA Research Paper — LaTeX Source

## Files

| File | Description |
|------|-------------|
| `main.tex` | Main paper source (ACM SIGPLAN format) |
| `references.bib` | BibTeX bibliography (20 citations) |
| `images/` | Folder for external image files (currently empty — all figures are TikZ/pgfplots inline) |

## Compilation

### Overleaf (Recommended)
1. Create a new project → Upload Files
2. Upload `main.tex` and `references.bib`
3. Create an `images/` folder (Upload → Create Folder)
4. Set **Main Document** to `main.tex`
5. Set **Compiler** to `pdfLaTeX`
6. Click **Recompile**

### Local (requires TeX Live or MiKTeX)
```bash
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

## Required LaTeX Packages
All packages are available in TeX Live 2023+ and on Overleaf:
- `acmart` (ACM class — already on Overleaf)
- `algorithm`, `algpseudocode`
- `booktabs`, `multirow`
- `pgfplots`, `tikz` (with libraries: shapes.geometric, arrows.meta, positioning, fit, backgrounds)
- `listings`
- `amsmath`, `amssymb`
- `microtype`

## Before Submission — Replace Placeholders

Search for `PLACEHOLDER` and `XXXXXXX` in `main.tex`:

| Placeholder | Replace with |
|-------------|--------------|
| `\acmConference[PLACEHOLDER]{...}` | Actual conference name, dates, location |
| `\acmDOI{XXXXXXX.XXXXXXX}` | DOI assigned by ACM after acceptance |
| `\acmISBN{978-1-4503-XXXX-X/26/XX}` | ISBN from rights form |
| Author email `ankan@student.buet.ac.bd` | Actual email |
| `\setcopyright{rightsretained}` | Copyright from ACM rights form |

## For Review Submission
Change the first line to:
```latex
\documentclass[sigplan,review,anonymous]{acmart}
```
This produces single-column anonymous format required by most ACM venues.

## Paper Structure

| Section | Focus | ~Pages |
|---------|-------|--------|
| Abstract | Problem, approach, key numbers | 0.2 |
| §1 Introduction | Motivation, C1–C6 contributions | 0.8 |
| §2 Background & Related Work | 6 gaps table | 0.8 |
| §3 System Architecture | Dual-chain design, actors, SCs | 1.5 |
| §4 Core Mechanisms | DCS + PARS (with formulas), hardware ID, oracle | 2.0 |
| §5 Security Analysis | Threat model, 10-attack table | 1.2 |
| §6 Evaluation | Gas, Caliper, DCS scalability, security tests | 1.5 |
| §7 Discussion | TPS context, PARS limitations, oracle risk | 0.5 |
| §8 Conclusion | Summary + future work | 0.5 |
| References | 20 citations | 0.5 |

**Estimated total: ~9.5 pages** in ACM SIGPLAN two-column format.

## Key Numbers (do not change without re-running experiments)

| Claim | Value | Source |
|-------|-------|--------|
| Tests passing | 86/86 | Hardhat test suite |
| DCS 100-UAV time | 8.37 ms | Python fleet_sim.py threading |
| Caliper total txns | 244 | benchmark/benchmark.yaml |
| Caliper failures | 0 | Caliper report |
| Invoke TPS | 4.4–4.6 | Caliper (single-node Raft) |
| Query TPS | 20.4 | Caliper |
| Highest gas | 369,599 (SC5.submitOrder) | hardhat-gas-reporter |
| Security attacks blocked | 10/10 | test/Security.test.js |
| Oracle relay latency | 16 ms (local) | bridge.js instrumentation |

## PARS Formula Added (C5 fix)
The original proposal did not include a formal PARS score calculation.
The paper adds Equation (2):
```
P = floor(100 * I_u * (1 + alpha * T_f + beta * R_f))
```
where I_u is the clinical urgency indicator (0.90/0.75/0.55/0.30),
T_f is the therapeutic time-sensitivity factor, R_f is the route-delay penalty,
alpha=0.07, beta=0.03.

## Implementation Mismatches Resolved

| Issue | Resolution in Paper |
|-------|---------------------|
| PARS score calculation missing | Added Eq. (2) with formal four-factor rubric |
| SC-4/5/6 listed as .sol but are Go chaincode | Paper correctly describes UOC contracts as Fabric Go chaincode |
| Caliper 4.4 TPS seems low | §7 Discussion explicitly contextualises as single-node prototype; cites Thakkar et al. 3500 TPS |
| DCS 8.37ms is Python simulation | §6 and §7 clearly state "Python threading" and note on-chain submission latency is separate |
| Oracle 16ms vs 5.4s discrepancy | §4.4 distinguishes "16ms local relay" vs "~5.4s cross-host" explicitly |
