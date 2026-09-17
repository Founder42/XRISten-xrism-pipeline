#!/usr/bin/env bash
# ==============================================================================
# Pipeline: xrism_rsl_pipeline.sh
# Purpose : Modular, robust, and parameterized reduction pipeline for XRISM Resolve
# Author  : Logos (Antigravity Assistant) for Dr. Fangzheng
# Version : 1.0.0
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Color formatting and Logging Setup
# ------------------------------------------------------------------------------
RED="[0;31m"
GREEN="[0;32m"
YELLOW="[1;33m"
CYAN="[0;36m"
NC="[0m" # No Color

log_info()    { echo -e "${CYAN}[INFO] $(date "+%Y-%m-%d %H:%M:%S")${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS] $(date "+%Y-%m-%d %H:%M:%S")${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN] $(date "+%Y-%m-%d %H:%M:%S")${NC} $*" >&2; }
log_error()   { echo -e "${RED}[ERROR] $(date "+%Y-%m-%d %H:%M:%S")${NC} $*" >&2; }

log_audit() {
    local log_file="${AUDIT_LOG:-pipeline_audit.log}"
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $*" >> "${log_file}"
}

# ------------------------------------------------------------------------------
# 2. Environment & Dependency Verification
# ------------------------------------------------------------------------------
check_environment() {
    log_info "Verifying execution environment and software dependencies..."
    
    if [[ -z "${HEADAS:-}" ]]; then
        log_error "Environment variable HEADAS is not set. Please initialize HEASoft (e.g. source \$HEADAS/headas-init.sh)."
        exit 1
    fi

    if [[ -z "${CALDB:-}" ]]; then
        log_error "Environment variable CALDB is not set. Please initialize CALDB (e.g. source \$CALDB/caldbinit.sh)."
        exit 1
    fi

    local required_cmds=(
        "ftcopy" "maketime" "extractor" "xselect" "rslmkrmf" 
        "rslbratios" "xaexpmap" "xaarfgen" "rslnxbgen" "coordpnt" 
        "fkeyprint" "punlearn"
    )

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_error "Required command '${cmd}' is not found in PATH. Please verify HEASoft installation."
            exit 1
        fi
    done

    # Verify Python interpreter with astropy and numpy
    PYTHON_BIN=""
    for cand in "${PYTHON:-}" "python3" "python" "/Users/fangzheng42/anaconda3/bin/python3" "/Users/fangzheng42/anaconda3/bin/python"; do
        if [[ -n "${cand}" ]] && command -v "${cand}" >/dev/null 2>&1; then
            if "${cand}" -c "import astropy.io.fits, numpy" >/dev/null 2>&1; then
                PYTHON_BIN="${cand}"
                break
            fi
        fi
    done

    if [[ -z "${PYTHON_BIN}" ]]; then
        log_error "Python interpreter with 'astropy' and 'numpy' is required but not found."
        log_error "Please ensure astropy and numpy are installed in your Python/conda environment."
        exit 1
    fi
    
    log_success "Environment validation passed. HEADAS and CALDB are active (Python: ${PYTHON_BIN})."
}

# ------------------------------------------------------------------------------
# 3. Helper Functions
# ------------------------------------------------------------------------------
get_fits_keyword() {
    local fits_file="$1"
    local keyword="$2"
    local py_bin="${PYTHON_BIN:-python3}"
    
    "${py_bin}" -c "
import sys
from astropy.io import fits

file_path = '$fits_file'
kw = '$keyword'
try:
    with fits.open(file_path) as hdul:
        for hdu in hdul:
            if kw in hdu.header:
                print(hdu.header[kw])
                sys.exit(0)
        print('')
except Exception as e:
    sys.exit(1)
"
}

create_region_files() {
    local out_dir="${1:-.}"
    local reg_no12="${out_dir}/region_no12.reg"
    local reg_no12_no27="${out_dir}/region_no12_no27.reg"

    if [[ -s "${reg_no12_no27}" ]]; then
        log_info "Region file '${reg_no12_no27}' already exists. Skipping."
        return 0
    fi

    log_info "Generating Resolve detector pixel region files in '${out_dir}'..."
    cat << 'EOF' > "${reg_no12}"
# Region file format: DS9 version 4.1
box(4,3,1,1,0)  # pixel 0
box(6,3,1,1,0)  # pixel 1
box(5,3,1,1,0)  # pixel 2
box(6,2,1,1,0)  # pixel 3
box(5,2,1,1,0)  # pixel 4
box(6,1,1,1,0)  # pixel 5
box(5,1,1,1,0)  # pixel 6
box(4,2,1,1,0)  # pixel 7
box(4,1,1,1,0)  # pixel 8
box(1,3,1,1,0)  # pixel 9
box(2,3,1,1,0)  # pixel 10
box(1,2,1,1,0)  # pixel 11
box(2,2,1,1,0)  # pixel 13
box(2,1,1,1,0)  # pixel 14
box(3,2,1,1,0)  # pixel 15
box(3,1,1,1,0)  # pixel 16
box(3,3,1,1,0)  # pixel 17
box(3,4,1,1,0)  # pixel 18
box(1,4,1,1,0)  # pixel 19
box(2,4,1,1,0)  # pixel 20
box(1,5,1,1,0)  # pixel 21
box(2,5,1,1,0)  # pixel 22
box(1,6,1,1,0)  # pixel 23
box(2,6,1,1,0)  # pixel 24
box(3,5,1,1,0)  # pixel 25
box(3,6,1,1,0)  # pixel 26
box(6,4,1,1,0)  # pixel 27
box(5,4,1,1,0)  # pixel 28
box(6,5,1,1,0)  # pixel 29
box(6,6,1,1,0)  # pixel 30
box(5,5,1,1,0)  # pixel 31
box(5,6,1,1,0)  # pixel 32
box(4,5,1,1,0)  # pixel 33
box(4,6,1,1,0)  # pixel 34
box(4,4,1,1,0)  # pixel 35
EOF

    # Filter out pixel 27 (leaving 34 active science pixels)
    grep -v 'pixel 27' "${reg_no12}" > "${reg_no12_no27}"
    log_success "Successfully created '${reg_no12_no27}'."
}

