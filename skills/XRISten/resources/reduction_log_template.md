# XRISM Resolve Reduction Log: {source_name} (ObsID: {ObsID})

## Observation & Session Metadata
- **Target Name**: `{source_name}`
- **Observation ID (ObsID)**: `{ObsID}`
- **Log Created**: `{session_start_timestamp}`
- **Last Updated**: `{last_updated_timestamp}`
- **Analysis Directory**: `{source_name}_analysis`
- **Reference Sky Position**: RA = `{RA}`, Dec = `{DEC}`
- **Detector Brightest Pixel**: `({RDETX0}, {RDETY0})`
- **Chosen Cut-off Rigidity Filter**: `CORTIME>={CHOSEN_COR}`

---

## Reduction History & Command Audit

### Step 1: Reprocess / Pre-reduction
- **Timestamp**: `{timestamp}`
- **Command Executed**:
```bash
xapipeline indir={indir} outdir={ObsID}_repo steminputs=xa{ObsID} stemoutputs=DEFAULT entry_stage=1 exit_stage=2 instrument=ALL verify_input=no
```
- **Key Output Files**:
  - `{ObsID}_repo/resolve/event_cl/xa{ObsID}rsl_p0px1000_cl.evt`
  - `{ObsID}_repo/resolve/event_cl/xa{ObsID}rsl_px1000_exp.gti`
  - `{ObsID}_repo/auxil/xa{ObsID}.ehk`
- **Notes / Verification**: Pre-pipeline version and telemetry verified.

---

### Step 2: Additional Screening (cl2)
- **Timestamp**: `{timestamp}`
- **Command Executed**:
```bash
ftcopy infile="xa{ObsID}rsl_p0px1000_cl.evt[EVENTS][(PI>=600)&&(((((RISE_TIME+0.00075*DERIV_MAX)>46)&&((RISE_TIME+0.00075*DERIV_MAX)<58))&&ITYPE<4)||(ITYPE==4)) && STATUS[4]==b0]" outfile=xa{ObsID}rsl_p0px1000_cl2.evt copyall=yes clobber=yes history=yes
```
- **Key Output Files**:
  - `xa{ObsID}rsl_p0px1000_cl2.evt`

---

### Step 3: Analysis Directory Setup
- **Timestamp**: `{timestamp}`
- **Command Executed**:
```bash
mkdir -p {source_name}_analysis
cp {ObsID}_repo/resolve/event_cl/*cl2.evt {source_name}_analysis/
cp {ObsID}_repo/auxil/*.ehk {source_name}_analysis/
cp {ObsID}_repo/resolve/event_cl/*px1000_exp.gti {source_name}_analysis/
cd {source_name}_analysis
```
- **Key Output Files**:
  - `{source_name}_analysis/` directory populated.

---

### Step 4: Cut-off Rigidity Filtering & Exposure Optimization
- **Timestamp**: `{timestamp}`
- **Optimization Strategy**: Evaluated `CORTIME>=4`, `CORTIME>=6`, `CORTIME>=8` to avoid unnecessary exposure loss.
- **Continuum Shape Comparison**: Verified consistent continuum shape across thresholds.
- **Filter Adopted**: `CORTIME>={CHOSEN_COR}` (e.g., `CORTIME>=4` chosen to retain maximum exposure).
- **Commands Executed**:
```bash
maketime infile='xa{ObsID}.ehk' outfile='xa{ObsID}_COR{CHOSEN_COR}_src.gti' expr='CORTIME>={CHOSEN_COR}' name=- value=- time=TIME compact=no
extractor filename='xa{ObsID}rsl_p0px1000_cl2.evt' eventsout='xa{ObsID}rsl_p0px1000_cl2_COR{CHOSEN_COR}.evt' timefile='xa{ObsID}_COR{CHOSEN_COR}_src.gti' imgfile=NONE phafile=NONE fitsbinlc=NONE regionfile=NONE xcolf=X ycolf=Y tcol=TIME ecol=PI xcolh=DETX ycolh=DETY
```
- **Key Output Files**:
  - `xa{ObsID}_COR{CHOSEN_COR}_src.gti`
  - `xa{ObsID}rsl_p0px1000_cl2_COR{CHOSEN_COR}.evt`

---

### Step 5: Branching Ratios Diagnostic
- **Timestamp**: `{timestamp}`
- **Command Executed**:
```bash
rslbratios infile=xa{ObsID}rsl_p0px1000_cl2{COR_SUFFIX}.evt filetype=cl outroot=rsl{ObsID}{COR_SUFFIX}_br lcbin=128.0
```
- **Key Output Files**:
  - `rsl{ObsID}{COR_SUFFIX}_br_clbr_2keVto12keV_hist.fits`

