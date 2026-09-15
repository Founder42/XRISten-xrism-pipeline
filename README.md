# XRISten-xrism-pipeline: Intelligent & Automated Data Reduction Pipeline for XRISM/Resolve

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![HEASoft: >=6.34](https://img.shields.io/badge/HEASoft-%E2%89%A56.34-brightgreen.svg)](https://heasarc.gsfc.nasa.gov/lheasoft/)
[![Python: >=3.9](https://img.shields.io/badge/Python-%E2%89%A53.9-blue.svg)](https://www.python.org/)
[![Mission: JAXA/NASA XRISM](https://img.shields.io/badge/Mission-JAXA%20%2F%20NASA%20XRISM-purple.svg)](https://xrism.isas.jaxa.jp/)
[![Release: v1.0](https://img.shields.io/badge/Release-v1.0-orange.svg)](https://github.com/Founder42/XRISten-xrism-pipeline)

> **An astrophysics-grade, dual-track automation framework and AI Agent Copilot for the XRISM Resolve X-ray Microcalorimeter. Seamlessly operates both as a standalone headless Shell pipeline on compute clusters and as an intelligent conversational Copilot for modern AI coding agents.**

---

## Table of Contents
- [Overview](#overview)
- [Key Features & Architecture](#key-features--architecture)
- [Prerequisites & Environment](#prerequisites--environment)
- [Workflow Overview](#workflow-overview)
- [Usage Track 1: Standalone Shell Pipeline](#usage-track-1-standalone-shell-pipeline-xrism_rsl_pipelinesh)
  - [Command-Line Options](#command-line-options)
  - [Canonical Invocation Examples](#canonical-invocation-examples)
- [Usage Track 2: Interactive AI Copilot](#usage-track-2-interactive-ai-copilot-xristen-skill)
  - [Skill Integration](#skill-integration)
  - [Agent Interaction Examples](#agent-interaction-examples)
- [Repository Structure](#repository-structure)
- [Quality Assurance & Audit Logging](#quality-assurance--audit-logging)
- [Acknowledgments & Inspiration](#acknowledgments--inspiration)
- [Citation & Contact](#citation--contact)

---

## Overview

The **XRISM (X-ray Imaging and Spectroscopy Mission)** Resolve instrument is a revolutionary cryogenic 36-pixel microcalorimeter array delivering unprecedented non-dispersive spectral resolution (~5 eV FWHM across 0.3–12 keV). However, producing science-ready spectra requires navigating complex multi-stage reduction: electrical crosstalk screening, rise-time derivative filtering, geomagnetic cut-off rigidity (`CORTIME`) optimization, non-interactive `xselect` extractions, XL-size response matrix generation (`rslmkrmf`), raytracing ARF calculations (`xaarfgen`), and background estimation with matched NXB RMF calibration.

**XRISten-xrism-pipeline** addresses these challenges by offering a **Dual-Track Operational Paradigm**:
1. **Track 1: Standalone Modular Pipeline (`xrism_rsl_pipeline.sh`)**  
   A modern, production-hardened Bash pipeline designed for deterministic, headless execution on HPC clusters and remote servers. It features strict execution safety (`set -euo pipefail`), automated environment pre-checks, multi-threshold `CORTIME` loops, and unified audit logging. It requires zero AI infrastructure and runs purely on HEASoft.
2. **Track 2: Interactive AI Copilot (`XRISten` Skill v1.0)**  
   An AI Agent Skill compatible with modern agentic development environments (e.g. Antigravity, OpenClaw, Aider, Claude Code). The agent converses with the astrophysicist in natural language to deduce science intent, validate parameter keys, and synthesize exact CLI commands for the user to copy-paste—strictly enforcing **non-execution by default** to preserve researcher oversight.

---

## Key Features & Architecture

```text
                                  +-----------------------+
                                  |   Raw XRISM Data      |
                                  +-----------+-----------+
                                              |
                     +------------------------+------------------------+
                     |                                                 |
         [ Track 1: Standalone CLI ]                       [ Track 2: AI Copilot ]
      ./xrism_rsl_pipeline.sh -o <OBSID>                "Extract spectra for Mrk 3..."
                     |                                                 |
                     v                                                 v
           Environment Validation                             Intent Recognition
          (HEADAS, CALDB, Astropy)                         & Parameter Elicitation
                     |                                                 |
                     v                                                 v
          Pre-reduction (xapipeline)                          Formatted CLI Command
                     |                                      (Copy-ready, No auto-run)
                     v                                                 |
         Pulse-Shape Screening (cl2.evt)                               |
                     |                                                 |
                     v                                                 |
       +-----------------------------+                                 |
       | Multi-CORTIME Loop (4, 6, 8)|                                 |
       +--------------+--------------+                                 |
                      |                                                |
                      +---> Branching Ratios (rslbratios)              |
                      +---> Automated xselect (DET Image, LC)          |
                      +---> Hp Grade-0 Spectrum Extraction             |
                      +---> XL-Size Source RMF (rslmkrmf)              |
                      +---> Point-Source ARF (xaarfgen)                |
                      +---> NXB Spectrum & Calibrated NXB RMF          |
                      |                                                |
                      v                                                v
            [ Science-Ready Products ] <-------------------------------+
           (*.pha, *.rmf, *.arf, *.nxb)
```

- **Robust Execution Safety**: Implements `set -euo pipefail`, defensive variable quoting, and automated validation of `$HEADAS` and `$CALDB`.
- **CORTIME Exposure Optimization**: Enables multi-threshold screening (e.g. `-c "4,6"`) in a single pass to evaluate continuum shape consistency and maximize effective observation time.
- **Headless `xselect` Automation**: Replaces interactive terminal prompts with clean heredoc injections (`<<EOF`).
- **Standardized Detector Geometry**: Automatically generates 34-pixel region files (`region_no12_no27.reg`), isolating science pixels from calibration pixel 12 and noisy pixel 27.
- **Calibrated NXB RMF Protocol**: Proactively regenerates custom background response matrices whenever non-standard `CORTIME` cuts (e.g. `< 6`) are applied.

---

## Prerequisites & Environment

Before executing the pipeline or invoking the agent commands, ensure the host analysis node meets the following requirements:

### 1. HEASoft & XRISM Mission Packages
HEASoft version **6.34 or later** is required, built with XRISM mission packages (`xapipeline`, `rslmkrmf`, `xaarfgen`, `rslnxbgen`, `xselect`, `ftcopy`, `maketime`, `extractor`, `coordpnt`, `fkeyprint`).

Initialize HEASoft in your shell:
```bash
export HEADAS=/path/to/heasoft-6.34/x86_64-apple-darwin... # or Linux platform
source $HEADAS/headas-init.sh
```

### 2. CALDB (Calibration Database)
Ensure `$CALDB` points to the latest index containing XRISM Resolve calibration files:
```bash
export CALDB=/path/to/caldb
source $CALDB/software/tools/caldbinit.sh
```

### 3. Non-X-ray Background (NXB) Database
Download the pre-compiled Resolve NXB database (required for `rslnxbgen`):
```bash
# Example path
export NXB_DIR=/path/to/xrism/resolve/nxb
```

### 4. Python Environment
Python 3.9+ with `astropy` installed (used for high-precision celestial coordinate calculations and pointing updates):
```bash
pip install astropy
```

---

## Workflow Overview

The pipeline executes the reduction through 11 modular stages:

| Stage | Step Name | Operation & Tool | Outputs / Deliverables |
| :--- | :--- | :--- | :--- |
| **0** | Environment Check | Validates `$HEADAS`, `$CALDB`, astropy, tools | Pre-flight confirmation |
| **1** | Calibration & Reprocessing | Run `xapipeline` on raw observation directory | Cleaned event files (`*cl2.evt`) |
| **2** | Pulse-Shape Screening | Rise-time filter (`rslpulsefit`, `maketime`) | Filtered event file `rsl_p0px1000_cl2.evt` |
| **3** | Observation Metadata Extraction | `fkeyprint` & coordinate resolution (`coordpnt`) | Target RA/Dec, Roll angle, Pointing |
| **4** | Detector Region Staging | Generate 34-pixel circular exclusion region | `region_no12_no27.reg` (Excludes px 12 & 27) |
| **5** | CORTIME Screening Loop | Apply cut-off rigidity thresholds (e.g. 4, 6) | `rsl_cor<N>_evt.fits` |
| **6** | Branching Ratios Calculation | Run `rslbratios` on screened event file | High-resolution branching ratio table |
| **7** | Science Spectrum Extraction | Headless `xselect` (Hp grade 0, 34-pixel filter) | Science source spectrum (`*src_cor<N>.pha`) |
| **8** | XL-Size Source RMF Generation | Run `rslmkrmf` (`resol=XL`, `quickrmf=no`) | Full-resolution response matrix (`*.rmf`) |
| **9** | Point-Source ARF Calculation | Run `xaarfgen` raytracing calculation | Effective area curve (`*.arf`) |
| **10**| Calibrated NXB Background | Run `rslnxbgen` & regenerate custom NXB RMF | Background spectrum (`*.nxb`) & RMF |

---

## Usage Track 1: Standalone Shell Pipeline (`xrism_rsl_pipeline.sh`)

### Command-Line Options

```text
Usage: ./xrism_rsl_pipeline.sh -o <OBSID> [OPTIONS]

Required Parameters:
  -o <OBSID>          9-digit XRISM observation ID (e.g. 201007010).

Optional Parameters:
  -s <SOURCE_NAME>    Target source name (default: same as OBSID).
  -r <RA>             Target celestial Right Ascension in decimal degrees.
  -d <DEC>            Target celestial Declination in decimal degrees.
  -c <CORTIME>        Cut-off rigidity threshold(s). Can be a single value or
                      comma-separated list, e.g. "4.0" or "4,6" (default: "4.0").
  -m <MODE>           Execution mode: "all" or comma-separated steps
                      (e.g. "prepare,screen_risetime,cutoff_rigidity,chk_event").
                      (default: "all").
  -i <RAWDATA_DIR>    Base directory containing raw observation data (default: ".").
                      The pipeline accesses raw data at "<RAWDATA_DIR>/<OBSID>",
                      creates reprocessed repository at "<RAWDATA_DIR>/<OBSID>_repo",
                      and analysis workspace at "<RAWDATA_DIR>/<OBSID>_analysis".
  -b <NXB_DIR>        Directory of XRISM NXB database (default: "$XRISM_NXB_DB" or "/path/to/XRISM_NXB_DB").
  -x <RDETX0>         Nominal detector X center (default: 3.5).
  -y <RDETY0>         Nominal detector Y center (default: 3.5).
  -h                  Show this help message and exit.

Available Step Names for -m:
  prepare             Create analysis directory, link files, inspect headers.
  screen_risetime     Execute pulse-shape and rise-time screening (cl2.evt).
  cutoff_rigidity     Apply CORTIME filtering for each specified threshold.
  chk_event           Compute branching ratios, DET image, and light curve.
  extract_spec        Extract Resolve Hp grade-0 spectrum.
  generate_rmf        Create UPR file and generate XL-size RMF.
  generate_arf        Verify coordinates, compute exposure map, and generate ARF.
  generate_NXB        Generate NXB spectrum, image, and custom NXB RMF.
```

### Examples

#### 1. Run all steps with raw data at /path/to/rawdata/201007010:
  ```bash
  ./xrism_rsl_pipeline.sh -o 201007010 -s Mrk3 -i /path/to/rawdata -r 93.901482 -d 71.037482 -b /path/to/XRISM_NXB_DB
  ```

#### 2. Run multi-threshold CORTIME comparison (4 and 6):
  ```bash
  ./xrism_rsl_pipeline.sh -o 201007010 -s Mrk3 -i /path/to/rawdata -c "4,6" -b /path/to/XRISM_NXB_DB
  ```

#### 3. Run specific steps only from any directory:
  ```bash
  ./xrism_rsl_pipeline.sh -o 201007010 -s Mrk3 -i /path/to/rawdata -m "cutoff_rigidity,extract_spec" -c "4,6"
  ```

---

## Usage Track 2: Interactive AI Copilot (XRISten Skill)

The **XRISten Skill (v1.0)** equips your AI coding agent to serve as an intelligent pair-programmer for XRISM reductions.

### Skill Integration

#### Antigravity / Gemini CLI
Deploy the skill globally or project-locally:
- **Global**: Copy `skills/XRISten/` to `~/.gemini/antigravity-cli/skills/XRISten/` or `~/.gemini/config/skills/XRISten/`.
- **Project-Level**: Place in `.agents/skills/XRISten/` within your workspace root.

#### OpenClaw / Aider / Claude Code
Reference `skills/XRISten/SKILL.md` directly in your agent system prompt or context rules:
```text
@skills/XRISten/SKILL.md
```

### Agent Interaction Examples

```text
User   > Please help me reduce the raw XRISM observation for target Mrk 3 with OBSID 201007010.

Agent  > I am XRISten (v1.0), your assistant for XRISM Resolve data reduction powered by
         xrism_rsl_pipeline.sh.
         
         To construct your pipeline command, could you please confirm:
         1. Target coordinates (RA/Dec)? (Default: read from FITS header)
         2. CORTIME threshold? (Default: 4.0; or '4,6' for comparison)
         3. Path to your NXB Database directory?

User   > RA is 93.901482, Dec is 71.037482. Let's compare CORTIME 4 and 6. 
         NXB path is /data/caldb/xrism_nxb.

Agent  > Here is your complete reduction command. Copy and run this on your analysis server:

         ```bash
         ./xrism_rsl_pipeline.sh              -o 201007010              -s Mrk3              -r 93.901482              -d 71.037482              -c "4,6"              -b /data/caldb/xrism_nxb
         ```

         This will stage Mrk3_analysis/, run rise-time screening, and independently generate
         COR4 and COR6 spectra, XL-size RMFs, ARFs, and calibrated NXB files.
```

---

## Repository Structure

```text
XRISten-xrism-pipeline/
├── README.md                          # Primary project documentation (this file)
├── LICENSE                            # MIT Open-Source License
├── .gitignore                         # Strict exclusion for FITS, EVT, RMF, ARF data
├── xrism_rsl_pipeline.sh              # Standalone production pipeline executable
└── skills/
    └── XRISten/
        ├── SKILL.md                   # AI Agent Copilot specification (v1.0)
        ├── scripts/
        │   └── xrism_rsl_pipeline.sh  # Bundled executable inside skill package
        └── resources/
            ├── no27.reg               # 34-pixel Resolve detector region definition
            └── reduction_log_template.md # Markdown audit log template
```

---

## Quality Assurance & Audit Logging

Every execution of `xrism_rsl_pipeline.sh` automatically records an audit trail into:
```text
${OBSID}_analysis/pipeline_audit.log
```
This log timestamps all stage transitions, executed commands, and parameter configurations to ensure full scientific reproducibility.

---

## Acknowledgments & Inspiration

This project was inspired by and builds upon the foundational XRISM Resolve reduction procedures documented by **Yerong Xu** in [`XRISM-data-reduction`](https://github.com/yrxu/XRISM-data-reduction/tree/main). We gratefully acknowledge their valuable contributions to the XRISM observational astrophysics and open-source software community.

---

## Citation & Contact

If you utilize **XRISten-xrism-pipeline** in astronomical data analysis leading to publications, please cite this repository:

```bibtex
@software{xristen_pipeline_2026,
  author       = {Fangzheng, Shi},
  title        = {{XRISten-xrism-pipeline}: Automated Reduction Pipeline and AI Copilot for XRISM/Resolve},
  year         = {2026},
  publisher    = {GitHub},
  version      = {v1.0},
  howpublished = {\url{https://github.com/Founder42/XRISten-xrism-pipeline}}
}
```

For scientific inquiries, feature requests, or bug reports, please open an Issue or Pull Request on GitHub.