# ------------------------------------------------------------------------------
# 4. Modular Pipeline Step Functions
# ------------------------------------------------------------------------------

step_check_exp() {
    log_info "=== Running Step: step_check_exp ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' and 'screen_risetime' first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local cl2_evt="xa${OBSID}rsl_p0px1000_cl2.evt"
    if [[ ! -f "${cl2_evt}" ]]; then
        log_error "Base clean event file '${cl2_evt}' not found in '${ANALYSIS_DIR}'. Please run 'prepare' and 'screen_risetime' first."
        exit 1
    fi

    local exp_val=""
    if command -v fkeyprint >/dev/null 2>&1; then
        exp_val=$(fkeyprint "${cl2_evt}" EXPOSURE exact=yes 2>/dev/null | awk -F'=' '/EXPOSURE/ {print $2}' | awk '{print $1}' | tr -d "'" || true)
    fi
    if [[ -z "${exp_val}" ]]; then
        exp_val=$(get_fits_keyword "${cl2_evt}" "EXPOSURE" 2>/dev/null || echo "UNKNOWN")
    fi

    log_info "Base Clean Event Exposure: ${exp_val} seconds."
    log_audit "EXEC: step_check_exp -> EXPOSURE=${exp_val}s"
    log_success "Step check_exp completed."
}