---

### Step 6: Detector Image Generation
- **Timestamp**: `{timestamp}`
- **Interactive xselect Commands**:
```bash
xselect
read eve xa{ObsID}rsl_p0px1000_cl2{COR_SUFFIX}.evt .
set image DET
filter pha_cutoff 4000 20000
extr image
save image xa{ObsID}rsl_p0px1000{COR_SUFFIX}_detimg.fits
exit
n
```
- **Key Output Files**:
  - `xa{ObsID}rsl_p0px1000{COR_SUFFIX}_detimg.fits`

---

### Step 7: DET Source Center Verification (Manual Check)
- **Timestamp**: `{timestamp}`
- **Manual Verification Status**: Confirmed by User via DS9 projection graphs.
- **Identified Detector Center**: `RDETX0 = {RDETX0}`, `RDETY0 = {RDETY0}`

---

### Step 8: Light Curve Extraction
- **Timestamp**: `{timestamp}`
- **Interactive xselect Commands**:
```bash
xselect
read eve xa{ObsID}rsl_p0px1000_cl2{COR_SUFFIX}.evt .
filter pha_cutoff 4000 20000
set binsize 128.0
extr curve exposure=0.8
save curve xa{ObsID}rsl_p0px1000_b128.lc
clear pha_cutoff
exit
n
```
- **Key Output Files**:
  - `xa{ObsID}rsl_p0px1000_b128.lc`

---

### Step 9: Resolve Hp Spectrum Extraction
- **Timestamp**: `{timestamp}`
- **Interactive xselect Commands**:
```bash
xselect
read eve xa{ObsID}rsl_p0px1000_cl2{COR_SUFFIX}.evt .
filter column "pixel=0:11,13:26,28:35"
filter GRADE "0:0"
extr spectrum
save spectrum {source_name}_rsl_Hp_src.pi
exit
n
```
- **Key Output Files**:
  - `{source_name}_rsl_Hp_src.pi`

---

### Step 10: RMF Generation
- **Timestamp**: `{timestamp}`
- **RMF Size Choice**: `{whichrmf}` (L or XL)
- **Commands Executed**:
```bash
ftcopy infile="xa{ObsID}rsl_p0px1000_cl2{COR_SUFFIX}.evt[EVENTS][(PI>=6000)&&(PI<=20000)&&(ITYPE<4)]" outfile=xa{ObsID}rsl_p0px1000_UPR.evt copyall=yes
punlearn rslmkrmf
rslmkrmf infile=xa{ObsID}rsl_p0px1000_UPR.evt outfileroot={source_name}_rsl_totexp_Hp_{whichrmf}_src regmode=DET whichrmf={whichrmf} resolist=0 regionfile=NONE pixlist=0-11,13-26,28-35 eminin=0.0 dein=0.5 nchanin=60000 useingrd=no eminout=0.0 deout=0.5 nchanout=60000 pixeltest=CENTER
```
- **Key Output Files**:
  - `xa{ObsID}rsl_p0px1000_UPR.evt`
  - `{source_name}_rsl_totexp_Hp_{whichrmf}_src.rmf`

---

### Step 11: Exposure Map Generation
- **Timestamp**: `{timestamp}`
- **Command Executed**:
```bash
punlearn xaexpmap
xaexpmap ehkfile=xa{ObsID}.ehk gtifile=xa{ObsID}rsl_p0px1000_cl2{COR_SUFFIX}.evt instrume=RESOLVE badimgfile=NONE pixgtifile=xa{ObsID}rsl_px1000_exp.gti outfile=xa{ObsID}rsl_p0px1000.expo outmaptype=EXPOSURE delta=20.0 numphi=1
```
- **Key Output Files**:
  - `xa{ObsID}rsl_p0px1000.expo`

---

### Step 12: Source Coordinate Alignment & Check (Manual Check)
- **Timestamp**: `{timestamp}`
- **Coordinates Verified**: RA = `{RA}`, Dec = `{DEC}` (via NED / Catalog)
- **Command Executed**:
```bash
punlearn coordpnt
coordpnt input="{RDETX0},{RDETY0}" outfile=NONE telescop=XRISM instrume=RESOLVE teldeffile=CALDB startsys=DET stopsys=RADEC ra={RA_NOM} dec={DEC_NOM} roll={PA_NOM} ranom={RA_NOM} decnom={DEC_NOM} clobber=yes
```

