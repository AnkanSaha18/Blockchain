# DCBA Paper — Images Folder

This folder contains all figures referenced in main.tex.

## Figures Required

The following figures are currently marked as placeholders in the LaTeX
source. Add the corresponding image files here before final compilation.

### Figure 1: DCBA Dual-Chain Architecture Diagram
- **Filename:** `architecture.pdf` (or `.png`)
- **Reference in paper:** `\ref{fig:architecture}` (Section 3)
- **Suggested content:**
  - Left block: PDC (Ethereum PoA) with SC-1, SC-2, SC-3, SC-7
  - Centre: SC-7 Oracle Bridge with bidirectional arrows labelled "rxHash relay"
  - Right block: UOC (Hyperledger Fabric) with SC-4, SC-5, SC-6
  - Actors positioned around each chain
  - Use the report.html visual as reference

### Figure 2: End-to-End System Flow Sequence Diagram
- **Filename:** `flow.pdf` (or `.png`)
- **Reference in paper:** `\ref{fig:flow}` (Section 4)
- **Suggested content:**
  - UML-style sequence diagram
  - Actors as vertical lifelines: Patient, HP, SC3, SC7, SC5, DS, SC4, SC6
  - 9 numbered steps shown as horizontal arrows
  - Chain boundary crossing highlighted for SC-7 calls

## How to Include in LaTeX

Replace the `\fbox` placeholder blocks with:

```latex
\includegraphics[width=\columnwidth]{images/architecture.pdf}
```

or for two-column spanning figures:

```latex
\begin{figure*}
  \centering
  \includegraphics[width=\textwidth]{images/architecture.pdf}
  \caption{...}
\end{figure*}
```

## Tools for Creating Figures

- **draw.io** (diagrams.net) — recommended for architecture and flow diagrams
- **Lucidchart** — good for UML sequence diagrams
- **TikZ/PGF** — if you want diagrams directly in LaTeX (no external file needed)
- **Inkscape** — for vector graphics exported as PDF

Export all figures as **PDF** for best quality in LaTeX. PNG at 300 DPI
is acceptable as a fallback.
