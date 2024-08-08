global folder "~/Documents/econ_research/newspaper_msa/data"

global figures "/Users/natalieyang/Dropbox/Research, highways/figures"

/*******************************************************************************
read in the hwy part

Creates MSA-withdrawal-level dataset that shows fraction of highway length
withdrawn in each MSA
*******************************************************************************/
* withdrawn highways
import delim "$folder/hwys2msa.csv", clear
keep if withdraw
keep smsacode length_msa_km withdraw
rename smsacode msa
rename length_msa_km length
tempfile temp
save "`temp'"

* built highways from Brinkman and Lin
// import delim "$folder/PR511-shp/PR511_shp.csv", clear
// keep if msa != 0
// keep msa real_lengt open*
// drop if open90 == 0 //drop the segments in their file that seem like they were never built
// rename real_lengt length_msa_km
// gen withdrawal = 0

import delim "$folder/pr5112msa.csv", clear
drop if smsa == .
drop if open90 == 0 //drop the segments in their file that seem like they were never built
keep smsa length_in_km open*
rename smsa msa
rename length_in_km length
gen withdrawal = 0

append using "`temp'"

sort msa withdraw /* here*/

* flag which MSAs have at least one withdrawal
bys msa: egen has_withdraw = max(withdraw)

* calc percent of total planned highways ended up being withdrawn
collapse (sum) length, by(msa withdraw)

bys msa: egen total_length = total(length)

gen frac_length = length / total_length
replace frac_length = 1 if frac_length > .9999 //precision issue

* reconfigure data to be frac withdrawn per msa
gsort msa -withdrawal
egen tag = tag(msa)
keep if tag
replace frac_length = 0 if withdrawal == 0
drop withdrawal tag length
rename frac_length frac_length_withdrawn

tempfile msahwy
save "`msahwy'"

/*******************************************************************************
read in the place 2 msa part

Creates Census-place level dataset that identifies largest place in each MSA
*******************************************************************************/
* get population by place
import delim "$folder/nhgis0034_csv/nhgis0034_ds94_1970_place.csv", clear
keep gisjoin cbc001
rename cbc001 population
tempfile temp2
save "`temp2'"

import delim "$folder/places2msa1970.csv", clear
merge 1:1 gisjoin using "`temp2'", keep(3) nogen

* identify the largest place in each MSA by population
bys smsacode: egen max_place_pop = max(population)
gen max_place = population == max_place_pop

keep nhgisplace smsacode max_place population
rename smsacode msa

tempfile msaplace
save "`msaplace'"

/*******************************************************************************
read in newspapers data

Reads in Gentzkow city-level newspaper data and keeps just 1960
*******************************************************************************/
import delim "$folder/gentzkow-etal_newspaper/ICPSR_30261/DS0007/30261-0007-Data.tsv", clear

** for now keep just year = 1960
keep if year == 1960

tempfile newspaper
save "`newspaper'"

/*******************************************************************************
merge datasets
*******************************************************************************/
import delim "$folder/places2newspapercities.csv", clear
drop if nhgisplace == "G060432800" // manual fix for now

merge 1:1 nhgisplace using "`msaplace'", keep(3) nogen

merge 1:1 citypermid using "`newspaper'", keep(3) nogen

* collapse down for central city vs. suburb places
collapse (sum) circ circ_polaff* population, by(msa max_place)
gen circ_per_cap = circ / population
gen circ_per_cap_r = circ_polaff_r / population
gen circ_per_cap_d = circ_polaff_d / population
gen circ_per_cap_i = circ_polaff_i / population
gen circ_per_cap_none = circ_polaff_none / population

bys msa: egen count = count(msa)
keep if count == 2

gsort msa -max

foreach var of varlist circ_per_cap* {
	by msa: gen rel_`var' = `var'[_n]/`var'[_n+1]
}
by msa: egen totpop = total(population)
drop if max_place == 0
drop max_place circ pop circ_per_cap*


* merge in hwy withdrawal info
merge m:1 msa using "`msahwy'", keep(3) nogen

gen haswithdraw = frac > 0


/*******************************************************************************
do some eda
*******************************************************************************/


label def has 0 "No withdrawn hwys" 1 "Has withdrawn hwys"
label val has has
label var rel_circ_per_cap "Relative per capita circulation (city / suburb)"

gen lpop = log(totpop)

* regress fraction withdrawn in the MSA on relative per capita circulation
eststo reg1: reg frac rel_circ_per_cap, robust

* control for total msa pop
eststo reg2: reg frac rel_circ_per_cap lpop, robust

estout using "/Users/natalieyang/Desktop/temp.tex", style(tex) replace ///
	cells(b(fmt(3) star) se(par fm(2))) ///
	stats(r2 N, labels("R^2" "N")) ///
	starl(* 0.1 ** 0.05 *** 0.01) ///
	label varlabels(_cons Constant)


* make a boxplot to compare relative circulation
graph box rel, by(has)
graph export "$figures/rel_newspaper_msa.png", replace