---

### Step 13: ARF Generation
- **Timestamp**: `{timestamp}`
- **Region File**: `no27.reg`
- **Command Executed**:
```bash
punlearn xaarfgen
xaarfgen xrtevtfile=raytrace_xa{ObsID}rsl_p0px1000_imgmode.fits source_ra={RA} source_dec={DEC} telescop=XRISM instrume=RESOLVE emapfile=xa{ObsID}rsl_p0px1000.expo regmode=DET regionfile=no27.reg sourcetype=POINT rmffile={source_name}_rsl_totexp_Hp_L_src.rmf erange="0.5 18.0 0.0 0.0" outfile={source_name}_rsl_totexp_Hp_ptsrc.arf numphoton=600000 minphoton=100 teldeffile=CALDB qefile=CALDB contamifile=CALDB obffile=CALDB fwfile=CALDB gatevalvefile=CALDB onaxisffile=CALDB onaxiscfile=CALDB mirrorfile=CALDB obstructfile=CALDB frontreffile=CALDB backreffile=CALDB pcolreffile=CALDB scatterfile=CALDB mode=h clobber=yes seed=7 imgfile=NONE
```
- **Key Output Files**:
  - `{source_name}_rsl_totexp_Hp_ptsrc.arf`

---

### Step 14: Non-X-ray Background (NXB) Generation & NXB Response Matrix
- **Timestamp**: `{timestamp}`
- **NXB Database Path**: `<NXB_DB_PATH>`
- **Filter Applied**: `CORTIME>={CHOSEN_COR}` (`sortbin='{SORTBIN}'`)
- **Command Executed**:
```bash
rslnxbgen infile='xa{ObsID}rsl_p0px1000_cl2{COR_SUFFIX}.evt' ehkfile='xa{ObsID}.ehk' regfile='NONE' pixels='-' innxbfile='<NXB_DB_PATH>/xrism_nxbdb_v3_rsl.evt' innxbehk='<NXB_DB_PATH>/xrism_nxbdb_v3_rsl.ehk' database='LOCAL' db_location='<NXB_DB_PATH>/' timefirst='-1700' timelast='+1700' sortcol='CORTIME' sortbin='{SORTBIN}' expr='(PI>=600) && ((RISE_TIME+0.00075*DERIV_MAX)>46) && ((RISE_TIME+0.00075*DERIV_MAX)<58) && (ITYPE==0) && (STATUS[4]==b0) && (PIXEL!=27)' outpifile='xa{ObsID}rsl_nxb{COR_SUFFIX}.pi' outnxbfile='xa{ObsID}rsl_nxb{COR_SUFFIX}.evt'
ftcopy 'xa{ObsID}rsl_nxb{COR_SUFFIX}.evt[EVENTS][bin DETX=1:8:1,DETY=1:8:1]' xa{ObsID}rsl_nxb{COR_SUFFIX}_detimg.fits clobber=yes
```
- **NXB RMF Generation**:
  - *Status*: `{NXB_RMF_STATUS}` (Default database `xrism_nxb_v3_rsl_M.rmf` for COR6; or custom re-generated for non-COR6).
  - *Re-generation Commands (if CORTIME != 6)*:
```bash
ftcopy infile="xa{ObsID}rsl_nxb{COR_SUFFIX}.evt[EVENTS][(PI>=6000)&&(PI<=20000)&&(ITYPE<4)]" outfile=xa{ObsID}rsl_nxb{COR_SUFFIX}_UPR.evt copyall=yes
punlearn rslmkrmf
rslmkrmf infile=xa{ObsID}rsl_nxb{COR_SUFFIX}_UPR.evt outfileroot=xa{ObsID}rsl_nxb{COR_SUFFIX}_M regmode=DET whichrmf=M resolist=0 regionfile=NONE pixlist=0-11,13-26,28-35 eminin=0.0 dein=0.5 nchanin=60000 useingrd=no eminout=0.0 deout=0.5 nchanout=60000 pixeltest=CENTER
```
- **Key Output Files**:
  - `xa{ObsID}rsl_nxb{COR_SUFFIX}.pi`
  - `xa{ObsID}rsl_nxb{COR_SUFFIX}.evt`
  - `xa{ObsID}rsl_nxb{COR_SUFFIX}_detimg.fits`
  - `xa{ObsID}rsl_nxb{COR_SUFFIX}_M.rmf` (if CORTIME != 6)
