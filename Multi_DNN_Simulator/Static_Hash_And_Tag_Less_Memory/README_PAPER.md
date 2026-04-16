# Stamp-Based On-Chip Memory Management for DNN Accelerators
## IEEE Conference Paper - LaTeX Source Files

This directory contains the complete LaTeX source files for the research paper on stamp-based memory management for DNN accelerators.

## Files Included

- **stamp_paper.tex** - Main paper source (IEEE conference format, double-column)
- **references.bib** - BibTeX bibliography file with all citations
- **Makefile_paper** - Build system for compiling the paper
- **README_PAPER.md** - This file

## Building the Paper

### Prerequisites

You need a LaTeX distribution installed:
- **Linux:** `sudo apt-get install texlive-full`
- **Mac:** Install MacTeX from https://www.tug.org/mactex/
- **Windows:** Install MiKTeX from https://miktex.org/

### Quick Build

```bash
# Using make (recommended)
make -f Makefile_paper

# Or manually
pdflatex stamp_paper.tex
bibtex stamp_paper
pdflatex stamp_paper.tex
pdflatex stamp_paper.tex
```

The output will be `stamp_paper.pdf`.

### Makefile Targets

```bash
make -f Makefile_paper        # Build the PDF (default)
make -f Makefile_paper clean  # Remove generated files
make -f Makefile_paper view   # Open the PDF
make -f Makefile_paper help   # Show help
```

## Paper Structure

### Abstract
Brief overview of the problem, approach, and key results (83.6% bandwidth savings, 91.8% cycle reduction).

### I. Introduction
- Motivation: limitations of hash-based memory management
- Key insight: exploit predictable DNN execution patterns
- Contributions: compiler framework, hardware controller, validation

### II. Background and Related Work
- DNN accelerator architectures
- Memory management approaches
- Data reuse optimization
- Comparison with Eyeriss, SCNN, Gemmini

### III. Stamp-Based Memory Management
- System architecture
- Compiler framework (phase generation, stamp allocation, delta computation)
- Hardware implementation (controller FSM, operation execution)
- Resource comparison

### IV. Evaluation
- Experimental setup (4×4 systolic array, 16 KB scratchpad)
- Bandwidth reduction results (84% average)
- Latency analysis (12.8× speedup)
- Operation distribution (52% KEEP, 15% MOVE, 33% LOAD)
- Energy efficiency analysis
- Scalability study

### V. Discussion
- Comparison with prior work
- Limitations (dynamic networks, multi-tenancy)
- Extensions (inter-layer optimization, prefetching, compression)

### VI. Conclusion
Summary of contributions and future work

## Key Results

| Metric | Value | Improvement |
|--------|-------|-------------|
| Off-chip bandwidth | 16.4% of baseline | 83.6% reduction |
| Memory mgmt cycles | 8.2% of baseline | 91.8% reduction |
| Hardware logic | 70% of baseline | 30% reduction |
| Tile reuse | 67% average | Majority of operations |

## Customization

### Changing Conference Format

To adapt for different venues:

**Journal format (single column):**
```latex
\documentclass[journal]{IEEEtran}
```

**Transaction format:**
```latex
\documentclass[journal,twocolumn]{IEEEtran}
```

**Other conferences:**
Replace `\documentclass[conference]{IEEEtran}` with the appropriate class for your target venue (e.g., ACM sigconf, USENIX, etc.)

### Adding Figures

The paper currently uses ASCII art for diagrams. To add actual figures:

1. Create figure files (PDF, PNG, or EPS)
2. Place them in the same directory
3. Replace ASCII art sections with:

```latex
\begin{figure}[t]
\centering
\includegraphics[width=\columnwidth]{your_figure.pdf}
\caption{Your caption here}
\label{fig:your_label}
\end{figure}
```

### Adding Authors

Edit the author block:

```latex
\author{
\IEEEauthorblockN{First Author\IEEEauthorrefmark{1},
Second Author\IEEEauthorrefmark{2}}
\IEEEauthorblockA{\IEEEauthorrefmark{1}First Institution\\
Email: first@institution.edu}
\IEEEauthorblockA{\IEEEauthorrefmark{2}Second Institution\\
Email: second@institution.edu}
}
```

## Citations

All references are in `references.bib`. To add new citations:

1. Add entry to `references.bib`:
```bibtex
@inproceedings{key2024,
  title={Paper Title},
  author={Author Name},
  booktitle={Conference Name},
  year={2024}
}
```

2. Cite in paper:
```latex
Prior work~\cite{key2024} showed...
```

## Common Issues

### Missing Packages

If compilation fails with "File not found":
```bash
# Update package database
sudo tlmgr update --self
sudo tlmgr update --all
```

### BibTeX Errors

If references don't appear:
1. Ensure you run `bibtex` after first `pdflatex`
2. Run `pdflatex` twice more to resolve references
3. Check `.blg` file for errors

### Overfull hbox Warnings

These indicate text extending into margins. Usually harmless, but to fix:
- Rephrase sentences
- Add `\-` for hyphenation hints
- Use `\raggedright` in specific paragraphs

## Word Count

Approximate word count (excluding references):
```bash
make -f Makefile_paper wordcount
```

IEEE conference papers typically have 6-8 page limits, which translates to approximately 4000-5500 words.

## Submission Checklist

Before submitting:

- [ ] Compile without errors or warnings
- [ ] All references cited in text
- [ ] All figures have captions and labels
- [ ] Tables are properly formatted
- [ ] Author information updated (remove "Anonymous" for camera-ready)
- [ ] Copyright notice added (for camera-ready)
- [ ] PDF metadata correct
- [ ] Page limit satisfied
- [ ] Supplementary materials prepared (if applicable)

## Camera-Ready Modifications

For accepted papers, typical changes:

1. **Add copyright notice:**
```latex
\IEEEoverridecommandlockouts
\IEEEpubid{\makebox[\columnwidth]{978-x-xxxx-xxxx-x/26/\$31.00~\copyright~2026 IEEE \hfill} \hspace{\columnsep}\makebox[\columnwidth]{ }}
```

2. **Update author block** with real names and affiliations

3. **Add acknowledgments** (funding, reviewers, etc.)

4. **Ensure compliance** with page limits and formatting

## Converting to Other Formats

### To PDF/A (for archival):
```bash
gs -dPDFA -dBATCH -dNOPAUSE -sColorConversionStrategy=UseDeviceIndependentColor \
   -sDEVICE=pdfwrite -dPDFACompatibilityPolicy=1 \
   -sOutputFile=stamp_paper_pdfa.pdf stamp_paper.pdf
```

### To HTML (for web):
```bash
htlatex stamp_paper.tex
```

### To Word (if required):
```bash
pandoc stamp_paper.tex -o stamp_paper.docx --bibliography=references.bib
```

## License

This paper and its source files are provided for academic and research purposes.

## Contact

For questions about the paper or LaTeX source:
- Check build logs for compilation issues
- Refer to IEEE LaTeX guidelines: https://www.ieee.org/conferences/publishing/templates.html
- See IEEEtran documentation: http://www.ctan.org/pkg/ieeetran

## Version History

- v1.0 (Feb 2026): Initial submission version
- Camera-ready version: TBD

---

**Happy writing!** 📝