step_prepare() {
    log_info "=== Running Step: step_prepare ==="
    log_audit "STEP_START: step_prepare (OBSID=${OBSID}, SOURCE=${SOURCE_NAME})"

    # 1. Check or run xapipeline if repo doesn't exist
    if [[ ! -d "${REPO_DIR}" ]]; then
        if [[ -d "${RAW_DIR}" ]]; then
            log_info "Repo directory '${REPO_DIR}' not found. Running xapipeline on raw data: '${RAW_DIR}'..."
            punlearn xapipeline
            xapipeline indir="${RAW_DIR}" outdir="${REPO_DIR}" steminputs="xa${OBSID}" stemoutputs="DEFAULT" \
                       entry_stage=1 exit_stage=2 instrument=ALL verify_input=no
            log_audit "EXEC: xapipeline on ${RAW_DIR} -> ${REPO_DIR}"
        else
            log_error "Neither repository directory '${REPO_DIR}' nor raw directory '${RAW_DIR}' exists."
            exit 1
        fi
    else
        log_info "Found existing reprocessed repository: '${REPO_DIR}'."
    fi

    # 2. Establish analysis directory
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    mkdir -p "${ANALYSIS_DIR}"

    # 3. Stage necessary primary files from REPO directly into ANALYSIS_DIR
    log_info "Staging primary event, EHK, and GTI files into '${ANALYSIS_DIR}'..."
    cp -u "${REPO_DIR}"/resolve/event_cl/*cl*.evt* "${ANALYSIS_DIR}/" 2>/dev/null || cp -u "${REPO_DIR}"/*cl*.evt* "${ANALYSIS_DIR}/" 2>/dev/null || true
    cp -u "${REPO_DIR}"/auxil/*.ehk* "${ANALYSIS_DIR}/" 2>/dev/null || cp -u "${REPO_DIR}"/*.ehk* "${ANALYSIS_DIR}/" 2>/dev/null || true
    cp -u "${REPO_DIR}"/resolve/event_cl/*px1000_exp.gti* "${ANALYSIS_DIR}/" 2>/dev/null || cp -u "${REPO_DIR}"/*px1000_exp.gti* "${ANALYSIS_DIR}/" 2>/dev/null || true

    # 4. Enter ANALYSIS_DIR after staging
    cd "${ANALYSIS_DIR}"

    # Uncompress any .gz files if present
    if ls *.gz >/dev/null 2>&1; then
        gunzip -f *.gz || true
    fi

    # 4. Generate detector region files
    create_region_files "."

    # 5. Extract header keywords
    local cl_evt="xa${OBSID}rsl_p0px1000_cl.evt"
    [[ ! -f "${cl_evt}" ]] && cl_evt="xa${OBSID}rsl_p0px1000_cl2.evt"
    if [[ -f "${cl_evt}" ]]; then
        RA_NOM=$(get_fits_keyword "${cl_evt}" "RA_NOM")
        DEC_NOM=$(get_fits_keyword "${cl_evt}" "DEC_NOM")
        PA_NOM=$(get_fits_keyword "${cl_evt}" "PA_NOM")
        log_info "Retrieved Nominal Pointing: RA_NOM=${RA_NOM}, DEC_NOM=${DEC_NOM}, PA_NOM=${PA_NOM}"
        
        if [[ -z "${SRC_RA}" ]]; then
            SRC_RA=$(get_fits_keyword "${cl_evt}" "RA_OBJ")
            [[ -z "${SRC_RA}" ]] && SRC_RA="${RA_NOM}"
            log_warn "Source RA not provided by user; using header value: ${SRC_RA}"
        fi
        if [[ -z "${SRC_DEC}" ]]; then
            SRC_DEC=$(get_fits_keyword "${cl_evt}" "DEC_OBJ")
            [[ -z "${SRC_DEC}" ]] && SRC_DEC="${DEC_NOM}"
            log_warn "Source DEC not provided by user; using header value: ${SRC_DEC}"
        fi
    fi

    log_success "Step prepare completed."
    log_audit "STEP_END: step_prepare"
}

step_screen_risetime() {
    log_info "=== Running Step: step_screen_risetime ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"
    
    local infile="xa${OBSID}rsl_p0px1000_cl.evt"
    local outfile="xa${OBSID}rsl_p0px1000_cl2.evt"

    if [[ ! -f "${infile}" ]]; then
        log_error "Input event file '${infile}' not found in '${ANALYSIS_DIR}'!"
        exit 1
    fi

    log_info "Applying Resolve rise-time and derivative screening to '${infile}'..."
    local expr="(PI>=600) && (((((RISE_TIME+0.00075*DERIV_MAX)>46)&&((RISE_TIME+0.00075*DERIV_MAX)<58))&&ITYPE<4)||(ITYPE==4)) && STATUS[4]==b0"
    
    ftcopy infile="${infile}[EVENTS][${expr}]" outfile="${outfile}" copyall=yes clobber=yes history=yes
    log_audit "EXEC: ftcopy screening -> ${outfile}"

    log_info "Screened exposure time check:"
    fkeyprint "${outfile}" EXPOSURE exact=yes | grep -i "EXPOSURE" || true

    log_success "Step screen_risetime completed -> '${outfile}'."
}

step_filter_epoch() {
    log_info "=== Running Step: step_filter_epoch (EPOCH=${EPOCH:-}, RANGE=[${DELTA_T_LOW:-}, ${DELTA_T_HIGH:-}]) ==="
    if [[ -z "${EPOCH:-}" || -z "${DELTA_T_LOW:-}" || -z "${DELTA_T_HIGH:-}" ]]; then
        log_error "Step 'filter_epoch' requires parameters -e <EPOCH_NAME> -l <DELTA_T_LOW> -u <DELTA_T_HIGH>."
        log_error "Example: $(basename "$0") -o ${OBSID:-<OBSID>} -i ${RAWDATA_DIR:-<RAWDATA_DIR>} -m filter_epoch -e epoch1 -l 0 -u 20000"
        exit 1
    fi

    if ! [[ "${DELTA_T_LOW}" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || ! [[ "${DELTA_T_HIGH}" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "DELTA_T_LOW (-l '${DELTA_T_LOW}') and DELTA_T_HIGH (-u '${DELTA_T_HIGH}') must be valid numbers (seconds)."
        exit 1
    fi

    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' and 'screen_risetime' first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local base_cl2="xa${OBSID}rsl_p0px1000_cl2.evt"
    local gti_file="xa${OBSID}_${EPOCH}.gti"
    local epoch_cl2="xa${OBSID}_${EPOCH}rsl_p0px1000_cl2.evt"

    if [[ ! -f "${base_cl2}" ]]; then
        log_error "Base clean event file '${base_cl2}' not found in '${ANALYSIS_DIR}'. Please run 'prepare' and 'screen_risetime' first."
        exit 1
    fi

    # Sub-step A: Astropy GTI Dynamic Slicing
    log_info "Generating sliced GTI table via Astropy for epoch '${EPOCH}' ([${DELTA_T_LOW}, ${DELTA_T_HIGH}] s relative to t0)..."
    local py_bin="${PYTHON_BIN:-python3}"
    "${py_bin}" -c "
import sys
import numpy as np
from astropy.io import fits

base_cl2 = '${base_cl2}'
out_gti = '${gti_file}'
epoch_name = '${EPOCH}'
dt_low = float('${DELTA_T_LOW}')
dt_high = float('${DELTA_T_HIGH}')

if dt_low >= dt_high:
    print(f'[ERROR] DELTA_T_LOW ({dt_low}) must be strictly less than DELTA_T_HIGH ({dt_high})', file=sys.stderr)
    sys.exit(1)

try:
    with fits.open(base_cl2) as hdul:
        gti_hdu = None
        for hdu in hdul:
            if hdu.name.startswith('GTI') or hdu.name == 'STDGTI':
                gti_hdu = hdu
                break
        
        if gti_hdu is None:
            print(f'[ERROR] No GTI extension found in {base_cl2}!', file=sys.stderr)
            sys.exit(1)
            
        col_names = [col.name.upper() for col in gti_hdu.columns]
        if 'START' not in col_names or 'STOP' not in col_names:
            print(f'[ERROR] GTI extension missing START or STOP column in {base_cl2}!', file=sys.stderr)
            sys.exit(1)
            
        start_col = gti_hdu.columns[col_names.index('START')].name
        stop_col = gti_hdu.columns[col_names.index('STOP')].name
        
        orig_starts = np.array(gti_hdu.data[start_col], dtype=np.float64)
        orig_stops = np.array(gti_hdu.data[stop_col], dtype=np.float64)
        
        if len(orig_starts) == 0:
            print(f'[ERROR] GTI extension in {base_cl2} is empty!', file=sys.stderr)
            sys.exit(1)
            
        t0 = float(np.min(orig_starts))
        w_start = t0 + dt_low
        w_stop = t0 + dt_high
        
        print(f'[INFO] Observation GTI t0: {t0:.6f} s')
        print(f'[INFO] Epoch {epoch_name} absolute window: [{w_start:.6f}, {w_stop:.6f}] s (relative: [{dt_low}, {dt_high}] s)')
        
        new_starts = np.maximum(orig_starts, w_start)
        new_stops = np.minimum(orig_stops, w_stop)
        
        valid = new_starts < new_stops
        filt_starts = new_starts[valid]
        filt_stops = new_stops[valid]
        
        if len(filt_starts) == 0:
            print(f'[ERROR] Sliced GTI has 0 intervals within relative window [{dt_low}, {dt_high}] s!', file=sys.stderr)
            print(f'[ERROR] Full observation GTI spans 0 to {np.max(orig_stops) - t0:.2f} s relative to t0.', file=sys.stderr)
            sys.exit(1)
            
        sliced_ontime = float(np.sum(filt_stops - filt_starts))
        print(f'[INFO] Sliced GTI total ontime: {sliced_ontime:.3f} s ({len(filt_starts)} intervals)')
        
        pri_hdu = fits.PrimaryHDU(header=hdul[0].header.copy())
        
        col1 = fits.Column(name='START', format='1D', unit='s', array=filt_starts)
        col2 = fits.Column(name='STOP', format='1D', unit='s', array=filt_stops)
        table_hdu = fits.BinTableHDU.from_columns([col1, col2], name='GTI')
        
        skip_keys = {'NAXIS1', 'NAXIS2', 'TFIELDS', 'TTYPE1', 'TFORM1', 'TUNIT1', 'TTYPE2', 'TFORM2', 'TUNIT2', 'EXTNAME'}
        for k, v in gti_hdu.header.items():
            if k not in skip_keys and k not in table_hdu.header:
                try:
                    table_hdu.header[k] = (v, gti_hdu.header.comments[k])
                except Exception:
                    pass
                    
        table_hdu.header['TSTART'] = float(filt_starts[0])
        table_hdu.header['TSTOP'] = float(filt_stops[-1])
        table_hdu.header['ONTIME'] = sliced_ontime
        table_hdu.header['EXPOSURE'] = sliced_ontime
        
        if 'TSTART' in pri_hdu.header:
            pri_hdu.header['TSTART'] = float(filt_starts[0])
        if 'TSTOP' in pri_hdu.header:
            pri_hdu.header['TSTOP'] = float(filt_stops[-1])
        if 'ONTIME' in pri_hdu.header:
            pri_hdu.header['ONTIME'] = sliced_ontime
        if 'EXPOSURE' in pri_hdu.header:
            pri_hdu.header['EXPOSURE'] = sliced_ontime
            
        new_hdul = fits.HDUList([pri_hdu, table_hdu])
        new_hdul.writeto(out_gti, overwrite=True)
        print(f'[SUCCESS] Successfully created GTI file: {out_gti}')

except Exception as exc:
    print(f'[ERROR] Python GTI slicing failed: {exc}', file=sys.stderr)
    sys.exit(1)
"
    log_audit "EXEC: Python Astropy GTI slicing -> ${gti_file}"

    if [[ ! -f "${gti_file}" ]]; then
        log_error "Failed to generate GTI file '${gti_file}'."
        exit 1
    fi

    # Sub-step B: Non-interactive XSELECT event filtering
    if [[ -f "${epoch_cl2}" ]]; then
        log_info "Detected pre-existing '${epoch_cl2}'. Removing prior to running xselect..."
        rm -f "${epoch_cl2}"
    fi

    log_info "Filtering events via xselect using '${gti_file}'..."
    xselect << XSEL_EPOCH_EOF
xsel_epoch_${EPOCH}
read event ${base_cl2} ./
filter time file ${gti_file}
extract event
save event ${epoch_cl2}
no
exit
no
XSEL_EPOCH_EOF
    log_audit "EXEC: xselect filter time file ${gti_file} -> ${epoch_cl2}"

    if [[ ! -f "${epoch_cl2}" || ! -s "${epoch_cl2}" ]]; then
        log_error "Failed to generate epoch event file '${epoch_cl2}' via xselect."
        exit 1
    fi

    log_info "Epoch filtered exposure time check (${epoch_cl2}):"
    fkeyprint "${epoch_cl2}" EXPOSURE exact=yes | grep -i "EXPOSURE" || true

    log_success "Epoch filtering completed -> '${epoch_cl2}'."
}

step_cutoff_rigidity() {
    local cor="$1"
    log_info "=== Running Step: step_cutoff_rigidity (CORTIME >= ${cor}, TAG=${TAG}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local ehk="xa${OBSID}.ehk"
    local cl2_evt="xa${TAG}rsl_p0px1000_cl2.evt"
    local out_gti="xa${TAG}_COR${cor}_src.gti"
    local out_evt="xa${TAG}rsl_p0px1000_cl2_COR${cor}.evt"

    if [[ ! -f "${ehk}" || ! -f "${cl2_evt}" ]]; then
        log_error "Missing '${ehk}' or '${cl2_evt}' in '${ANALYSIS_DIR}'."
        if [[ -n "${EPOCH:-}" && ! -f "${cl2_evt}" ]]; then
            log_error "Epoch clean event file '${cl2_evt}' not found. Please run 'filter_epoch' step first."
        fi
        exit 1
    fi

    # 1. Make time filter
    log_info "Creating GTI file for CORTIME >= ${cor} (TAG=${TAG})..."
    maketime infile="${ehk}" outfile="${out_gti}" expr="CORTIME>=${cor}" name=- value=- time=TIME compact=no clobber=yes
    log_audit "EXEC: maketime CORTIME>=${cor} -> ${out_gti}"

    # 2. Extract filtered event
    log_info "Extracting screened event file for COR${cor} (TAG=${TAG})..."
    extractor filename="${cl2_evt}" eventsout="${out_evt}" timefile="${out_gti}" \
              imgfile=NONE phafile=NONE fitsbinlc=NONE regionfile=NONE \
              xcolf=X ycolf=Y tcol=TIME ecol=PI xcolh=DETX ycolh=DETY clobber=yes
    log_audit "EXEC: extractor COR${cor} -> ${out_evt}"

    log_info "Filtered exposure time check (COR${cor}, TAG=${TAG}):"
    fkeyprint "${out_evt}" EXPOSURE exact=yes | grep -i "EXPOSURE" || true

    log_success "Cutoff rigidity filtering completed -> '${out_evt}'."
}

step_chk_event() {
    local cor="$1"
    log_info "=== Running Step: step_chk_event (COR${cor}, TAG=${TAG}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local evt="xa${TAG}rsl_p0px1000_cl2_COR${cor}.evt"
    local br_root="rsl${TAG}_cl2br_COR${cor}"
    local det_img="xa${TAG}rsl_p0px1000_detimg_COR${cor}.fits"
    local lc_file="xa${TAG}rsl_p0px1000_b128_COR${cor}.lc"

    # 1. Branching ratios
    log_info "Calculating branching ratios with rslbratios (TAG=${TAG})..."
    rslbratios infile="${evt}" filetype=cl outroot="${br_root}" lcbin=128.0 clobber=yes
    log_audit "EXEC: rslbratios -> ${br_root}"

    # 2. DET pixel image via xselect (Heredoc)
    log_info "Generating DET image via xselect (COR${cor}, TAG=${TAG})..."
    xselect <<XSEL_IMG_EOF
xsel_img_${cor}
read event ${evt} ./
set image DET
filter pha_cutoff 4000 20000
extr image
save image ${det_img}
exit
no
XSEL_IMG_EOF
    log_audit "EXEC: xselect extr image -> ${det_img}"

    # 3. Lightcurve via xselect (Heredoc)
    log_info "Extracting light curve via xselect (binsize 128s, COR${cor}, TAG=${TAG})..."
    xselect <<XSEL_LC_EOF
xsel_lc_${cor}
read event ${evt} ./
filter pha_cutoff 4000 20000
set binsize 128.0
extr curve exposure=0.8
save curve ${lc_file}
clear pha_cutoff
exit
no
XSEL_LC_EOF
    log_audit "EXEC: xselect extr curve -> ${lc_file}"

    log_success "Event checks (branching ratios, DET image, lightcurve) completed for COR${cor} (TAG=${TAG})."
}

step_extract_spec() {
    local cor="$1"
    log_info "=== Running Step: step_extract_spec (COR${cor}, TAG=${TAG}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local evt="xa${TAG}rsl_p0px1000_cl2_COR${cor}.evt"
    local spec_out="${TAG}_rsl_Hp_src_COR${cor}.pha"

    log_info "Extracting Resolve high-primary (Hp) spectrum (excluding px 12 & 27, TAG=${TAG})..."
    xselect <<XSEL_SPEC_EOF
xsel_spec_${cor}
read event ${evt} ./
filter column "pixel=0:11,13:26,28:35"
filter GRADE "0:0"
extr spectrum
save spectrum ${spec_out}
exit
no
XSEL_SPEC_EOF
    log_audit "EXEC: xselect extr spectrum -> ${spec_out}"
    log_success "Spectrum extraction completed -> '${spec_out}'."
}

step_generate_rmf() {
    local cor="$1"
    log_info "=== Running Step: step_generate_rmf (XL Size, COR${cor}, TAG=${TAG}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local evt="xa${TAG}rsl_p0px1000_cl2_COR${cor}.evt"
    local upr_evt="xa${TAG}rsl_p0px1000_UPR_COR${cor}.evt"
    local rmf_root="${TAG}_rsl_totexp_Hp_XL_src_COR${cor}"

    # 1. Screen artificial Ls events to generate UPR event file
    log_info "Generating UPR event file for RMF (TAG=${TAG})..."
    ftcopy infile="${evt}[EVENTS][(PI>=6000)&&(PI<=20000)&&(ITYPE<4)]" outfile="${upr_evt}" copyall=yes clobber=yes
    log_audit "EXEC: ftcopy UPR -> ${upr_evt}"

    # 2. Compute XL Size RMF via rslmkrmf
    log_info "Computing XL Size RMF via rslmkrmf (TAG=${TAG})..."
    punlearn rslmkrmf
    rslmkrmf infile="${upr_evt}" outfileroot="${rmf_root}" regmode=DET whichrmf=X resolist=0 regionfile=NONE \
              splitrmf=yes elcbinfac=16 splitcomb=yes pixlist=0-11,13-26,28-35 \
              eminin=0.0 dein=0.5 nchanin=60000 useingrd=no eminout=0.0 deout=0.5 nchanout=60000 \
              pixeltest=CENTER clobber=yes
    log_audit "EXEC: rslmkrmf (XL size) -> ${rmf_root}"

    log_success "RMF generation completed for COR${cor} (TAG=${TAG})."
}

step_generate_arf() {
    local cor="$1"
    log_info "=== Running Step: step_generate_arf (COR${cor}, TAG=${TAG}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    # --------------------------------------------------------------------------
    # Robust Pointing & Target Coordinates Extraction
    # --------------------------------------------------------------------------
    if [[ -z "${RA_NOM:-}" || -z "${DEC_NOM:-}" || -z "${PA_NOM:-}" ]]; then
        log_info "Nominal pointing not in memory; scanning event files for FITS header keywords..."
        
        local candidate_files=(
            "xa${TAG}rsl_p0px1000_cl2_COR${cor}.evt"
            "xa${TAG}rsl_p0px1000_cl2.evt"
            "xa${OBSID}rsl_p0px1000_cl.evt"
            "xa${OBSID}rsl_p0px1000_cl2.evt"
            "${REPO_DIR}/resolve/event_cl/xa${OBSID}rsl_p0px1000_cl.evt"
            "${REPO_DIR}/resolve/event_cl/xa${OBSID}rsl_p0px1000_cl2.evt"
            "${REPO_DIR}/xa${OBSID}rsl_p0px1000_cl.evt"
        )
        
        local header_evt=""
        for cand in "${candidate_files[@]}"; do
            if [[ -f "${cand}" ]]; then
                header_evt="${cand}"
                break
            fi
        done

        if [[ -n "${header_evt}" ]]; then
            log_info "Reading nominal pointing from '${header_evt}'..."
            [[ -z "${RA_NOM:-}" ]] && RA_NOM=$(get_fits_keyword "${header_evt}" "RA_NOM")
            [[ -z "${DEC_NOM:-}" ]] && DEC_NOM=$(get_fits_keyword "${header_evt}" "DEC_NOM")
            [[ -z "${PA_NOM:-}" ]] && PA_NOM=$(get_fits_keyword "${header_evt}" "PA_NOM")
            if [[ -z "${SRC_RA:-}" ]]; then
                SRC_RA=$(get_fits_keyword "${header_evt}" "RA_OBJ")
                [[ -z "${SRC_RA:-}" ]] && SRC_RA="${RA_NOM}"
            fi
            if [[ -z "${SRC_DEC:-}" ]]; then
                SRC_DEC=$(get_fits_keyword "${header_evt}" "DEC_OBJ")
                [[ -z "${SRC_DEC:-}" ]] && SRC_DEC="${DEC_NOM}"
            fi
        fi

        # Fallback to user-supplied target coordinates or default PA if still empty
        [[ -z "${RA_NOM:-}" && -n "${SRC_RA:-}" ]] && RA_NOM="${SRC_RA}"
        [[ -z "${DEC_NOM:-}" && -n "${SRC_DEC:-}" ]] && DEC_NOM="${SRC_DEC}"
        [[ -z "${PA_NOM:-}" ]] && PA_NOM="0.0"

        if [[ -z "${RA_NOM:-}" || -z "${DEC_NOM:-}" ]]; then
            log_error "Could not determine nominal pointing (RA_NOM, DEC_NOM). Please provide -r <RA> -d <DEC> or ensure event files are present in '${ANALYSIS_DIR}'."
            exit 1
        fi
        
        log_info "Using pointing: RA_NOM=${RA_NOM}, DEC_NOM=${DEC_NOM}, PA_NOM=${PA_NOM}, SRC_RA=${SRC_RA}, SRC_DEC=${SRC_DEC}"
    fi

    local evt="xa${TAG}rsl_p0px1000_cl2_COR${cor}.evt"
    local ehk="xa${OBSID}.ehk"
    local gti="xa${OBSID}rsl_px1000_exp.gti"
    local expo_out="xa${TAG}rsl_p0px1000_COR${cor}.expo"
    local rmf_in="${TAG}_rsl_totexp_Hp_XL_src_COR${cor}.rmf"
    [[ ! -f "${rmf_in}" ]] && rmf_in="${TAG}_rsl_totexp_Hp_XL_src_COR${cor}_comb.rmf"
    local arf_out="${TAG}_rsl_totexp_Hp_ptsrc_COR${cor}.arf"
    local reg_file="region_no12_no27.reg"

    # GTIFILE determination for xaexpmap:
    # When in time-resolved epoch mode, point to the sliced cl2 event file (or cor evt)
    local expmap_gtifile="${evt}"
    if [[ -n "${EPOCH:-}" ]]; then
        if [[ -f "xa${TAG}rsl_p0px1000_cl2.evt" ]]; then
            expmap_gtifile="xa${TAG}rsl_p0px1000_cl2.evt"
        fi
    fi

    # 1. Check coordinates consistency with coordpnt
    log_info "Verifying coordinates alignment with coordpnt (Nominal center: ${RDETX0}, ${RDETY0})..."
    punlearn coordpnt
    coordpnt input="${RDETX0},${RDETY0}" outfile=NONE telescop=XRISM instrume=RESOLVE teldeffile=CALDB \
             startsys=DET stopsys=RADEC ra="${RA_NOM:-0.0}" dec="${DEC_NOM:-0.0}" roll="${PA_NOM:-0.0}" \
             ranom="${RA_NOM:-0.0}" decnom="${DEC_NOM:-0.0}" clobber=yes
    log_audit "EXEC: coordpnt check at ${RDETX0},${RDETY0}"

    # 2. Make spatial exposure map
    log_info "Generating spatial exposure map via xaexpmap (gtifile=${expmap_gtifile}, pixgtifile=${gti})..."
    punlearn xaexpmap
    xaexpmap ehkfile="${ehk}" gtifile="${expmap_gtifile}" instrume=RESOLVE badimgfile=NONE \
             pixgtifile="${gti}" outfile="${expo_out}" outmaptype=EXPOSURE delta=20.0 numphi=1 clobber=yes
    log_audit "EXEC: xaexpmap -> ${expo_out}"

    # 3. Raytracing event file is an output from xaarfgen
    local xrt_file="raytrace_xa${TAG}rsl_p0px1000_imgmode_COR${cor}.fits"

    create_region_files "."

    # 4. Generate ARF via xaarfgen
    # Clean pre-existing raytrace file to prevent xaarfgen collision
    if [[ -f "${xrt_file}" ]]; then
        log_info "Detected existing raytrace file '${xrt_file}'. Removing prior to running xaarfgen..."
        rm -f "${xrt_file}"
    fi

    log_info "Generating point-source ARF via xaarfgen (TAG=${TAG})..."
    punlearn xaarfgen
    xaarfgen xrtevtfile="${xrt_file}" source_ra="${SRC_RA}" source_dec="${SRC_DEC}" \
             telescop=XRISM instrume=RESOLVE emapfile="${expo_out}" regmode=DET regionfile="${reg_file}" \
             sourcetype=POINT rmffile="${rmf_in}" erange="0.5 18.0 0.0 0.0" outfile="${arf_out}" \
             numphoton=600000 minphoton=100 teldeffile=CALDB qefile=CALDB contamifile=CALDB \
             obffile=CALDB fwfile=CALDB gatevalvefile=CALDB onaxisffile=CALDB onaxiscfile=CALDB \
             mirrorfile=CALDB obstructfile=CALDB frontreffile=CALDB backreffile=CALDB \
             pcolreffile=CALDB scatterfile=CALDB mode=h clobber=yes seed=7 imgfile=NONE
    log_audit "EXEC: xaarfgen -> ${arf_out}"

    log_success "ARF generation completed -> '${arf_out}'."
}

step_generate_NXB() {
    local cor="$1"
    log_info "=== Running Step: step_generate_NXB (COR${cor}, TAG=${TAG}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local evt="xa${TAG}rsl_p0px1000_cl2_COR${cor}.evt"
    local ehk="xa${OBSID}.ehk"
    local nxb_pi="xa${TAG}rsl_nxb_COR${cor}.pi"
    local nxb_evt="xa${TAG}rsl_nxb_COR${cor}.evt"
    local nxb_img="xa${TAG}rsl_nxb_detimg_COR${cor}.fits"
    local nxb_upr="xa${TAG}rsl_nxb_UPR_COR${cor}.evt"
    local nxb_rmf_root="xa${TAG}_rsl_Hp_M_nxb_COR${cor}"

    # Verify NXB DB directory and files
    if [[ ! -f "${NXB_DIR}/xrism_nxbdb_v3_rsl.evt" || ! -f "${NXB_DIR}/xrism_nxbdb_v3_rsl.ehk" ]]; then
        log_error "NXB database files ('xrism_nxbdb_v3_rsl.evt/ehk') not found in '${NXB_DIR}'!"
        exit 1
    fi

    # Determine sortbin dynamically
    local sortbin="6,8,10,12,99"
    local cor_num="${cor%%.*}" # Integer part
    if [[ "${cor_num}" -le 4 ]]; then
        sortbin="4,6,8,10,12,99"
    elif [[ "${cor_num}" -eq 6 ]]; then
        sortbin="6,8,10,12,99"
    elif [[ "${cor_num}" -ge 8 ]]; then
        sortbin="8,10,12,99"
    fi

    log_info "Extracting NXB spectrum and event list (sortcol=CORTIME, sortbin=${sortbin}, TAG=${TAG})..."
    punlearn rslnxbgen
    local nxb_expr="(PI>=600) && ((RISE_TIME+0.00075*DERIV_MAX)>46) && ((RISE_TIME+0.00075*DERIV_MAX)<58) && (ITYPE==0) && (STATUS[4]==b0) && (PIXEL!=27)"
    rslnxbgen infile="${evt}" ehkfile="${ehk}" regfile="NONE" pixels="-" \
              innxbfile="${NXB_DIR}/xrism_nxbdb_v3_rsl.evt" innxbehk="${NXB_DIR}/xrism_nxbdb_v3_rsl.ehk" \
              database="LOCAL" db_location="${NXB_DIR}/" timefirst="-1700" timelast="+1700" \
              sortcol="CORTIME" sortbin="${sortbin}" \
              expr="${nxb_expr}" \
              outpifile="${nxb_pi}" outnxbfile="${nxb_evt}" clobber=yes
    log_audit "EXEC: rslnxbgen -> ${nxb_pi}, ${nxb_evt}"

    # NXB DET image check
    ftcopy "${nxb_evt}[EVENTS][bin DETX=1:8:1,DETY=1:8:1]" "${nxb_img}" clobber=yes

    # Re-generate NXB RMF (mandatory for custom CORTIME)
    log_info "Re-generating calibrated NXB RMF (M size) for COR${cor} (TAG=${TAG})..."
    ftcopy infile="${nxb_evt}[EVENTS][(PI>=6000)&&(PI<=20000)&&(ITYPE<4)]" outfile="${nxb_upr}" copyall=yes clobber=yes
    punlearn rslmkrmf
    rslmkrmf infile="${nxb_upr}" outfileroot="${nxb_rmf_root}" regmode=DET whichrmf=M resolist=0 regionfile=NONE \
              pixlist=0-11,13-26,28-35 eminin=0.0 dein=0.5 nchanin=60000 useingrd=no eminout=0.0 deout=0.5 nchanout=60000 \
              pixeltest=CENTER clobber=yes
    log_audit "EXEC: rslmkrmf NXB -> ${nxb_rmf_root}.rmf"

    log_success "NXB generation & RMF calibration completed for COR${cor} (TAG=${TAG})."
}

# ------------------------------------------------------------------------------
# 5. Usage & Argument Parsing
# ------------------------------------------------------------------------------
usage() {
    cat << USAGE_EOF
Usage: $(basename "$0") -o <OBSID> [OPTIONS]

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
  -e <EPOCH_NAME>     Identifier tag for time-resolved epoch (e.g. "epoch1", "flare").
                      When specified, products use tag "<OBSID>_<EPOCH>".
  -l <DELTA_T_LOW>    Relative start time for time-resolved slicing in seconds (e.g. 0).
  -u <DELTA_T_HIGH>   Relative stop time for time-resolved slicing in seconds (e.g. 20000).
  -b <NXB_DIR>        Directory of XRISM NXB database (default: "\$XRISM_NXB_DB" or "/path/to/XRISM_NXB_DB").
  -x <RDETX0>         Nominal detector X center (default: 3.5).
  -y <RDETY0>         Nominal detector Y center (default: 3.5).
  -h                  Show this help message and exit.

Available Step Names for -m:
  check_exp           Inspect base clean event exposure time (EXPOSURE).
  prepare             Create analysis directory, link files, inspect headers.
  screen_risetime     Execute pulse-shape and rise-time screening (cl2.evt).
  filter_epoch        Slice GTI and filter events for time-resolved epoch (-e, -l, -u).
  cutoff_rigidity     Apply CORTIME filtering for each specified threshold.
  chk_event           Compute branching ratios, DET image, and light curve.
  extract_spec        Extract Resolve Hp grade-0 spectrum.
  generate_rmf        Create UPR file and generate XL-size RMF.
  generate_arf        Verify coordinates, compute exposure map, and generate ARF.
  generate_NXB        Generate NXB spectrum, image, and custom NXB RMF.

Examples:
  # 1. Base full-time reduction (default all steps):
  $(basename "$0") -o 201007010 -s Mrk3 -i /path/to/rawdata -r 93.901482 -d 71.037482 -b /path/to/XRISM_NXB_DB

  # 2. Check base clean event exposure time:
  $(basename "$0") -o 201007010 -i /path/to/rawdata -m check_exp

  # 3. Filter an epoch window (0 to 20000 s relative to observation start):
  $(basename "$0") -o 201007010 -i /path/to/rawdata -m filter_epoch -e epoch1 -l 0 -u 20000

  # 4. Run time-resolved reduction for epoch1 from cutoff_rigidity to generate_arf:
  $(basename "$0") -o 201007010 -i /path/to/rawdata -m "cutoff_rigidity,extract_spec,generate_rmf,generate_arf" -e epoch1 -c "4.0"

  # 5. Run full pipeline in time-resolved mode:
  $(basename "$0") -o 201007010 -i /path/to/rawdata -e epoch1 -l 0 -u 20000 -c "4.0" -b /path/to/XRISM_NXB_DB
USAGE_EOF
    exit 0
}

# ------------------------------------------------------------------------------
# 6. Main Execution Dispatcher
# ------------------------------------------------------------------------------
main() {
    OBSID=""
    SOURCE_NAME=""
    SRC_RA=""
    SRC_DEC=""
    RA_NOM=""
    DEC_NOM=""
    PA_NOM=""
    CORTIMES="4.0"
    EXEC_MODE="all"
    RAWDATA_DIR=""
    NXB_DIR="${XRISM_NXB_DB:-/path/to/XRISM_NXB_DB}"
    RDETX0="3.5"
    RDETY0="3.5"
    EPOCH=""
    DELTA_T_LOW=""
    DELTA_T_HIGH=""

    while getopts "o:s:r:d:c:m:i:b:x:y:e:l:u:h" opt; do
        case "${opt}" in
            o) OBSID="${OPTARG}" ;;
            s) SOURCE_NAME="${OPTARG}" ;;
            r) SRC_RA="${OPTARG}" ;;
            d) SRC_DEC="${OPTARG}" ;;
            c) CORTIMES="${OPTARG}" ;;
            m) EXEC_MODE="${OPTARG}" ;;
            i) RAWDATA_DIR="${OPTARG}" ;;
            b) NXB_DIR="${OPTARG}" ;;
            x) RDETX0="${OPTARG}" ;;
            y) RDETY0="${OPTARG}" ;;
            e) EPOCH="${OPTARG}" ;;
            l) DELTA_T_LOW="${OPTARG}" ;;
            u) DELTA_T_HIGH="${OPTARG}" ;;
            h) usage ;;
            *) usage ;;
        esac
    done

    if [[ -z "${OBSID}" ]]; then
        log_error "Observation ID (-o) is required."
        usage
    fi

    [[ -z "${SOURCE_NAME}" ]] && SOURCE_NAME="${OBSID}"

    # Define unified namespace tag
    if [[ -n "${EPOCH:-}" ]]; then
        TAG="${OBSID}_${EPOCH}"
    else
        TAG="${OBSID}"
    fi

    # Resolve RAWDATA_DIR and derive standardized paths
    [[ -z "${RAWDATA_DIR}" ]] && RAWDATA_DIR="."
    RAWDATA_DIR="${RAWDATA_DIR%/}"
    if [[ "$(basename "${RAWDATA_DIR}")" == "${OBSID}" ]]; then
        RAWDATA_DIR="$(dirname "${RAWDATA_DIR}")"
    fi
    RAWDATA_DIR="$(cd "${RAWDATA_DIR}" 2>/dev/null && pwd || echo "${RAWDATA_DIR}")"

    RAW_DIR="${RAWDATA_DIR}/${OBSID}"
    REPO_DIR="${RAWDATA_DIR}/${OBSID}_repo"
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    AUDIT_LOG="${ANALYSIS_DIR}/pipeline_audit.log"

    check_environment

    log_info "========================================================"
    log_info "Starting XRISM Resolve Reduction Pipeline"
    log_info "  OBSID        : ${OBSID}"
    log_info "  Source Name  : ${SOURCE_NAME}"
    log_info "  Namespace Tag: ${TAG}"
    if [[ -n "${EPOCH:-}" ]]; then
        log_info "  Epoch Name   : ${EPOCH}"
        log_info "  Epoch Window : [${DELTA_T_LOW:-N/A}, ${DELTA_T_HIGH:-N/A}] s"
    fi
    log_info "  Raw Base Dir : ${RAWDATA_DIR}"
    log_info "  Raw Data Dir : ${RAW_DIR}"
    log_info "  Repo Dir     : ${REPO_DIR}"
    log_info "  Analysis Dir : ${ANALYSIS_DIR}"
    log_info "  CORTIME(s)   : ${CORTIMES}"
    log_info "  Exec Mode    : ${EXEC_MODE}"
    log_info "  NXB DB Dir   : ${NXB_DIR}"
    log_info "========================================================"

    # Helper function to check if step should run
    should_run() {
        local step="$1"
        if [[ "${EXEC_MODE}" == "all" ]]; then
            if [[ "${step}" == "check_exp" ]]; then
                return 1
            fi
            if [[ "${step}" == "filter_epoch" && -z "${EPOCH:-}" ]]; then
                return 1
            fi
            return 0
        fi
        [[ ",${EXEC_MODE}," == *",${step},"* ]]
    }

    # Split CORTIMES into array
    IFS=',' read -r -a COR_ARRAY <<< "${CORTIMES}"

    # 1. Non-rigidity preparation & inspection steps
    if should_run "check_exp"; then
        step_check_exp
    fi

    if should_run "prepare"; then
        step_prepare
    fi

    if should_run "screen_risetime"; then
        step_screen_risetime
    fi

    if should_run "filter_epoch"; then
        step_filter_epoch
    fi

    # 2. Rigidity-dependent steps (Iterate for each CORTIME threshold)
    for cor_val in "${COR_ARRAY[@]}"; do
        cor_val="$(echo "${cor_val}" | tr -d ' ')"
        log_info "--------------------------------------------------------"
        log_info "Processing for Rigidity Threshold: CORTIME >= ${cor_val} (TAG=${TAG})"
        log_info "--------------------------------------------------------"

        if should_run "cutoff_rigidity"; then
            step_cutoff_rigidity "${cor_val}"
        fi

        if should_run "chk_event"; then
            step_chk_event "${cor_val}"
        fi

        if should_run "extract_spec"; then
            step_extract_spec "${cor_val}"
        fi

        if should_run "generate_rmf"; then
            step_generate_rmf "${cor_val}"
        fi

        if should_run "generate_arf"; then
            step_generate_arf "${cor_val}"
        fi

        if should_run "generate_NXB"; then
            step_generate_NXB "${cor_val}"
        fi
    done

    log_success "========================================================"
    log_success "Pipeline execution finished successfully!"
    log_success "All products and audit trail are saved in '${ANALYSIS_DIR}'."
    log_success "Audit log: ${AUDIT_LOG}"
    log_success "========================================================"
}

main "$@"
