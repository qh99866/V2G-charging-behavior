****************************************************
* Vehicle-to-grid discharge reshapes electric vehicle charging behavior
* Main analysis
*
* This script reproduces the main post-discharge, event-study,
* heterogeneity, and anticipatory charging analyses in the manuscript.
*
* Required restricted data:
*   data/private/analysis_data.dta
*
* Output directory:
*   results/main/
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

* Run this script from the repository root.
global project "`c(pwd)'"
global data    "$project/data/private"
global out     "$project/results/main"

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
log using "$out/00_V2G_article_results_only.log", text replace

global min_car_type_vehicles 5
global controls_main      "i.weekend i.holiday_group"
global controls_noholiday "i.weekend"
global absorb_main        "vehicle_id province_week_fe"
global outcomes_article ///
    "y1_chg_start_soc y2_chg_end_soc ln_y3_chg_energy ln_y4_chg_duration_h"

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
* 5. Define result-collection programs
****************************************************

****************************************************
* 5.1 Collect statistics from current reghdfe model
****************************************************

capture program drop _post_direct_result
program define _post_direct_result
    version 16.0

    syntax, POSTH(name) ANALYSIS(string) WINDOW(string) ///
        OUTCOME(string) GROUP(string) TERM(string) ///
        REL(real) THRESHOLD(real) [REFZERO]

    local Nobs = e(N)
    local df = e(df_r)

    capture local r2 = e(r2)
    if _rc local r2 = .

    capture local r2adj = e(r2_a)
    if _rc local r2adj = .

    tempvar es tag_vehicle tag_event
    gen byte `es' = e(sample)

    egen byte `tag_vehicle' = tag(vehicle_id) if `es' == 1
    quietly count if `tag_vehicle' == 1
    local N_vehicle = r(N)

    egen byte `tag_event' = tag(event_id) if `es' == 1
    quietly count if `tag_event' == 1
    local N_event = r(N)

	tempname cons consse

	capture scalar `cons' = _b[_cons]

	if _rc {
		local constant = .
		local constant_se = .
		local constant_p_value = .
		local constant_status "not retained by reghdfe"
	}
	else {
		local constant = scalar(`cons')

		capture scalar `consse' = _se[_cons]

		if _rc {
			local constant_se = .
			local constant_p_value = .
		}
		else {
			local constant_se = scalar(`consse')

			if missing(`constant_se') | ///
				`constant_se' == 0 | ///
				missing(`df') {

				local constant_p_value = .
			}
			else {
				local constant_t = ///
					`constant' / `constant_se'

				local constant_p_value = ///
					2 * ttail(`df', abs(`constant_t'))
			}
		}

		local constant_status ///
			"reported; FE-normalization dependent"
	}

    if "`refzero'" != "" {
        local b = 0
        local se = 0
        local t = .
        local p = .
        local lb = 0
        local ub = 0
        local model_status "reference event"
    }
    else {
        tempname bsc sesc
        capture scalar `bsc' = _b[`term']
        if _rc {
            local b = .
            local se = .
            local t = .
            local p = .
            local lb = .
            local ub = .
            local model_status "term not estimated or omitted"
        }
        else {
            scalar `sesc' = _se[`term']
            local b = scalar(`bsc')
            local se = scalar(`sesc')

            if missing(`se') | `se' == 0 | missing(`df') {
                local t = .
                local p = .
                local lb = .
                local ub = .
            }
            else {
                local t = `b' / `se'
                local p = 2 * ttail(`df', abs(`t'))
                local crit = invttail(`df', 0.025)
                local lb = `b' - `crit' * `se'
                local ub = `b' + `crit' * `se'
            }
            local model_status "estimated"
        }
    }

	post `posth' ///
		("`analysis'") ///
		("`window'") ///
		("`outcome'") ///
		("`group'") ///
		(`rel') ///
		(`threshold') ///
		("`term'") ///
		(`b') ///
		(`se') ///
		(`t') ///
		(`p') ///
		(`lb') ///
		(`ub') ///
		(`Nobs') ///
		(`N_vehicle') ///
		(`N_event') ///
		(`r2') ///
		(`r2adj') ///
		(`constant') ///
		(`constant_se') ///
		(`constant_p_value') ///
		("`constant_status'") ///
		("`model_status'")
end

****************************************************
* 5.2 Collect statistics from current reghdfe model
****************************************************

capture program drop _post_lincom_result
program define _post_lincom_result
    version 16.0

    syntax, POSTH(name) ANALYSIS(string) WINDOW(string) ///
        OUTCOME(string) GROUP(string) TERM(string) ///
        EXPRESSION(string asis) REL(real) THRESHOLD(real)

    local Nobs = e(N)
    local df = e(df_r)

    capture local r2 = e(r2)
    if _rc local r2 = .

    capture local r2adj = e(r2_a)
    if _rc local r2adj = .

    tempvar es tag_vehicle tag_event
    gen byte `es' = e(sample)

    egen byte `tag_vehicle' = tag(vehicle_id) if `es' == 1
    quietly count if `tag_vehicle' == 1
    local N_vehicle = r(N)

    egen byte `tag_event' = tag(event_id) if `es' == 1
    quietly count if `tag_event' == 1
    local N_event = r(N)

	tempname cons consse

	capture scalar `cons' = _b[_cons]

	if _rc {
		local constant = .
		local constant_se = .
		local constant_p_value = .
		local constant_status "not retained by reghdfe"
	}
	else {
		local constant = scalar(`cons')

		capture scalar `consse' = _se[_cons]

		if _rc {
			local constant_se = .
			local constant_p_value = .
		}
		else {
			local constant_se = scalar(`consse')

			if missing(`constant_se') | ///
				`constant_se' == 0 | ///
				missing(`df') {

				local constant_p_value = .
			}
			else {
				local constant_t = ///
					`constant' / `constant_se'

				local constant_p_value = ///
					2 * ttail(`df', abs(`constant_t'))
			}
		}

		local constant_status ///
			"reported; FE-normalization dependent"
	}

    capture noisily lincom `expression'
    if _rc {
        local b = .
        local se = .
        local t = .
        local p = .
        local lb = .
        local ub = .
        local model_status "lincom failed"
    }
    else {
        local b = r(estimate)
        local se = r(se)

        capture local df_lincom = r(df)
        if _rc local df_lincom = `df'
        if missing(`df_lincom') local df_lincom = `df'

        if missing(`se') | `se' == 0 | missing(`df_lincom') {
            local t = .
            local p = .
            local lb = .
            local ub = .
        }
        else {
            local t = `b' / `se'
            local p = 2 * ttail(`df_lincom', abs(`t'))
            local crit = invttail(`df_lincom', 0.025)
            local lb = `b' - `crit' * `se'
            local ub = `b' + `crit' * `se'
        }
        local model_status "estimated by lincom"
    }

	post `posth' ///
		("`analysis'") ///
		("`window'") ///
		("`outcome'") ///
		("`group'") ///
		(`rel') ///
		(`threshold') ///
		("`term'") ///
		(`b') ///
		(`se') ///
		(`t') ///
		(`p') ///
		(`lb') ///
		(`ub') ///
		(`Nobs') ///
		(`N_vehicle') ///
		(`N_event') ///
		(`r2') ///
		(`r2adj') ///
		(`constant') ///
		(`constant_se') ///
		(`constant_p_value') ///
		("`constant_status'") ///
		("`model_status'")
end

****************************************************
* 5.3 Post missing results when estimation fails or sample is insufficient
****************************************************

capture program drop _post_missing_result
program define _post_missing_result
    version 16.0

    syntax, POSTH(name) ANALYSIS(string) WINDOW(string) ///
        OUTCOME(string) GROUP(string) TERM(string) ///
        REL(real) THRESHOLD(real) STATUS(string) ///
        [VEHICLES(real .) EVENTS(real .)]

    post `posth' ///
		("`analysis'") ///
		("`window'") ///
		("`outcome'") ///
		("`group'") ///
		(`rel') ///
		(`threshold') ///
		("`term'") ///
		(.) (.) (.) (.) (.) (.) ///
		(.) (`vehicles') (`events') ///
		(.) (.) ///
		(.) (.) (.) ///
		("not available") ///
		("`status'")
end

****************************************************
* 5.4 Main post-discharge regressions
****************************************************

capture program drop run_static_collect
program define run_static_collect
    version 16.0

    syntax, POSTH(name) SAMPLEVAR(name) TREATVAR(name) ///
        ANALYSIS(string) WINDOW(string) ///
        [CONTROLVARS(string) ABSORBVAR(string)]

    if `"`absorbvar'"' == "" local absorbvar "$absorb_main"
    if `"`controlvars'"' == "" local controlvars "$controls_main"

    foreach y of global outcomes_article {
        di as result "Static regression: `analysis' | `window' | `y'"

        capture noisily reghdfe `y' `treatvar' `controlvars' ///
            if `samplevar' == 1 & !missing(`y', `treatvar'), ///
            absorb(`absorbvar') ///
            vce(cluster vehicle_id)

        if _rc {
            _post_missing_result, ///
                posth(`posth') ///
                analysis("`analysis'") ///
                window("`window'") ///
                outcome("`y'") ///
                group("All vehicles") ///
                term("`treatvar'") ///
                rel(.) threshold(.) ///
                status("reghdfe failed")
        }
        else {
            _post_direct_result, ///
                posth(`posth') ///
                analysis("`analysis'") ///
                window("`window'") ///
                outcome("`y'") ///
                group("All vehicles") ///
                term("`treatvar'") ///
                rel(.) threshold(.)
        }
    }
end

****************************************************
****************************************************

capture program drop run_eventstudy_collect
program define run_eventstudy_collect
    version 16.0

    syntax, POSTH(name) SAMPLEVAR(name) WINDOW(string) ///
        RELLIST(numlist integer) ///
        [CONTROLVARS(string) ABSORBVAR(string)]

    if `"`absorbvar'"' == "" local absorbvar "$absorb_main"
    if `"`controlvars'"' == "" local controlvars "$controls_main"

    foreach y of global outcomes_article {
        di as result "event study：`window' | `y'"

        capture noisily reghdfe `y' ib6.rel_cat `controlvars' ///
            if `samplevar' == 1 & !missing(`y', rel_cat), ///
            absorb(`absorbvar') ///
            vce(cluster vehicle_id)

        if _rc {
            foreach r of numlist `rellist' {
                local cat = `r' + 11
                _post_missing_result, ///
                    posth(`posth') ///
                    analysis("event_study") ///
                    window("`window'") ///
                    outcome("`y'") ///
                    group("All vehicles") ///
                    term("`cat'.rel_cat") ///
                    rel(`r') threshold(.) ///
                    status("reghdfe failed")
            }
        }
        else {
            foreach r of numlist `rellist' {
                local cat = `r' + 11

                if `r' == -5 {
                    _post_direct_result, ///
                        posth(`posth') ///
                        analysis("event_study") ///
                        window("`window'") ///
                        outcome("`y'") ///
                        group("All vehicles") ///
                        term("`cat'.rel_cat") ///
                        rel(`r') threshold(.) refzero
                }
                else {
                    _post_direct_result, ///
                        posth(`posth') ///
                        analysis("event_study") ///
                        window("`window'") ///
                        outcome("`y'") ///
                        group("All vehicles") ///
                        term("`cat'.rel_cat") ///
                        rel(`r') threshold(.)
                }
            }
        }
    }
end

****************************************************
* 5.6 Subgroup heterogeneity regressions
****************************************************

capture program drop run_group_collect
program define run_group_collect
    version 16.0

    syntax, POSTH(name) SAMPLEVAR(name) TREATVAR(name) ///
        GROUPVAR(name) ANALYSIS(string) WINDOW(string) ///
        [CONTROLVARS(string) ABSORBVAR(string) MINVEHICLES(integer 1)]

    if `"`absorbvar'"' == "" local absorbvar "$absorb_main"
    if `"`controlvars'"' == "" local controlvars "$controls_main"

    quietly levelsof `groupvar' ///
        if `samplevar' == 1 & !missing(`groupvar'), local(groups)

    if `"`groups'"' == "" {
        di as error "`analysis' | `window': no valid groups."
        exit
    }

    local vallab : value label `groupvar'

    foreach g of local groups {
        local gname "`g'"
        if `"`vallab'"' != "" {
            local gname : label `vallab' `g'
        }
        local gname = subinstr(`"`gname'"', char(34), "'", .)

        tempvar tagv tage
        egen byte `tagv' = tag(vehicle_id) ///
            if `samplevar' == 1 & `groupvar' == `g'
        quietly count if `tagv' == 1
        local Nv = r(N)

        egen byte `tage' = tag(event_id) ///
            if `samplevar' == 1 & `groupvar' == `g'
        quietly count if `tage' == 1
        local Ne = r(N)

        di as txt "`analysis' | `window' | `gname': vehicles=`Nv', events=`Ne'"

        foreach y of global outcomes_article {
            if `Nv' < `minvehicles' {
                _post_missing_result, ///
                    posth(`posth') ///
                    analysis("`analysis'") ///
                    window("`window'") ///
                    outcome("`y'") ///
                    group("`gname'") ///
                    term("`treatvar'") ///
                    rel(.) threshold(.) ///
                    vehicles(`Nv') events(`Ne') ///
                    status("insufficient vehicles")
                continue
            }

            capture noisily reghdfe `y' `treatvar' `controlvars' ///
                if `samplevar' == 1 & `groupvar' == `g' & ///
                !missing(`y', `treatvar'), ///
                absorb(`absorbvar') ///
                vce(cluster vehicle_id)

            if _rc {
                _post_missing_result, ///
                    posth(`posth') ///
                    analysis("`analysis'") ///
                    window("`window'") ///
                    outcome("`y'") ///
                    group("`gname'") ///
                    term("`treatvar'") ///
                    rel(.) threshold(.) ///
                    vehicles(`Nv') events(`Ne') ///
                    status("reghdfe failed")
            }
            else {
                _post_direct_result, ///
                    posth(`posth') ///
                    analysis("`analysis'") ///
                    window("`window'") ///
                    outcome("`y'") ///
                    group("`gname'") ///
                    term("`treatvar'") ///
                    rel(.) threshold(.)
            }
        }
    }
end

****************************************************
* 5.7 Holiday interaction model
****************************************************

capture program drop run_holiday_interaction_collect
program define run_holiday_interaction_collect
    version 16.0

    syntax, POSTH(name) SAMPLEVAR(name) TREATVAR(name) ///
        WINDOW(string) [CONTROLVARS(string) ABSORBVAR(string)]

    if `"`absorbvar'"' == "" local absorbvar "$absorb_main"
    if `"`controlvars'"' == "" local controlvars "$controls_noholiday"

    foreach y of global outcomes_article {
        di as result "Holiday interaction: `window' | `y'"

        capture noisily reghdfe `y' ///
            ib0.`treatvar'##ib0.holiday_group `controlvars' ///
            if `samplevar' == 1 & ///
            !missing(`y', `treatvar', holiday_group), ///
            absorb(`absorbvar') ///
            vce(cluster vehicle_id)

        if _rc {
            foreach g in "Non-holiday" "Holiday" "Holiday - Non-holiday" {
                _post_missing_result, ///
                    posth(`posth') ///
                    analysis("holiday_interaction") ///
                    window("`window'") ///
                    outcome("`y'") ///
                    group("`g'") ///
                    term("holiday interaction") ///
                    rel(.) threshold(.) ///
                    status("reghdfe failed")
            }
        }
        else {
            * Post-discharge effect on non-holidays
            _post_direct_result, ///
                posth(`posth') ///
                analysis("holiday_interaction") ///
                window("`window'") ///
                outcome("`y'") ///
                group("Non-holiday") ///
                term("1.`treatvar'") ///
                rel(.) threshold(.)

            * Total post-discharge effect on holidays
            _post_lincom_result, ///
                posth(`posth') ///
                analysis("holiday_interaction") ///
                window("`window'") ///
                outcome("`y'") ///
                group("Holiday") ///
                term("1.`treatvar' + 1.`treatvar'#1.holiday_group") ///
                expression("1.`treatvar' + 1.`treatvar'#1.holiday_group") ///
                rel(.) threshold(.)

            * Holiday - Non-holiday interaction effect
            _post_direct_result, ///
                posth(`posth') ///
                analysis("holiday_interaction") ///
                window("`window'") ///
                outcome("`y'") ///
                group("Holiday - Non-holiday") ///
                term("1.`treatvar'#1.holiday_group") ///
                rel(.) threshold(.)
        }
    }
end

****************************************************
* 5.8 Cumulative discharge-frequency threshold interactions
****************************************************

capture program drop run_threshold_collect
program define run_threshold_collect
    version 16.0

    syntax, POSTH(name) SAMPLEVAR(name) TREATVAR(name) ///
        WINDOW(string) COUNTVAR(name) ///
        [CONTROLVARS(string) ABSORBVAR(string)]

    if `"`absorbvar'"' == "" local absorbvar "$absorb_main"
    if `"`controlvars'"' == "" local controlvars "$controls_main"

    forvalues c = 1/20 {
        tempvar high taglow taghigh

        gen byte `high' = `countvar' > `c' ///
            if `samplevar' == 1 & !missing(`countvar')

        egen byte `taglow' = tag(vehicle_id) ///
            if `samplevar' == 1 & `high' == 0
        quietly count if `taglow' == 1
        local Nvl = r(N)

        egen byte `taghigh' = tag(vehicle_id) ///
            if `samplevar' == 1 & `high' == 1
        quietly count if `taghigh' == 1
        local Nvh = r(N)

        di as txt "Discharge-frequency interaction | `window' | c=`c': vehicles <= c=`Nvl', vehicles > c=`Nvh'"

        foreach y of global outcomes_article {
            if `Nvl' == 0 | `Nvh' == 0 {
                foreach g in "Count <= c" "Count > c" "Count > c minus Count <= c" {
                    _post_missing_result, ///
                        posth(`posth') ///
                        analysis("count_threshold_interaction") ///
                        window("`window'") ///
                        outcome("`y'") ///
                        group("`g'") ///
                        term("count threshold interaction") ///
                        rel(.) threshold(`c') ///
                        status("one threshold group is empty")
                }
                continue
            }

            capture noisily reghdfe `y' ///
                ib0.`treatvar'##ib0.`high' `controlvars' ///
                if `samplevar' == 1 & ///
                !missing(`y', `treatvar', `high'), ///
                absorb(`absorbvar') ///
                vce(cluster vehicle_id)

            if _rc {
                foreach g in "Count <= c" "Count > c" "Count > c minus Count <= c" {
                    _post_missing_result, ///
                        posth(`posth') ///
                        analysis("count_threshold_interaction") ///
                        window("`window'") ///
                        outcome("`y'") ///
                        group("`g'") ///
                        term("count threshold interaction") ///
                        rel(.) threshold(`c') ///
                        status("reghdfe failed")
                }
            }
            else {
                * Post-discharge effect for the low-frequency group
                _post_direct_result, ///
                    posth(`posth') ///
                    analysis("count_threshold_interaction") ///
                    window("`window'") ///
                    outcome("`y'") ///
                    group("Count <= c") ///
                    term("1.`treatvar'") ///
                    rel(.) threshold(`c')

                * Total post-discharge effect for the high-frequency group
                _post_lincom_result, ///
                    posth(`posth') ///
                    analysis("count_threshold_interaction") ///
                    window("`window'") ///
                    outcome("`y'") ///
                    group("Count > c") ///
                    term("1.`treatvar' + interaction") ///
                    expression("1.`treatvar' + 1.`treatvar'#1.`high'") ///
                    rel(.) threshold(`c')

                * High- minus low-frequency interaction effect
                _post_direct_result, ///
                    posth(`posth') ///
                    analysis("count_threshold_interaction") ///
                    window("`window'") ///
                    outcome("`y'") ///
                    group("Count > c minus Count <= c") ///
                    term("1.`treatvar'#1.`high'") ///
                    rel(.) threshold(`c')
            }
        }
    }
end

****************************************************
* 6. Initialize results container
****************************************************

tempfile all_results
tempname RESULTS

postfile `RESULTS' ///
    str40 analysis ///
    str32 window ///
    str48 outcome ///
    str120 group ///
    double rel ///
    double threshold ///
    str160 term ///
    double coefficient ///
    double se ///
    double t_statistic ///
    double p_value ///
    double ci_lower_95 ///
    double ci_upper_95 ///
    double observations ///
    double vehicles ///
    double events ///
    double r2 ///
    double r2_adjusted ///
	double constant ///
	double constant_se ///
	double constant_p_value ///
	str80 constant_status ///
	str60 model_status ///
    using `all_results', replace

****************************************************
* 7. Main post-discharge regressions
****************************************************

*-----------------------------------
* (1) -10~-5 vs 1~10
*-----------------------------------

run_static_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_main_m5) ///
    treatvar(post_m5) ///
    analysis("main_static") ///
    window("all_post_1_10") ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

*-----------------------------------
* (2) -10~-5 vs 1
*-----------------------------------

run_static_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_firstpost_m5) ///
    treatvar(post1_only_m5) ///
    analysis("main_static") ///
    window("first_post_1") ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

*-----------------------------------
* (3) -10~-5 vs 2~10
*-----------------------------------

run_static_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_post2plus_m5) ///
    treatvar(post2plus_only_m5) ///
    analysis("main_static") ///
    window("later_post_2_10") ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

****************************************************
* 8. Main post-discharge regressions
****************************************************

run_eventstudy_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_firstpost_es_m5) ///
    window("first_post_1") ///
    rellist(-10 -9 -8 -7 -6 -5 1) ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

run_eventstudy_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_post2plus_es_m5) ///
    window("later_post_2_10") ///
    rellist(-10 -9 -8 -7 -6 -5 2 3 4 5 6 7 8 9 10) ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

****************************************************
* 9. Vehicle-type heterogeneity
****************************************************

run_group_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_hetero_first_m5) ///
    treatvar(post1_only_m5) ///
    groupvar(car_type_id) ///
    analysis("vehicle_heterogeneity") ///
    window("first_post_1") ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main") ///
    minvehicles($min_car_type_vehicles)

run_group_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_hetero_post2plus_m5) ///
    treatvar(post2plus_only_m5) ///
    groupvar(car_type_id) ///
    analysis("vehicle_heterogeneity") ///
    window("later_post_2_10") ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main") ///
    minvehicles($min_car_type_vehicles)

****************************************************
* 10. Holiday-status heterogeneity
****************************************************

* 10.1 Construct public-holiday indicator
run_group_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_firstpost_m5) ///
    treatvar(post1_only_m5) ///
    groupvar(holiday_group) ///
    analysis("holiday_group_regression") ///
    window("first_post_1") ///
    controlvars("$controls_noholiday") ///
    absorbvar("$absorb_main") ///
    minvehicles(1)

run_group_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_post2plus_m5) ///
    treatvar(post2plus_only_m5) ///
    groupvar(holiday_group) ///
    analysis("holiday_group_regression") ///
    window("later_post_2_10") ///
    controlvars("$controls_noholiday") ///
    absorbvar("$absorb_main") ///
    minvehicles(1)

run_holiday_interaction_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_firstpost_m5) ///
    treatvar(post1_only_m5) ///
    window("first_post_1") ///
    controlvars("$controls_noholiday") ///
    absorbvar("$absorb_main")

run_holiday_interaction_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_post2plus_m5) ///
    treatvar(post2plus_only_m5) ///
    window("later_post_2_10") ///
    controlvars("$controls_noholiday") ///
    absorbvar("$absorb_main")

****************************************************
* 11. Cumulative discharge-frequency heterogeneity
****************************************************

run_threshold_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_firstpost_m5) ///
    treatvar(post1_only_m5) ///
    window("first_post_1") ///
    countvar(vehicle_discharge_count_desc) ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

run_threshold_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_post2plus_m5) ///
    treatvar(post2plus_only_m5) ///
    window("later_post_2_10") ///
    countvar(vehicle_discharge_count_desc) ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

****************************************************
* 12. Anticipatory charging: events -10 to -5 vs -4 to -1
****************************************************

* Manuscript table
run_static_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_anticipation_pre_m5) ///
    treatvar(anticipation_pre_m5) ///
    analysis("anticipation_static") ///
    window("pre_minus4_to_minus1") ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

* 12.2 Anticipatory charging adjustments
* Reference event
run_eventstudy_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_anticipation_es_m5) ///
    window("pre_minus4_to_minus1") ///
    rellist(-10 -9 -8 -7 -6 -5 -4 -3 -2 -1) ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

* 12.3 Vehicle-type heterogeneity
run_group_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_hetero_anticipation_m5) ///
    treatvar(anticipation_pre_m5) ///
    groupvar(car_type_id) ///
    analysis("anticipation_vehicle") ///
    window("pre_minus4_to_minus1") ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main") ///
    minvehicles($min_car_type_vehicles)

run_group_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_anticipation_pre_m5) ///
    treatvar(anticipation_pre_m5) ///
    groupvar(holiday_group) ///
    analysis("anticipation_holiday_group") ///
    window("pre_minus4_to_minus1") ///
    controlvars("$controls_noholiday") ///
    absorbvar("$absorb_main") ///
    minvehicles(1)

run_holiday_interaction_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_anticipation_pre_m5) ///
    treatvar(anticipation_pre_m5) ///
    window("pre_minus4_to_minus1") ///
    controlvars("$controls_noholiday") ///
    absorbvar("$absorb_main")

* 12.6 Cumulative discharge-frequency threshold interactions
run_threshold_collect, ///
    posth(`RESULTS') ///
    samplevar(sample_anticipation_pre_m5) ///
    treatvar(anticipation_pre_m5) ///
    window("pre_minus4_to_minus1") ///
    countvar(vehicle_discharge_count_desc) ///
    controlvars("$controls_main") ///
    absorbvar("$absorb_main")

postclose `RESULTS'

****************************************************
* 13. Export DTA, CSV, and Excel results
****************************************************

preserve
    use `all_results', clear

    ****************************************************
    * Create display field for the constant p-value
    ****************************************************

    capture drop constant_p_display
    gen str12 constant_p_display = ""

    * Format very small p-values as <0.001
    replace constant_p_display = "<0.001" ///
        if !missing(constant_p_value) & ///
        constant_p_value < 0.001

    * Format remaining p-values to three decimal places
    replace constant_p_display = ///
        string(constant_p_value, "%6.3f") ///
        if !missing(constant_p_value) & ///
        constant_p_value >= 0.001

    * Remove leading spaces introduced by formatting
    replace constant_p_display = ///
        strtrim(constant_p_display)

    sort analysis window outcome group rel threshold
	order analysis window outcome group rel threshold term ///
		coefficient se t_statistic p_value ///
		ci_lower_95 ci_upper_95 ///
		observations vehicles events ///
		r2 r2_adjusted ///
		constant constant_se constant_p_value ///
		constant_p_display ///
		constant_status model_status

    label variable analysis "Analysis"
    label variable window "Analysis window"
    label variable outcome "Outcome"
    label variable group "Group/effect"
    label variable rel "Relative event"
    label variable threshold "Cumulative discharge-frequency threshold c"
    label variable term "Regression term"
    label variable coefficient "Coefficient"
    label variable se "Vehicle-clustered standard error"
    label variable t_statistic "t statistic"
    label variable p_value "p value"
    label variable ci_lower_95 "95% CI lower bound"
    label variable ci_upper_95 "95% CI upper bound"
    label variable observations "Observations"
    label variable vehicles "Number of vehicles"
    label variable events "Number of discharge events"
    label variable r2 "R-squared"
    label variable r2_adjusted "Adjusted R-squared"
	label variable constant "Constant"
	label variable constant_se "Constant SE"
	label variable constant_p_value "Constant p-value"
	label variable constant_p_display ///
    "Constant p-value (display)"
	label variable constant_status "Constant note"
	label variable model_status "Model status"

	save `all_results', replace

	save "$out/V2G_results_and_plotting_data.dta", replace

    export delimited using ///
        "$out/V2G_results_and_plotting_data.csv", replace

    local xlsx "$out/V2G_results_and_plotting_data.xlsx"

    * Full results table
    export excel using "`xlsx'", ///
        sheet("00_all_results") firstrow(variables) replace

    * Stata does not allow nested preserve commands
    * Reload the results tempfile before exporting each worksheet

    * Main post-discharge regressions
    use `all_results', clear
    keep if analysis == "main_static"
	keep analysis window outcome term ///
		coefficient se p_value ///
		constant constant_se constant_p_value ///
		constant_p_display ///
		r2 r2_adjusted ///
		observations vehicles events ///
		constant_status model_status
    sort window outcome
    export excel using "`xlsx'", ///
        sheet("01_main_static", replace) firstrow(variables)

    * Main post-discharge regressions
    use `all_results', clear
    keep if analysis == "event_study"
    keep analysis window outcome rel term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort window outcome rel
    export excel using "`xlsx'", ///
        sheet("02_event_study", replace) firstrow(variables)

    * Vehicle-type heterogeneity
    use `all_results', clear
    keep if analysis == "vehicle_heterogeneity"
    keep analysis window outcome group term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort window outcome group
    export excel using "`xlsx'", ///
        sheet("03_vehicle", replace) firstrow(variables)

    * Plotting data
    use `all_results', clear
    keep if analysis == "holiday_group_regression"
    keep analysis window outcome group term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort window outcome group
    export excel using "`xlsx'", ///
        sheet("04_holiday_group", replace) firstrow(variables)

    * Main post-discharge regressions
    use `all_results', clear
    keep if analysis == "holiday_interaction" & ///
        inlist(window, "first_post_1", "later_post_2_10")
    keep analysis window outcome group term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort window outcome group
    export excel using "`xlsx'", ///
        sheet("05_holiday_interact", replace) firstrow(variables)

    * Main post-discharge regressions
    use `all_results', clear
    keep if analysis == "count_threshold_interaction" & ///
        inlist(window, "first_post_1", "later_post_2_10")
    keep analysis window outcome group threshold term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort window outcome threshold group
    export excel using "`xlsx'", ///
        sheet("06_count_threshold", replace) firstrow(variables)

    * Anticipatory charging adjustments
    use `all_results', clear
    keep if analysis == "anticipation_static"
	keep analysis window outcome term ///
		coefficient se p_value ///
		constant constant_se constant_p_value ///
		constant_p_display ///
		r2 r2_adjusted ///
		observations vehicles events ///
		constant_status model_status
    sort outcome
    export excel using "`xlsx'", ///
        sheet("07_pre_static", replace) firstrow(variables)

    * Vehicle-type heterogeneity
    use `all_results', clear
    keep if analysis == "anticipation_vehicle"
    keep analysis window outcome group term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort outcome group
    export excel using "`xlsx'", ///
        sheet("08_pre_vehicle", replace) firstrow(variables)

    * Anticipatory charging adjustments
    use `all_results', clear
    keep if analysis == "anticipation_holiday_group"
    keep analysis window outcome group term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort outcome group
    export excel using "`xlsx'", ///
        sheet("09_pre_holiday_grp", replace) firstrow(variables)

    * Anticipatory charging adjustments
    use `all_results', clear
    keep if analysis == "holiday_interaction" & ///
        window == "pre_minus4_to_minus1"
    keep analysis window outcome group term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort outcome group
    export excel using "`xlsx'", ///
        sheet("10_pre_holiday_int", replace) firstrow(variables)

    * Anticipatory charging adjustments
    use `all_results', clear
    keep if analysis == "count_threshold_interaction" & ///
        window == "pre_minus4_to_minus1"
    keep analysis window outcome group threshold term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort outcome threshold group
    export excel using "`xlsx'", ///
        sheet("11_pre_threshold", replace) firstrow(variables)

    * Anticipatory charging adjustments
    use `all_results', clear
    keep if analysis == "event_study" & ///
        window == "pre_minus4_to_minus1"
    keep analysis window outcome rel term ///
        coefficient se p_value ci_lower_95 ci_upper_95 ///
        observations vehicles events model_status
    sort outcome rel
    export excel using "`xlsx'", ///
        sheet("12_pre_event_study", replace) firstrow(variables)

    * README worksheet
    clear
    set obs 15
    gen str32 sheet = ""
    gen str244 description = ""

    replace sheet = "00_all_results" in 1
    replace description = "Long-format dataset containing all regression and plotting results." in 1

    replace sheet = "01_main_static" in 2
    replace description = "Three main static specifications with coefficient, SE, p-value, constant, adjusted R-squared, observations, and number of vehicles." in 2

    replace sheet = "02_event_study" in 3
    replace description = "Event-study results for the first post-discharge charge, subsequent post-discharge charges, and anticipatory charging; event -5 is the omitted reference." in 3

    replace sheet = "03_vehicle" in 4
    replace description = "Vehicle-type subgroup regressions; commuter buses, sanitation special-purpose vehicles, tourist buses, engineering special-purpose vehicles, and highway coaches are excluded." in 4

    replace sheet = "04_holiday_group" in 5
    replace description = "Holiday and non-holiday subgroup regressions; weekend is the additional calendar control." in 5

    replace sheet = "05_holiday_interact" in 6
    replace description = "Formal Holiday × Post interaction for the main post-discharge windows, reporting non-holiday, holiday, and between-group effects." in 6

    replace sheet = "06_count_threshold" in 7
    replace description = "Cumulative discharge-frequency interactions for thresholds c=1,...,20 in the main post-discharge windows." in 7

    replace sheet = "07_pre_static" in 8
    replace description = "Anticipation regression comparing events -4 to -1 with the earlier pre-discharge period (-10 to -5)." in 8

    replace sheet = "08_pre_vehicle" in 9
    replace description = "Vehicle-type heterogeneity in anticipatory charging adjustments." in 9

    replace sheet = "09_pre_holiday_grp" in 10
    replace description = "Holiday-status subgroup regressions for anticipatory charging adjustments." in 10

    replace sheet = "10_pre_holiday_int" in 11
    replace description = "Formal Holiday × Anticipation interaction." in 11

    replace sheet = "11_pre_threshold" in 12
    replace description = "Cumulative discharge-frequency interactions for anticipatory charging, c=1,...,20." in 12

    replace sheet = "12_pre_event_study" in 13
    replace description = "Anticipatory event study for events -10 to -1 with event -5 as the omitted reference." in 13

    replace sheet = "Constant" in 14
    replace description = "Constant, SE, and p-value are stored from reghdfe output; constant_p_display formats very small p-values as <0.001. Constants in fixed-effect models depend on FE normalization and are not substantively interpreted." in 14

    replace sheet = "Plot fields" in 15
    replace description = "For plotting, use coefficient, ci_lower_95, and ci_upper_95 and filter by analysis, window, outcome, group, rel, or threshold." in 15

    export excel using "`xlsx'", ///
        sheet("README", replace) firstrow(variables)
restore

****************************************************
* 14. Completion message
****************************************************

di as txt "============================================================"
di as result "Main analysis completed."
di as txt "Analyses completed:"
di as txt "  1. Main post-discharge regressions: -10 to -5 vs 1-10, 1, and 2-10"
di as txt "  2. Post-discharge event studies with reference event -5"
di as txt "  3. Vehicle-type heterogeneity"
di as txt "  4. Holiday-status subgroup and interaction analyses"
di as txt "  5. Cumulative discharge-frequency interactions, c=1,...,20"
di as txt "  6. Anticipatory charging regression and heterogeneity analyses"
di as txt "  7. Anticipatory event study with reference event -5"
di as txt "Not run here: placebo tests, CSDID, fixed-effect sensitivity, non-overlapping windows, or automated plotting."
di as txt "Results workbook: $out/V2G_results_and_plotting_data.xlsx"
di as txt "Results CSV: $out/V2G_results_and_plotting_data.csv"
di as txt "============================================================"

log close
