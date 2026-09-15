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
        "fkeyprint" "punlearn" "python3"
    )

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_error "Required command '${cmd}' is not found in PATH. Please verify HEASoft installation."
            exit 1
        fi
    done
    
    log_success "Environment validation passed. HEADAS and CALDB are active."
}

# ------------------------------------------------------------------------------
# 3. Helper Functions
# ------------------------------------------------------------------------------
get_fits_keyword() {
    local fits_file="$1"
    local keyword="$2"
    
    python3 -c "
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

step_cutoff_rigidity() {
    local cor="$1"
    log_info "=== Running Step: step_cutoff_rigidity (CORTIME >= ${cor}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local ehk="xa${OBSID}.ehk"
    local cl2_evt="xa${OBSID}rsl_p0px1000_cl2.evt"
    local out_gti="xa${OBSID}_COR${cor}_src.gti"
    local out_evt="xa${OBSID}rsl_p0px1000_cl2_COR${cor}.evt"

    if [[ ! -f "${ehk}" || ! -f "${cl2_evt}" ]]; then
        log_error "Missing '${ehk}' or '${cl2_evt}' in '${ANALYSIS_DIR}'."
        exit 1
    fi

    # 1. Make time filter
    log_info "Creating GTI file for CORTIME >= ${cor}..."
    maketime infile="${ehk}" outfile="${out_gti}" expr="CORTIME>=${cor}" name=- value=- time=TIME compact=no clobber=yes
    log_audit "EXEC: maketime CORTIME>=${cor} -> ${out_gti}"

    # 2. Extract filtered event
    log_info "Extracting screened event file for COR${cor}..."
    extractor filename="${cl2_evt}" eventsout="${out_evt}" timefile="${out_gti}" \
              imgfile=NONE phafile=NONE fitsbinlc=NONE regionfile=NONE \
              xcolf=X ycolf=Y tcol=TIME ecol=PI xcolh=DETX ycolh=DETY clobber=yes
    log_audit "EXEC: extractor COR${cor} -> ${out_evt}"

    log_info "Filtered exposure time check (COR${cor}):"
    fkeyprint "${out_evt}" EXPOSURE exact=yes | grep -i "EXPOSURE" || true

    log_success "Cutoff rigidity filtering completed -> '${out_evt}'."
}

step_chk_event() {
    local cor="$1"
    log_info "=== Running Step: step_chk_event (COR${cor}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local evt="xa${OBSID}rsl_p0px1000_cl2_COR${cor}.evt"
    local br_root="rsl${OBSID}_cl2br_COR${cor}"
    local det_img="xa${OBSID}rsl_p0px1000_detimg_COR${cor}.fits"
    local lc_file="xa${OBSID}rsl_p0px1000_b128_COR${cor}.lc"

    # 1. Branching ratios
    log_info "Calculating branching ratios with rslbratios..."
    rslbratios infile="${evt}" filetype=cl outroot="${br_root}" lcbin=128.0 clobber=yes
    log_audit "EXEC: rslbratios -> ${br_root}"

    # 2. DET pixel image via xselect (Heredoc)
    log_info "Generating DET image via xselect (COR${cor})..."
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
    log_info "Extracting light curve via xselect (binsize 128s, COR${cor})..."
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

    log_success "Event checks (branching ratios, DET image, lightcurve) completed for COR${cor}."
}

step_extract_spec() {
    local cor="$1"
    log_info "=== Running Step: step_extract_spec (COR${cor}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local evt="xa${OBSID}rsl_p0px1000_cl2_COR${cor}.evt"
    local spec_out="${SOURCE_NAME}_rsl_Hp_src_COR${cor}.pha"

    log_info "Extracting Resolve high-primary (Hp) spectrum (excluding px 12 & 27)..."
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
    log_info "=== Running Step: step_generate_rmf (XL Size, COR${cor}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local evt="xa${OBSID}rsl_p0px1000_cl2_COR${cor}.evt"
    local upr_evt="xa${OBSID}rsl_p0px1000_UPR_COR${cor}.evt"
    local rmf_root="${SOURCE_NAME}_rsl_totexp_Hp_XL_src_COR${cor}"

    # 1. Screen artificial Ls events to generate UPR event file
    log_info "Generating UPR event file for RMF..."
    ftcopy infile="${evt}[EVENTS][(PI>=6000)&&(PI<=20000)&&(ITYPE<4)]" outfile="${upr_evt}" copyall=yes clobber=yes
    log_audit "EXEC: ftcopy UPR -> ${upr_evt}"

    # 2. Compute XL Size RMF via rslmkrmf
    log_info "Computing XL Size RMF via rslmkrmf..."
    punlearn rslmkrmf
    rslmkrmf infile="${upr_evt}" outfileroot="${rmf_root}" regmode=DET whichrmf=X resolist=0 regionfile=NONE \
              splitrmf=yes elcbinfac=16 splitcomb=yes pixlist=0-11,13-26,28-35 \
              eminin=0.0 dein=0.5 nchanin=60000 useingrd=no eminout=0.0 deout=0.5 nchanout=60000 \
              pixeltest=CENTER clobber=yes
    log_audit "EXEC: rslmkrmf (XL size) -> ${rmf_root}"

    log_success "RMF generation completed for COR${cor}."
}

step_generate_arf() {
    local cor="$1"
    log_info "=== Running Step: step_generate_arf (COR${cor}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    # Ensure coordinates are available even if prepare step was skipped
    local cl_evt="xa${OBSID}rsl_p0px1000_cl.evt"
    if [[ (-z "${RA_NOM:-}" || -z "${DEC_NOM:-}" || -z "${PA_NOM:-}") && -f "${cl_evt}" ]]; then
        log_info "Retrieving nominal pointing from '${cl_evt}'..."
        [[ -z "${RA_NOM:-}" ]] && RA_NOM=$(get_fits_keyword "${cl_evt}" "RA_NOM")
        [[ -z "${DEC_NOM:-}" ]] && DEC_NOM=$(get_fits_keyword "${cl_evt}" "DEC_NOM")
        [[ -z "${PA_NOM:-}" ]] && PA_NOM=$(get_fits_keyword "${cl_evt}" "PA_NOM")
        if [[ -z "${SRC_RA}" ]]; then
            SRC_RA=$(get_fits_keyword "${cl_evt}" "RA_OBJ")
            [[ -z "${SRC_RA}" ]] && SRC_RA="${RA_NOM}"
        fi
        if [[ -z "${SRC_DEC}" ]]; then
            SRC_DEC=$(get_fits_keyword "${cl_evt}" "DEC_OBJ")
            [[ -z "${SRC_DEC}" ]] && SRC_DEC="${DEC_NOM}"
        fi
    fi

    local evt="xa${OBSID}rsl_p0px1000_cl2_COR${cor}.evt"
    local ehk="xa${OBSID}.ehk"
    local gti="xa${OBSID}rsl_px1000_exp.gti"
    local expo_out="xa${OBSID}rsl_p0px1000_COR${cor}.expo"
    local rmf_in="${SOURCE_NAME}_rsl_totexp_Hp_XL_src_COR${cor}.rmf"
    [[ ! -f "${rmf_in}" ]] && rmf_in="${SOURCE_NAME}_rsl_totexp_Hp_XL_src_COR${cor}_comb.rmf"
    local arf_out="${SOURCE_NAME}_rsl_totexp_Hp_ptsrc_COR${cor}.arf"
    local reg_file="region_no12_no27.reg"

    # 1. Check coordinates consistency with coordpnt
    log_info "Verifying coordinates alignment with coordpnt (Nominal center: ${RDETX0}, ${RDETY0})..."
    punlearn coordpnt
    coordpnt input="${RDETX0},${RDETY0}" outfile=NONE telescop=XRISM instrume=RESOLVE teldeffile=CALDB \
             startsys=DET stopsys=RADEC ra="${RA_NOM}" dec="${DEC_NOM}" roll="${PA_NOM}" \
             ranom="${RA_NOM}" decnom="${DEC_NOM}" clobber=yes
    log_audit "EXEC: coordpnt check at ${RDETX0},${RDETY0}"

    # 2. Make spatial exposure map
    log_info "Generating spatial exposure map via xaexpmap..."
    punlearn xaexpmap
    xaexpmap ehkfile="${ehk}" gtifile="${evt}" instrume=RESOLVE badimgfile=NONE \
             pixgtifile="${gti}" outfile="${expo_out}" outmaptype=EXPOSURE delta=20.0 numphi=1 clobber=yes
    log_audit "EXEC: xaexpmap -> ${expo_out}"

    # 3. Raytracing event file is an output from xaarfgen
    local xrt_file="raytrace_xa${OBSID}rsl_p0px1000_imgmode_COR${cor}.fits"

    create_region_files "."

    # 4. Generate ARF via xaarfgen
    log_info "Generating point-source ARF via xaarfgen..."
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
    log_info "=== Running Step: step_generate_NXB (COR${cor}) ==="
    ANALYSIS_DIR="${RAWDATA_DIR}/${OBSID}_analysis"
    if [[ ! -d "${ANALYSIS_DIR}" ]]; then
        log_error "Analysis directory '${ANALYSIS_DIR}' not found. Please run 'prepare' step first."
        exit 1
    fi
    cd "${ANALYSIS_DIR}"

    local evt="xa${OBSID}rsl_p0px1000_cl2_COR${cor}.evt"
    local ehk="xa${OBSID}.ehk"
    local nxb_pi="xa${OBSID}rsl_nxb_COR${cor}.pi"
    local nxb_evt="xa${OBSID}rsl_nxb_COR${cor}.evt"
    local nxb_img="xa${OBSID}rsl_nxb_detimg_COR${cor}.fits"
    local nxb_upr="xa${OBSID}rsl_nxb_UPR_COR${cor}.evt"
    local nxb_rmf_root="xa${OBSID}_rsl_Hp_M_nxb_COR${cor}"

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

    log_info "Extracting NXB spectrum and event list (sortcol=CORTIME, sortbin=${sortbin})..."
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
    log_info "Re-generating calibrated NXB RMF (M size) for COR${cor}..."
    ftcopy infile="${nxb_evt}[EVENTS][(PI>=6000)&&(PI<=20000)&&(ITYPE<4)]" outfile="${nxb_upr}" copyall=yes clobber=yes
    punlearn rslmkrmf
    rslmkrmf infile="${nxb_upr}" outfileroot="${nxb_rmf_root}" regmode=DET whichrmf=M resolist=0 regionfile=NONE \
              pixlist=0-11,13-26,28-35 eminin=0.0 dein=0.5 nchanin=60000 useingrd=no eminout=0.0 deout=0.5 nchanout=60000 \
              pixeltest=CENTER clobber=yes
    log_audit "EXEC: rslmkrmf NXB -> ${nxb_rmf_root}.rmf"

    log_success "NXB generation & RMF calibration completed for COR${cor}."
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
  -b <NXB_DIR>        Directory of XRISM NXB database (default: "\$XRISM_NXB_DB" or "/path/to/XRISM_NXB_DB").
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

Examples:
  # 1. Run all steps with raw data at /path/to/rawdata/201007010:
  $(basename "$0") -o 201007010 -s Mrk3 -i /path/to/rawdata -r 93.901482 -d 71.037482 -b /path/to/XRISM_NXB_DB

  # 2. Run multi-threshold CORTIME comparison (4 and 6):
  $(basename "$0") -o 201007010 -s Mrk3 -i /path/to/rawdata -c "4,6" -b /path/to/XRISM_NXB_DB

  # 3. Run specific steps only from any directory:
  $(basename "$0") -o 201007010 -s Mrk3 -i /path/to/rawdata -m "cutoff_rigidity,extract_spec" -c "4,6"
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
    CORTIMES="4.0"
    EXEC_MODE="all"
    RAWDATA_DIR=""
    NXB_DIR="${XRISM_NXB_DB:-/path/to/XRISM_NXB_DB}"
    RDETX0="3.5"
    RDETY0="3.5"

    while getopts "o:s:r:d:c:m:i:b:x:y:h" opt; do
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
            h) usage ;;
            *) usage ;;
        esac
    done

    if [[ -z "${OBSID}" ]]; then
        log_error "Observation ID (-o) is required."
        usage
    fi

    [[ -z "${SOURCE_NAME}" ]] && SOURCE_NAME="${OBSID}"

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
            return 0
        fi
        [[ ",${EXEC_MODE}," == *",${step},"* ]]
    }

    # Split CORTIMES into array
    IFS=',' read -r -a COR_ARRAY <<< "${CORTIMES}"

    # 1. Non-rigidity preparation steps
    if should_run "prepare"; then
        step_prepare
    fi

    if should_run "screen_risetime"; then
        step_screen_risetime
    fi

    # 2. Rigidity-dependent steps (Iterate for each CORTIME threshold)
    for cor_val in "${COR_ARRAY[@]}"; do
        cor_val="$(echo "${cor_val}" | tr -d ' ')"
        log_info "--------------------------------------------------------"
        log_info "Processing for Rigidity Threshold: CORTIME >= ${cor_val}"
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
