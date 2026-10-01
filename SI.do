****************************************************
* Vehicle-to-grid discharge reshapes electric vehicle charging behavior
* Supplementary robustness analyses
*
* This script reproduces the robustness checks described in the manuscript:
*   A. Event-study reference-point sensitivity using events -1 and -2.
*   B. Fixed-effect sensitivity using no FE, vehicle FE only,
*      calendar-week FE only, and province-by-calendar-week FE only.
*
* Required restricted data:
*   data/private/analysis_data.dta
*
* Output directory:
*   results/SI/
*
* Software:
*   Stata 16.0
****************************************************

version 16.0
set more off
set linesize 255
capture set maxvar 32767
set varabbrev off

****************************************************
* 0. Project paths and run settings
****************************************************

global project "`c(pwd)'"
global data    "$project/data/private"
global out     "$project/results/SI"

capture mkdir "$project/results"
capture mkdir "$out"

capture confirm file "$data/analysis_data.dta"
if _rc {
    di as error "Error: restricted analysis dataset not found."
    di as error "Expected file: $data/analysis_data.dta"
    exit 601
}

use "$data/analysis_data.dta", clear

capture log close _all
log using "$out/00_V2G_SI_robustness.log", text replace

global min_car_type_vehicles 5
global controls_main      "i.weekend i.holiday_group"
global controls_noholiday "i.weekend"
global absorb_main        "vehicle_id province_week_fe"
global outcomes_article ///
    "y1_chg_start_soc y2_chg_end_soc ln_y3_chg_energy ln_y4_chg_duration_h"

****************************************************
* 0A. Protect the original data frame
****************************************************
local original_frame "`c(frame)'"
capture frame drop si_work
frame copy `original_frame' si_work
frame change si_work

di as result "=================================================="
di as result "SI robustness analyses run in temporary frame: si_work"
di as result "Original data frame: `original_frame' will not be modified"
di as result "=================================================="

****************************************************
* 1. Check data and required variables
****************************************************

capture noisily describe
if _rc {
    di as error "Error: no usable data are loaded in Stata."
    exit 2000
}

if _N == 0 {
    di as error "Error: the current dataset contains no observations."
    exit 2000
}

di as txt "Current dataset: `c(filename)'"
di as txt "Number of observations: " _N

local required_vars ///
    vid vehicle_id event_id ///
    y1_chg_start_soc y2_chg_end_soc ///
    y3_chg_energy y4_chg_duration_h ///
    rel_k post complete20_calc ///
    vehicle_discharge_count_desc ///
    discharge_start_time charge_start_time ///
    holiday car_type province

foreach v of local required_vars {
    capture confirm variable `v'
    if _rc {
        di as error "Error: required variable `v' is missing."
        di as error "Check that the authorized V2G analysis dataset is being used."
        describe
        exit 111
    }
}

****************************************************
* 1.1 Ensure numeric identifiers
****************************************************

capture confirm numeric variable vehicle_id
if _rc {
    capture drop vehicle_id_num
    egen long vehicle_id_num = group(vid)
    drop vehicle_id
    rename vehicle_id_num vehicle_id
    label variable vehicle_id "Numeric vehicle ID generated from vid"
}
else {
    label variable vehicle_id "Numeric vehicle ID"
}

capture confirm numeric variable event_id
if _rc {
    capture drop event_id_num
    egen long event_id_num = group(event_id)
    drop event_id
    rename event_id_num event_id
    label variable event_id "Numeric V2G discharge-event ID"
}
else {
    label variable event_id "Numeric V2G discharge-event ID"
}

****************************************************
* 1.2 Create integer relative-event variable
****************************************************

capture confirm numeric variable rel_k
if _rc {
    di as error "Error: rel_k must be numeric."
    exit 109
}

capture drop rel_int
gen int rel_int = round(rel_k)
label variable rel_int "Relative charging-event position to V2G discharge (integer)"

tab rel_int, missing

****************************************************
* 1.3 Diagnose and remove exact duplicates
****************************************************

capture drop __dup_exact
duplicates tag, gen(__dup_exact)

quietly count if __dup_exact > 0
local N_dup_rows = r(N)
di as txt "Rows involved in exact duplicates = `N_dup_rows'"

if `N_dup_rows' > 0 {
    preserve
        keep if __dup_exact > 0
        sort event_id rel_int
        export excel using "$out/01_exact_duplicate_rows.xlsx", ///
            firstrow(variables) replace
    restore
}

drop __dup_exact
duplicates drop

preserve
    keep if !missing(rel_int)
    capture noisily isid event_id rel_int
    if _rc {
        di as error "Warning: event_id × rel_int is still not unique after removing exact duplicates."
        duplicates tag event_id rel_int, gen(__dup_event_rel)
        keep if __dup_event_rel > 0
        export excel using "$out/02_remaining_event_rel_duplicates.xlsx", ///
            firstrow(variables) replace
    }
    else {
        di as txt "Check passed: event_id × rel_int is unique."
    }
restore

****************************************************
* 2. Construct dates, fixed effects, and calendar controls
****************************************************

****************************************************
* 2.1 Parse charging date
****************************************************

capture drop charge_day

capture confirm numeric variable charge_start_time
if !_rc {
    local charge_fmt : format charge_start_time
    quietly summarize charge_start_time, meanonly

    if substr("`charge_fmt'", 1, 3) == "%td" {
        gen double charge_day = charge_start_time
    }
    else if substr("`charge_fmt'", 1, 3) == "%tc" {
        gen double charge_day = dofc(charge_start_time)
    }
    else if r(max) > 10000000 & r(max) < 30000000 {
        capture drop __charge_str
        gen str8 __charge_str = string(charge_start_time, "%08.0f")
        gen double charge_day = daily(__charge_str, "YMD")
        drop __charge_str
    }
    else if r(max) > 1000000000 & r(max) < 4000000000 {
        gen double charge_day = ///
            dofc((charge_start_time + 315619200) * 1000)
    }
    else if r(max) > 100000000000 {
        gen double charge_day = dofc(charge_start_time)
    }
    else {
        gen double charge_day = charge_start_time
    }
}
else {
    gen double charge_day = ///
        daily(substr(strtrim(charge_start_time), 1, 10), "YMD")
    replace charge_day = ///
        daily(substr(strtrim(charge_start_time), 1, 10), "DMY") ///
        if missing(charge_day) & strtrim(charge_start_time) != ""
    replace charge_day = ///
        daily(substr(strtrim(charge_start_time), 1, 10), "MDY") ///
        if missing(charge_day) & strtrim(charge_start_time) != ""
}

format charge_day %tdCCYY-NN-DD
label variable charge_day "Charging date"

****************************************************
* 2.2 Parse discharge date
****************************************************

capture drop discharge_day

capture confirm numeric variable discharge_start_time
if !_rc {
    local discharge_fmt : format discharge_start_time
    quietly summarize discharge_start_time, meanonly

    if substr("`discharge_fmt'", 1, 3) == "%td" {
        gen double discharge_day = discharge_start_time
    }
    else if substr("`discharge_fmt'", 1, 3) == "%tc" {
        gen double discharge_day = dofc(discharge_start_time)
    }
    else if r(max) > 10000000 & r(max) < 30000000 {
        capture drop __discharge_str
        gen str8 __discharge_str = string(discharge_start_time, "%08.0f")
        gen double discharge_day = daily(__discharge_str, "YMD")
        drop __discharge_str
    }
    else if r(max) > 1000000000 & r(max) < 4000000000 {
        gen double discharge_day = ///
            dofc((discharge_start_time + 315619200) * 1000)
    }
    else if r(max) > 100000000000 {
        gen double discharge_day = dofc(discharge_start_time)
    }
    else {
        gen double discharge_day = discharge_start_time
    }
}
else {
    gen double discharge_day = ///
        daily(substr(strtrim(discharge_start_time), 1, 10), "YMD")
    replace discharge_day = ///
        daily(substr(strtrim(discharge_start_time), 1, 10), "DMY") ///
        if missing(discharge_day) & strtrim(discharge_start_time) != ""
    replace discharge_day = ///
        daily(substr(strtrim(discharge_start_time), 1, 10), "MDY") ///
        if missing(discharge_day) & strtrim(discharge_start_time) != ""
}

format discharge_day %tdCCYY-NN-DD
label variable discharge_day "V2G discharge date"

quietly count if missing(charge_day)
di as txt "Rows with missing charge_day = " r(N)

quietly count if missing(discharge_day)
di as txt "Rows with missing discharge_day = " r(N)

****************************************************
* 2.3 Construct fixed-effect variables
****************************************************

capture drop province_id
egen int province_id = group(province), label
label variable province_id "Numeric province ID"

capture drop car_type_id
egen int car_type_id = group(car_type), label
label variable car_type_id "Numeric vehicle-type ID"

capture drop charge_week
gen int charge_week = wofd(charge_day)
format charge_week %tw
label variable charge_week "Calendar week of charging event"

capture drop province_week_fe
egen long province_week_fe = group(province_id charge_week)
label variable province_week_fe "Province-by-calendar-week FE"

capture drop weekend
gen byte weekend = inlist(dow(charge_day), 0, 6) if !missing(charge_day)
label define weekend_lbl 0 "Weekday" 1 "Weekend", replace
label values weekend weekend_lbl
label variable weekend "Weekend indicator"

****************************************************
* 2.4 Construct public-holiday indicator
****************************************************

capture drop holiday_group
capture confirm string variable holiday
if !_rc {
    gen byte holiday_group = real(strtrim(holiday))

    replace holiday_group = 1 ///
        if holiday_group > 0 & !missing(holiday_group)
    replace holiday_group = 0 if holiday_group == 0

    * Chinese terms below are raw-data values used for matching and are intentionally retained.
    replace holiday_group = 1 if ///
        ustrregexm(lower(strtrim(holiday)), ///
        "yes|true|holiday|weekend|节假日|周末|休息日")

    replace holiday_group = 0 if ///
        ustrregexm(lower(strtrim(holiday)), ///
        "no|false|weekday|工作日|非节假日|调休上班")
}
else {
    gen byte holiday_group = .
    replace holiday_group = 0 if holiday == 0
    replace holiday_group = 1 if holiday != 0 & !missing(holiday)
}

replace holiday_group = . if !inlist(holiday_group, 0, 1)

label define holiday_lbl 0 "Non-holiday" 1 "Holiday", replace
label values holiday_group holiday_lbl
label variable holiday_group "Public-holiday indicator"

tab holiday_group weekend, missing

****************************************************
* 2.5 Log-transform charging energy and duration
****************************************************

capture drop ln_y3_chg_energy ln_y4_chg_duration_h

gen double ln_y3_chg_energy = ln(y3_chg_energy + 1) ///
    if !missing(y3_chg_energy) & y3_chg_energy >= 0
label variable ln_y3_chg_energy "ln(charging energy + 1)"

gen double ln_y4_chg_duration_h = ln(y4_chg_duration_h + 1) ///
    if !missing(y4_chg_duration_h) & y4_chg_duration_h >= 0
label variable ln_y4_chg_duration_h "ln(charging duration + 1)"

****************************************************
* 3. Construct analysis windows and treatment indicators
****************************************************

drop if missing(rel_int) | missing(post)
keep if inrange(rel_int, -10, 10)
drop if rel_int == 0
drop if missing(charge_day, discharge_day, province_week_fe)

capture drop sample_complete20
gen byte sample_complete20 = complete20_calc == 1
label variable sample_complete20 "Complete event window: 10 charges before and after discharge"

****************************************************
* 3.1 Define estimation samples
****************************************************

capture drop sample_main_m5
gen byte sample_main_m5 = sample_complete20 == 1 & ///
    (inrange(rel_int, -10, -5) | inrange(rel_int, 1, 10))
label variable sample_main_m5 "Main sample: events -10 to -5 vs 1 to 10"

capture drop sample_firstpost_m5
gen byte sample_firstpost_m5 = sample_complete20 == 1 & ///
    (inrange(rel_int, -10, -5) | rel_int == 1)
label variable sample_firstpost_m5 "First post-discharge charge: events -10 to -5 vs event 1"

capture drop sample_post2plus_m5
gen byte sample_post2plus_m5 = sample_complete20 == 1 & ///
    (inrange(rel_int, -10, -5) | inrange(rel_int, 2, 10))
label variable sample_post2plus_m5 "Subsequent post-discharge charges: events -10 to -5 vs events 2 to 10"

capture drop sample_anticipation_pre_m5
gen byte sample_anticipation_pre_m5 = sample_complete20 == 1 & ///
    inrange(rel_int, -10, -1)
label variable sample_anticipation_pre_m5 ///
    "Anticipatory charging: events -10 to -5 vs -4 to -1"

****************************************************
* 3.2 Define treatment indicators
****************************************************

capture drop post_m5
gen byte post_m5 = inrange(rel_int, 1, 10) if sample_main_m5 == 1
replace post_m5 = 0 ///
    if sample_main_m5 == 1 & inrange(rel_int, -10, -5)
label variable post_m5 "Post-discharge: events 1 to 10; comparison: -10 to -5"

capture drop post1_only_m5
gen byte post1_only_m5 = rel_int == 1 if sample_firstpost_m5 == 1
replace post1_only_m5 = 0 ///
    if sample_firstpost_m5 == 1 & inrange(rel_int, -10, -5)
label variable post1_only_m5 "First post-discharge charge; comparison: -10 to -5"

capture drop post2plus_only_m5
gen byte post2plus_only_m5 = inrange(rel_int, 2, 10) ///
    if sample_post2plus_m5 == 1
replace post2plus_only_m5 = 0 ///
    if sample_post2plus_m5 == 1 & inrange(rel_int, -10, -5)
label variable post2plus_only_m5 "Subsequent post-discharge charges (2-10); comparison: -10 to -5"

capture drop anticipation_pre_m5
gen byte anticipation_pre_m5 = inrange(rel_int, -4, -1) ///
    if sample_anticipation_pre_m5 == 1
replace anticipation_pre_m5 = 0 ///
    if sample_anticipation_pre_m5 == 1 & inrange(rel_int, -10, -5)
label variable anticipation_pre_m5 ///
    "Anticipation window: events -4 to -1; comparison: -10 to -5"

****************************************************
* 3.3 Construct event-study categories and samples
****************************************************

capture drop rel_cat
gen byte rel_cat = rel_int + 11

label define relcat_lbl ///
    1  "-10" ///
    2  "-9"  ///
    3  "-8"  ///
    4  "-7"  ///
    5  "-6"  ///
    6  "-5"  ///
    7  "-4"  ///
    8  "-3"  ///
    9  "-2"  ///
    10 "-1"  ///
    12 "1"   ///
    13 "2"   ///
    14 "3"   ///
    15 "4"   ///
    16 "5"   ///
    17 "6"   ///
    18 "7"   ///
    19 "8"   ///
    20 "9"   ///
    21 "10", replace

label values rel_cat relcat_lbl
label variable rel_cat "Relative charging-event category"

capture drop sample_firstpost_es_m5
gen byte sample_firstpost_es_m5 = sample_complete20 == 1 & ///
    (inrange(rel_int, -10, -5) | rel_int == 1)
label variable sample_firstpost_es_m5 ///
    "Event study: events -10 to -5 and event 1"

capture drop sample_post2plus_es_m5
gen byte sample_post2plus_es_m5 = sample_complete20 == 1 & ///
    (inrange(rel_int, -10, -5) | inrange(rel_int, 2, 10))
label variable sample_post2plus_es_m5 ///
    "Event study: events -10 to -5 and events 2 to 10"

* Anticipatory charging adjustments
* Reference event
capture drop sample_anticipation_es_m5
gen byte sample_anticipation_es_m5 = sample_complete20 == 1 & ///
    inrange(rel_int, -10, -1)
label variable sample_anticipation_es_m5 ///
    "Anticipatory event study: events -10 to -1; reference event -5"

quietly count if sample_firstpost_es_m5 == 1 & inrange(rel_int, -4, -1)
assert r(N) == 0

quietly count if sample_post2plus_es_m5 == 1 & inrange(rel_int, -4, -1)
assert r(N) == 0

quietly count if sample_anticipation_es_m5 == 1 & inrange(rel_int, 1, 10)
assert r(N) == 0

****************************************************
* 3.4 Prepare cumulative discharge-frequency variable
****************************************************

capture confirm numeric variable vehicle_discharge_count_desc
if _rc {
    capture destring vehicle_discharge_count_desc, ///
        replace ignore(",+ ")
    if _rc {
        di as error ///
            "Error: vehicle_discharge_count_desc cannot be converted to numeric."
        exit 109
    }
}

****************************************************
* 3.5 Prepare vehicle-type heterogeneity samples
****************************************************

capture drop car_type_str
capture confirm string variable car_type
if !_rc {
    gen str80 car_type_str = strtrim(car_type)
}
else {
    capture decode car_type, gen(car_type_str)
    if _rc gen str80 car_type_str = string(car_type)
    replace car_type_str = strtrim(car_type_str)
}

capture drop car_type_hetero_key exclude_car_type_hetero

gen str80 car_type_hetero_key = ustrtrim(car_type_str)
replace car_type_hetero_key = ///
    subinstr(car_type_hetero_key, " ", "", .)
replace car_type_hetero_key = ///
    subinstr(car_type_hetero_key, "　", "", .)

* Chinese vehicle-type strings below are raw-data category values and are intentionally retained.
gen byte exclude_car_type_hetero = ///
    inlist(car_type_hetero_key, ///
        "通勤客车", ///
        "环卫特种车", ///
        "旅游客车", ///
        "工程特种车", ///
        "公路客车")
replace exclude_car_type_hetero = 0 if missing(exclude_car_type_hetero)

label define exclude_car_hetero_lbl ///
    0 "Retained" 1 "Excluded from vehicle-type heterogeneity", replace
label values exclude_car_type_hetero exclude_car_hetero_lbl

capture drop sample_hetero_first_m5 ///
    sample_hetero_post2plus_m5 ///
    sample_hetero_anticipation_m5

gen byte sample_hetero_first_m5 = ///
    sample_firstpost_m5 == 1 & exclude_car_type_hetero == 0

gen byte sample_hetero_post2plus_m5 = ///
    sample_post2plus_m5 == 1 & exclude_car_type_hetero == 0

gen byte sample_hetero_anticipation_m5 = ///
    sample_anticipation_pre_m5 == 1 & exclude_car_type_hetero == 0

preserve
    keep if sample_complete20 == 1 & !missing(car_type_id)
    keep car_type_id car_type_str car_type_hetero_key exclude_car_type_hetero
    duplicates drop
    sort exclude_car_type_hetero car_type_id
    export excel using "$out/03_car_type_heterogeneity_exclusion_check.xlsx", ///
        firstrow(variables) replace
restore

****************************************************
* 4. Install and check required packages
****************************************************

cap which ftools
if _rc ssc install ftools, replace

cap which reghdfe
if _rc ssc install reghdfe, replace

cap which reghdfe
if _rc {
    di as error "Error: reghdfe could not be installed; analysis cannot continue."
    exit 199
}


****************************************************
* 5. Construct variables for SI robustness analyses
****************************************************

* 5.1 Construct calendar variables for fixed-effect sensitivity
capture drop charge_month
 gen int charge_month = mofd(charge_day)
format charge_month %tm
label variable charge_month "Charging calendar month"

capture drop province_month_fe
 egen long province_month_fe = group(province_id charge_month)
label variable province_month_fe "Province × Calendar Month FE"

capture drop sample_firstpost_es_refpre
 gen byte sample_firstpost_es_refpre = sample_complete20 == 1 & ///
    (inrange(rel_int,-10,-1) | rel_int==1)
label variable sample_firstpost_es_refpre ///
    "ES robustness: rel -10~-1 and rel 1"

capture drop sample_post2plus_es_refpre
 gen byte sample_post2plus_es_refpre = sample_complete20 == 1 & ///
    (inrange(rel_int,-10,-1) | inrange(rel_int,2,10))
label variable sample_post2plus_es_refpre ///
    "ES robustness: rel -10~-1 and rel 2~10"

****************************************************
* 6. Run switches
****************************************************

* 1 = run; 0 = skip
global run_es_ref_robustness     1
global run_fe_main_static        1
global run_fe_eventstudy         1
global run_fe_vehicle_hetero     1
global run_fe_holiday_hetero     1
global run_fe_count_threshold    1

****************************************************
* 7. Define SI result-collection programs
****************************************************

capture program drop _si_post_direct
program define _si_post_direct
    version 16.0
    syntax, POSTH(name) ANALYSIS(string) WINDOW(string) OUTCOME(string) ///
        GROUP(string) TERM(string) FESPEC(string) REFERENCEEVENT(real) ///
        REL(real) THRESHOLD(real) [REFZERO]

    local Nobs = e(N)
    local df = e(df_r)
    capture local r2 = e(r2)
    if _rc local r2 = .
    capture local r2adj = e(r2_a)
    if _rc local r2adj = .
    capture local r2within = e(r2_within)
    if _rc local r2within = .

    tempvar es tagv tage
    gen byte `es' = e(sample)
    egen byte `tagv' = tag(vehicle_id) if `es'==1
    quietly count if `tagv'==1
    local Nv = r(N)
    egen byte `tage' = tag(event_id) if `es'==1
    quietly count if `tage'==1
    local Ne = r(N)

    capture local cons = _b[_cons]
    if _rc {
        local cons = .
        local consse = .
        local consp = .
        local constatus "not retained by estimator"
    }
    else {
        capture local consse = _se[_cons]
        if _rc local consse = .
        if missing(`consse') | `consse'==0 | missing(`df') local consp = .
        else local consp = 2*ttail(`df',abs(`cons'/`consse'))
        if "`fespec'"=="FE1_no_FE" local constatus "reported; standard OLS intercept"
        else local constatus "reported; FE-normalization dependent"
    }

    if "`refzero'"!="" {
        local b=0
        local se=0
        local t=.
        local p=.
        local lb=0
        local ub=0
        local status "reference event"
    }
    else {
        capture local b = _b[`term']
        if _rc {
            local b=.
            local se=.
            local t=.
            local p=.
            local lb=.
            local ub=.
            local status "term not estimated or omitted"
        }
        else {
            local se = _se[`term']
            if missing(`se') | `se'==0 | missing(`df') {
                local t=.
                local p=.
                local lb=.
                local ub=.
            }
            else {
                local t=`b'/`se'
                local p=2*ttail(`df',abs(`t'))
                local crit=invttail(`df',0.025)
                local lb=`b'-`crit'*`se'
                local ub=`b'+`crit'*`se'
            }
            local status "estimated"
        }
    }

    post `posth' ///
        ("`analysis'") ("`window'") ("`fespec'") (`referenceevent') ///
        ("`outcome'") ("`group'") (`rel') (`threshold') ("`term'") ///
        (`b') (`se') (`t') (`p') (`lb') (`ub') ///
        (`Nobs') (`Nv') (`Ne') (`r2') (`r2adj') (`r2within') ///
        (`cons') (`consse') (`consp') ("`constatus'") ("`status'")
end

capture program drop _si_post_lincom
program define _si_post_lincom
    version 16.0
    syntax, POSTH(name) ANALYSIS(string) WINDOW(string) OUTCOME(string) ///
        GROUP(string) TERM(string) EXPRESSION(string asis) ///
        FESPEC(string) REFERENCEEVENT(real) REL(real) THRESHOLD(real)

    local Nobs=e(N)
    local df=e(df_r)
    capture local r2=e(r2)
    if _rc local r2=.
    capture local r2adj=e(r2_a)
    if _rc local r2adj=.
    capture local r2within=e(r2_within)
    if _rc local r2within=.

    tempvar es tagv tage
    gen byte `es'=e(sample)
    egen byte `tagv'=tag(vehicle_id) if `es'==1
    quietly count if `tagv'==1
    local Nv=r(N)
    egen byte `tage'=tag(event_id) if `es'==1
    quietly count if `tage'==1
    local Ne=r(N)

    capture local cons=_b[_cons]
    if _rc {
        local cons=.
        local consse=.
        local consp=.
        local constatus "not retained by estimator"
    }
    else {
        capture local consse=_se[_cons]
        if _rc local consse=.
        if missing(`consse') | `consse'==0 | missing(`df') local consp=.
        else local consp=2*ttail(`df',abs(`cons'/`consse'))
        if "`fespec'"=="FE1_no_FE" local constatus "reported; standard OLS intercept"
        else local constatus "reported; FE-normalization dependent"
    }

    capture noisily lincom `expression'
    if _rc {
        local b=.
        local se=.
        local t=.
        local p=.
        local lb=.
        local ub=.
        local status "lincom failed"
    }
    else {
        local b=r(estimate)
        local se=r(se)
        capture local dfl=r(df)
        if _rc local dfl=`df'
        if missing(`dfl') local dfl=`df'
        if missing(`se') | `se'==0 | missing(`dfl') {
            local t=.
            local p=.
            local lb=.
            local ub=.
        }
        else {
            local t=`b'/`se'
            local p=2*ttail(`dfl',abs(`t'))
            local crit=invttail(`dfl',0.025)
            local lb=`b'-`crit'*`se'
            local ub=`b'+`crit'*`se'
        }
        local status "estimated by lincom"
    }

    post `posth' ///
        ("`analysis'") ("`window'") ("`fespec'") (`referenceevent') ///
        ("`outcome'") ("`group'") (`rel') (`threshold') ("`term'") ///
        (`b') (`se') (`t') (`p') (`lb') (`ub') ///
        (`Nobs') (`Nv') (`Ne') (`r2') (`r2adj') (`r2within') ///
        (`cons') (`consse') (`consp') ("`constatus'") ("`status'")
end

capture program drop _si_post_missing
program define _si_post_missing
    version 16.0
    syntax, POSTH(name) ANALYSIS(string) WINDOW(string) OUTCOME(string) ///
        GROUP(string) TERM(string) FESPEC(string) REFERENCEEVENT(real) ///
        REL(real) THRESHOLD(real) STATUS(string) ///
        [VEHICLES(real .) EVENTS(real .)]

    post `posth' ///
        ("`analysis'") ("`window'") ("`fespec'") (`referenceevent') ///
        ("`outcome'") ("`group'") (`rel') (`threshold') ("`term'") ///
        (.) (.) (.) (.) (.) (.) ///
        (.) (`vehicles') (`events') (.) (.) (.) ///
        (.) (.) (.) ("not available") ("`status'")
end

****************************************************
* 7.1 Static regressions
****************************************************
capture program drop si_run_static
program define si_run_static
    version 16.0
    syntax, POSTH(name) SAMPLEVAR(name) TREATVAR(name) ANALYSIS(string) ///
        WINDOW(string) FESPEC(string) ABSORBVAR(string) [CONTROLVARS(string)]
    if `"`controlvars'"'=="" local controlvars "$controls_main"

    foreach y of global outcomes_article {
        di as result "SI static | `fespec' | `window' | `y'"
        if "`absorbvar'"=="NONE" {
            capture noisily regress `y' `treatvar' `controlvars' ///
                if `samplevar'==1 & !missing(`y',`treatvar'), ///
                vce(cluster vehicle_id)
        }
        else {
            capture noisily reghdfe `y' `treatvar' `controlvars' ///
                if `samplevar'==1 & !missing(`y',`treatvar'), ///
                absorb(`absorbvar') vce(cluster vehicle_id)
        }
        if _rc {
            _si_post_missing, posth(`posth') analysis("`analysis'") ///
                window("`window'") outcome("`y'") group("All vehicles") ///
                term("`treatvar'") fespec("`fespec'") referenceevent(.) ///
                rel(.) threshold(.) status("regression failed")
        }
        else {
            _si_post_direct, posth(`posth') analysis("`analysis'") ///
                window("`window'") outcome("`y'") group("All vehicles") ///
                term("`treatvar'") fespec("`fespec'") referenceevent(.) ///
                rel(.) threshold(.)
        }
    }
end

****************************************************
****************************************************
capture program drop si_run_eventstudy
program define si_run_eventstudy
    version 16.0
    syntax, POSTH(name) SAMPLEVAR(name) WINDOW(string) RELLIST(numlist integer) ///
        BASEREL(integer) ANALYSIS(string) FESPEC(string) ABSORBVAR(string) ///
        [CONTROLVARS(string)]
    if `"`controlvars'"'=="" local controlvars "$controls_main"

    local basecat=`baserel'+11
    foreach y of global outcomes_article {
        di as result "SI ES | base=`baserel' | `fespec' | `window' | `y'"
        if "`absorbvar'"=="NONE" {
            capture noisily regress `y' ib`basecat'.rel_cat `controlvars' ///
                if `samplevar'==1 & !missing(`y',rel_cat), ///
                vce(cluster vehicle_id)
        }
        else {
            capture noisily reghdfe `y' ib`basecat'.rel_cat `controlvars' ///
                if `samplevar'==1 & !missing(`y',rel_cat), ///
                absorb(`absorbvar') vce(cluster vehicle_id)
        }

        if _rc {
            foreach r of numlist `rellist' {
                local cat=`r'+11
                _si_post_missing, posth(`posth') analysis("`analysis'") ///
                    window("`window'") outcome("`y'") group("All vehicles") ///
                    term("`cat'.rel_cat") fespec("`fespec'") ///
                    referenceevent(`baserel') rel(`r') threshold(.) ///
                    status("regression failed")
            }
        }
        else {
            foreach r of numlist `rellist' {
                local cat=`r'+11
                if `r'==`baserel' {
                    _si_post_direct, posth(`posth') analysis("`analysis'") ///
                        window("`window'") outcome("`y'") group("All vehicles") ///
                        term("`cat'.rel_cat") fespec("`fespec'") ///
                        referenceevent(`baserel') rel(`r') threshold(.) refzero
                }
                else {
                    _si_post_direct, posth(`posth') analysis("`analysis'") ///
                        window("`window'") outcome("`y'") group("All vehicles") ///
                        term("`cat'.rel_cat") fespec("`fespec'") ///
                        referenceevent(`baserel') rel(`r') threshold(.)
                }
            }
        }
    }
end

****************************************************
****************************************************
capture program drop si_run_group
program define si_run_group
    version 16.0
    syntax, POSTH(name) SAMPLEVAR(name) TREATVAR(name) GROUPVAR(name) ///
        ANALYSIS(string) WINDOW(string) FESPEC(string) ABSORBVAR(string) ///
        [CONTROLVARS(string) MINVEHICLES(integer 1)]
    if `"`controlvars'"'=="" local controlvars "$controls_main"

    quietly levelsof `groupvar' if `samplevar'==1 & !missing(`groupvar'), local(groups)
    local vallab : value label `groupvar'

    foreach g of local groups {
        local gname "`g'"
        if `"`vallab'"'!="" local gname : label `vallab' `g'
        local gname=subinstr(`"`gname'"',char(34),"'",.)

        tempvar tagv tage
        egen byte `tagv'=tag(vehicle_id) if `samplevar'==1 & `groupvar'==`g'
        quietly count if `tagv'==1
        local Nv=r(N)
        egen byte `tage'=tag(event_id) if `samplevar'==1 & `groupvar'==`g'
        quietly count if `tage'==1
        local Ne=r(N)

        foreach y of global outcomes_article {
            if `Nv'<`minvehicles' {
                _si_post_missing, posth(`posth') analysis("`analysis'") ///
                    window("`window'") outcome("`y'") group("`gname'") ///
                    term("`treatvar'") fespec("`fespec'") referenceevent(.) ///
                    rel(.) threshold(.) vehicles(`Nv') events(`Ne') ///
                    status("insufficient vehicles")
                continue
            }
            if "`absorbvar'"=="NONE" {
                capture noisily regress `y' `treatvar' `controlvars' ///
                    if `samplevar'==1 & `groupvar'==`g' & !missing(`y',`treatvar'), ///
                    vce(cluster vehicle_id)
            }
            else {
                capture noisily reghdfe `y' `treatvar' `controlvars' ///
                    if `samplevar'==1 & `groupvar'==`g' & !missing(`y',`treatvar'), ///
                    absorb(`absorbvar') vce(cluster vehicle_id)
            }
            if _rc {
                _si_post_missing, posth(`posth') analysis("`analysis'") ///
                    window("`window'") outcome("`y'") group("`gname'") ///
                    term("`treatvar'") fespec("`fespec'") referenceevent(.) ///
                    rel(.) threshold(.) vehicles(`Nv') events(`Ne') ///
                    status("regression failed")
            }
            else {
                _si_post_direct, posth(`posth') analysis("`analysis'") ///
                    window("`window'") outcome("`y'") group("`gname'") ///
                    term("`treatvar'") fespec("`fespec'") referenceevent(.) ///
                    rel(.) threshold(.)
            }
        }
    }
end

****************************************************
****************************************************
capture program drop si_run_holiday_interaction
program define si_run_holiday_interaction
    version 16.0
    syntax, POSTH(name) SAMPLEVAR(name) TREATVAR(name) WINDOW(string) ///
        FESPEC(string) ABSORBVAR(string) [CONTROLVARS(string)]
    if `"`controlvars'"'=="" local controlvars "$controls_noholiday"

    foreach y of global outcomes_article {
        if "`absorbvar'"=="NONE" {
            capture noisily regress `y' ///
                ib0.`treatvar'##ib0.holiday_group `controlvars' ///
                if `samplevar'==1 & !missing(`y',`treatvar',holiday_group), ///
                vce(cluster vehicle_id)
        }
        else {
            capture noisily reghdfe `y' ///
                ib0.`treatvar'##ib0.holiday_group `controlvars' ///
                if `samplevar'==1 & !missing(`y',`treatvar',holiday_group), ///
                absorb(`absorbvar') vce(cluster vehicle_id)
        }
        if _rc {
            foreach g in "Non-holiday" "Holiday" "Holiday - Non-holiday" {
                _si_post_missing, posth(`posth') analysis("fe_holiday_interaction") ///
                    window("`window'") outcome("`y'") group("`g'") ///
                    term("holiday interaction") fespec("`fespec'") ///
                    referenceevent(.) rel(.) threshold(.) status("regression failed")
            }
        }
        else {
            _si_post_direct, posth(`posth') analysis("fe_holiday_interaction") ///
                window("`window'") outcome("`y'") group("Non-holiday") ///
                term("1.`treatvar'") fespec("`fespec'") referenceevent(.) ///
                rel(.) threshold(.)
            _si_post_lincom, posth(`posth') analysis("fe_holiday_interaction") ///
                window("`window'") outcome("`y'") group("Holiday") ///
                term("Holiday total effect") ///
                expression("1.`treatvar' + 1.`treatvar'#1.holiday_group") ///
                fespec("`fespec'") referenceevent(.) rel(.) threshold(.)
            _si_post_direct, posth(`posth') analysis("fe_holiday_interaction") ///
                window("`window'") outcome("`y'") group("Holiday - Non-holiday") ///
                term("1.`treatvar'#1.holiday_group") fespec("`fespec'") ///
                referenceevent(.) rel(.) threshold(.)
        }
    }
end

****************************************************
****************************************************
capture program drop si_run_threshold
program define si_run_threshold
    version 16.0
    syntax, POSTH(name) SAMPLEVAR(name) TREATVAR(name) WINDOW(string) ///
        COUNTVAR(name) FESPEC(string) ABSORBVAR(string) [CONTROLVARS(string)]
    if `"`controlvars'"'=="" local controlvars "$controls_main"

    forvalues c=1/20 {
        tempvar high taglow taghigh
        gen byte `high'=`countvar'>`c' if `samplevar'==1 & !missing(`countvar')
        egen byte `taglow'=tag(vehicle_id) if `samplevar'==1 & `high'==0
        quietly count if `taglow'==1
        local Nvl=r(N)
        egen byte `taghigh'=tag(vehicle_id) if `samplevar'==1 & `high'==1
        quietly count if `taghigh'==1
        local Nvh=r(N)

        foreach y of global outcomes_article {
            if `Nvl'==0 | `Nvh'==0 {
                foreach g in "Count <= c" "Count > c" "Count > c minus Count <= c" {
                    _si_post_missing, posth(`posth') analysis("fe_count_threshold") ///
                        window("`window'") outcome("`y'") group("`g'") ///
                        term("count threshold interaction") fespec("`fespec'") ///
                        referenceevent(.) rel(.) threshold(`c') ///
                        status("one threshold group is empty")
                }
                continue
            }
            if "`absorbvar'"=="NONE" {
                capture noisily regress `y' ///
                    ib0.`treatvar'##ib0.`high' `controlvars' ///
                    if `samplevar'==1 & !missing(`y',`treatvar',`high'), ///
                    vce(cluster vehicle_id)
            }
            else {
                capture noisily reghdfe `y' ///
                    ib0.`treatvar'##ib0.`high' `controlvars' ///
                    if `samplevar'==1 & !missing(`y',`treatvar',`high'), ///
                    absorb(`absorbvar') vce(cluster vehicle_id)
            }
            if _rc {
                foreach g in "Count <= c" "Count > c" "Count > c minus Count <= c" {
                    _si_post_missing, posth(`posth') analysis("fe_count_threshold") ///
                        window("`window'") outcome("`y'") group("`g'") ///
                        term("count threshold interaction") fespec("`fespec'") ///
                        referenceevent(.) rel(.) threshold(`c') status("regression failed")
                }
            }
            else {
                _si_post_direct, posth(`posth') analysis("fe_count_threshold") ///
                    window("`window'") outcome("`y'") group("Count <= c") ///
                    term("1.`treatvar'") fespec("`fespec'") referenceevent(.) ///
                    rel(.) threshold(`c')
                _si_post_lincom, posth(`posth') analysis("fe_count_threshold") ///
                    window("`window'") outcome("`y'") group("Count > c") ///
                    term("high-group total effect") ///
                    expression("1.`treatvar' + 1.`treatvar'#1.`high'") ///
                    fespec("`fespec'") referenceevent(.) rel(.) threshold(`c')
                _si_post_direct, posth(`posth') analysis("fe_count_threshold") ///
                    window("`window'") outcome("`y'") ///
                    group("Count > c minus Count <= c") ///
                    term("1.`treatvar'#1.`high'") fespec("`fespec'") ///
                    referenceevent(.) rel(.) threshold(`c')
            }
        }
    }
end

****************************************************
****************************************************
tempfile si_results
tempname SI
postfile `SI' ///
    str40 analysis str32 window str48 fe_spec double reference_event ///
    str48 outcome str120 group double rel double threshold str160 term ///
    double coefficient double se double t_statistic double p_value ///
    double ci_lower_95 double ci_upper_95 ///
    double observations double vehicles double events ///
    double r2 double r2_adjusted double r2_within ///
    double constant double constant_se double constant_p_value ///
    str80 constant_status str60 model_status ///
    using `si_results', replace

****************************************************
* 9. Robustness A: event -1 / event -2 as omitted reference
****************************************************
if $run_es_ref_robustness == 1 {
    foreach b in -1 -2 {
        si_run_eventstudy, posth(`SI') ///
            samplevar(sample_firstpost_es_refpre) window("first_post_1") ///
            rellist(-10 -9 -8 -7 -6 -5 -4 -3 -2 -1 1) baserel(`b') ///
            analysis("es_reference_robustness") ///
            fespec("MAIN_vehicle_provinceweek") ///
            absorbvar("vehicle_id province_week_fe") ///
            controlvars("$controls_main")

        si_run_eventstudy, posth(`SI') ///
            samplevar(sample_post2plus_es_refpre) window("later_post_2_10") ///
            rellist(-10 -9 -8 -7 -6 -5 -4 -3 -2 -1 2 3 4 5 6 7 8 9 10) ///
            baserel(`b') analysis("es_reference_robustness") ///
            fespec("MAIN_vehicle_provinceweek") ///
            absorbvar("vehicle_id province_week_fe") ///
            controlvars("$controls_main")
    }
}

****************************************************
* 10. Fixed-effect sensitivity specifications
****************************************************
* FE1: no fixed effects
* FE2: vehicle FE only
* FE3: calendar-week FE only
* FE4: province×calendar-week FE only
*
* The main benchmark is not re-estimated in this loop

local fe_specs ///
    FE1_no_FE ///
    FE2_vehicle_only ///
    FE3_week_only ///
    FE4_provinceweek_only

foreach fs of local fe_specs {
    if "`fs'"=="FE1_no_FE"              local ABS "NONE"
    if "`fs'"=="FE2_vehicle_only"       local ABS "vehicle_id"
    if "`fs'"=="FE3_week_only"          local ABS "charge_week"
    if "`fs'"=="FE4_provinceweek_only"  local ABS "province_week_fe"

    di as text "============================================================"
    di as result "Running FE sensitivity: `fs'"
    if "`ABS'"=="NONE" di as text "No absorbed fixed effects; OLS with vehicle-clustered SE"
    else               di as text "absorb(`ABS')"
    di as text "============================================================"

    ****************************************************
    * 10.1 Main post-discharge regressions
    ****************************************************
    if $run_fe_main_static == 1 {
        si_run_static, posth(`SI') samplevar(sample_main_m5) ///
            treatvar(post_m5) analysis("fe_main_static") ///
            window("all_post_1_10") fespec("`fs'") absorbvar("`ABS'") ///
            controlvars("$controls_main")

        si_run_static, posth(`SI') samplevar(sample_firstpost_m5) ///
            treatvar(post1_only_m5) analysis("fe_main_static") ///
            window("first_post_1") fespec("`fs'") absorbvar("`ABS'") ///
            controlvars("$controls_main")

        si_run_static, posth(`SI') samplevar(sample_post2plus_m5) ///
            treatvar(post2plus_only_m5) analysis("fe_main_static") ///
            window("later_post_2_10") fespec("`fs'") absorbvar("`ABS'") ///
            controlvars("$controls_main")
    }

    ****************************************************
    ****************************************************
    if $run_fe_eventstudy == 1 {
        si_run_eventstudy, posth(`SI') samplevar(sample_firstpost_es_m5) ///
            window("first_post_1") rellist(-10 -9 -8 -7 -6 -5 1) ///
            baserel(-5) analysis("fe_event_study") fespec("`fs'") ///
            absorbvar("`ABS'") controlvars("$controls_main")

        si_run_eventstudy, posth(`SI') samplevar(sample_post2plus_es_m5) ///
            window("later_post_2_10") ///
            rellist(-10 -9 -8 -7 -6 -5 2 3 4 5 6 7 8 9 10) ///
            baserel(-5) analysis("fe_event_study") fespec("`fs'") ///
            absorbvar("`ABS'") controlvars("$controls_main")
    }

    ****************************************************
    * 10.3 Vehicle-type heterogeneity
    ****************************************************
    if $run_fe_vehicle_hetero == 1 {
        si_run_group, posth(`SI') samplevar(sample_hetero_first_m5) ///
            treatvar(post1_only_m5) groupvar(car_type_id) ///
            analysis("fe_vehicle_heterogeneity") window("first_post_1") ///
            fespec("`fs'") absorbvar("`ABS'") controlvars("$controls_main") ///
            minvehicles($min_car_type_vehicles)

        si_run_group, posth(`SI') samplevar(sample_hetero_post2plus_m5) ///
            treatvar(post2plus_only_m5) groupvar(car_type_id) ///
            analysis("fe_vehicle_heterogeneity") window("later_post_2_10") ///
            fespec("`fs'") absorbvar("`ABS'") controlvars("$controls_main") ///
            minvehicles($min_car_type_vehicles)
    }

    ****************************************************
    ****************************************************
    if $run_fe_holiday_hetero == 1 {
        si_run_group, posth(`SI') samplevar(sample_firstpost_m5) ///
            treatvar(post1_only_m5) groupvar(holiday_group) ///
            analysis("fe_holiday_group") window("first_post_1") ///
            fespec("`fs'") absorbvar("`ABS'") ///
            controlvars("$controls_noholiday") minvehicles(1)

        si_run_group, posth(`SI') samplevar(sample_post2plus_m5) ///
            treatvar(post2plus_only_m5) groupvar(holiday_group) ///
            analysis("fe_holiday_group") window("later_post_2_10") ///
            fespec("`fs'") absorbvar("`ABS'") ///
            controlvars("$controls_noholiday") minvehicles(1)

        si_run_holiday_interaction, posth(`SI') ///
            samplevar(sample_firstpost_m5) treatvar(post1_only_m5) ///
            window("first_post_1") fespec("`fs'") absorbvar("`ABS'") ///
            controlvars("$controls_noholiday")

        si_run_holiday_interaction, posth(`SI') ///
            samplevar(sample_post2plus_m5) treatvar(post2plus_only_m5) ///
            window("later_post_2_10") fespec("`fs'") absorbvar("`ABS'") ///
            controlvars("$controls_noholiday")
    }

    ****************************************************
    * 10.5 Cumulative discharge-frequency heterogeneity
    ****************************************************
    if $run_fe_count_threshold == 1 {
        si_run_threshold, posth(`SI') samplevar(sample_firstpost_m5) ///
            treatvar(post1_only_m5) window("first_post_1") ///
            countvar(vehicle_discharge_count_desc) fespec("`fs'") ///
            absorbvar("`ABS'") controlvars("$controls_main")

        si_run_threshold, posth(`SI') samplevar(sample_post2plus_m5) ///
            treatvar(post2plus_only_m5) window("later_post_2_10") ///
            countvar(vehicle_discharge_count_desc) fespec("`fs'") ///
            absorbvar("`ABS'") controlvars("$controls_main")
    }
}

postclose `SI'

****************************************************
* 11. Export SI results
****************************************************
preserve
    use `si_results', clear

    capture drop constant_p_display
    gen str12 constant_p_display=""
    replace constant_p_display="<0.001" if !missing(constant_p_value) & constant_p_value<0.001
    replace constant_p_display=strtrim(string(constant_p_value,"%6.3f")) ///
        if !missing(constant_p_value) & constant_p_value>=0.001

    capture drop pct_effect
    gen double pct_effect=100*(exp(coefficient)-1) ///
        if inlist(outcome,"ln_y3_chg_energy","ln_y4_chg_duration_h") & !missing(coefficient)
    label variable pct_effect "For log outcomes: 100*(exp(beta)-1)"

    order analysis window fe_spec reference_event outcome group rel threshold term ///
        coefficient se t_statistic p_value ci_lower_95 ci_upper_95 pct_effect ///
        observations vehicles events r2 r2_adjusted r2_within ///
        constant constant_se constant_p_value constant_p_display ///
        constant_status model_status
    sort analysis fe_spec reference_event window outcome group threshold rel

    save "$out/V2G_SI_robustness_results.dta", replace
    export delimited using "$out/V2G_SI_robustness_results.csv", replace

    local xlsx "$out/V2G_SI_robustness_results.xlsx"
    export excel using "`xlsx'", sheet("00_all_results") firstrow(variables) replace

    * 01: event study, rel=-1 as reference
    use `si_results', clear
    keep if analysis=="es_reference_robustness" & reference_event==-1
    sort window outcome rel
    export excel using "`xlsx'", sheet("01_ES_ref_minus1", replace) firstrow(variables)

    * 02: event study, rel=-2 as reference
    use `si_results', clear
    keep if analysis=="es_reference_robustness" & reference_event==-2
    sort window outcome rel
    export excel using "`xlsx'", sheet("02_ES_ref_minus2", replace) firstrow(variables)

    * 03: FE sensitivity - main static
    use `si_results', clear
    keep if analysis=="fe_main_static"
    sort window outcome fe_spec
    export excel using "`xlsx'", sheet("03_FE_main_static", replace) firstrow(variables)

    * 04: FE sensitivity - benchmark event study (base=-5)
    use `si_results', clear
    keep if analysis=="fe_event_study"
    sort window outcome rel fe_spec
    export excel using "`xlsx'", sheet("04_FE_event_study", replace) firstrow(variables)

    * 05: FE sensitivity - vehicle type heterogeneity
    use `si_results', clear
    keep if analysis=="fe_vehicle_heterogeneity"
    sort window outcome group fe_spec
    export excel using "`xlsx'", sheet("05_FE_vehicle", replace) firstrow(variables)

    * 06: FE sensitivity - holiday grouped regressions
    use `si_results', clear
    keep if analysis=="fe_holiday_group"
    sort window outcome group fe_spec
    export excel using "`xlsx'", sheet("06_FE_holiday_group", replace) firstrow(variables)

    * 07: FE sensitivity - Holiday×Post formal interactions
    use `si_results', clear
    keep if analysis=="fe_holiday_interaction"
    sort window outcome group fe_spec
    export excel using "`xlsx'", sheet("07_FE_holiday_int", replace) firstrow(variables)

    * 08: FE sensitivity - discharge count threshold interactions
    use `si_results', clear
    keep if analysis=="fe_count_threshold"
    sort window outcome threshold group fe_spec
    export excel using "`xlsx'", sheet("08_FE_count", replace) firstrow(variables)

    clear
    set obs 5
    gen str40 fe_spec=""
    gen str100 absorbed_fixed_effects=""
    gen str140 interpretation=""
    replace fe_spec="FE1_no_FE" in 1
    replace absorbed_fixed_effects="None" in 1
    replace interpretation="No absorbed fixed effects; weekend/holiday controls retained; SE clustered by vehicle" in 1
    replace fe_spec="FE2_vehicle_only" in 2
    replace absorbed_fixed_effects="Vehicle FE" in 2
    replace interpretation="Controls time-invariant vehicle heterogeneity only" in 2
    replace fe_spec="FE3_week_only" in 3
    replace absorbed_fixed_effects="Calendar-week FE" in 3
    replace interpretation="Controls national week-specific common shocks only" in 3
    replace fe_spec="FE4_provinceweek_only" in 4
    replace absorbed_fixed_effects="Province×Calendar-week FE" in 4
    replace interpretation="Controls province-specific weekly shocks only" in 4
    replace fe_spec="MAIN_vehicle_provinceweek" in 5
    replace absorbed_fixed_effects="Vehicle FE + Province×Calendar-week FE" in 5
    replace interpretation="Main-text benchmark; shown here for reference only, not re-estimated in FE-sensitivity loop" in 5
    export excel using "`xlsx'", sheet("09_FE_legend", replace) firstrow(variables)
restore

****************************************************
* 12. Return to the original data frame
****************************************************

frame change `original_frame'
capture frame drop si_work

di as result "=================================================="
di as result "SI robustness analysis completed."
di as result "Returned to original data frame: `original_frame'"
di as result "The original data frame was not modified."
di as result "=================================================="

****************************************************
* 12. Completion
****************************************************
log close

di as result "SI robustness analysis completed."
di as result "Output folder: $out"
di as result "Main workbook: $out/V2G_SI_robustness_results.xlsx"
