WITH 

pat AS (
SELECT * FROM `oxygenators-209612.eicu.patient`),

diag AS (
SELECT * FROM `oxygenators-209612.eicu.diagnosis`),

chart AS (
SELECT * FROM `oxygenators-209612.eicu.nursecharting`),


--TODO: Validate what O2 L/% is.

ventilation AS (
SELECT
  MAX(SAFE_CAST(chart.nursingchartvalue as FLOAT64)) AS max_fiO2,
  chart.patientunitstayid AS icustay_id
FROM chart
WHERE chart.nursingchartcelltypevalname = "O2 L/%"
GROUP BY chart.patientunitstayid),

-- `device` is modified from
-- https://github.com/MIT-LCP/eicu-code/blob/master/concepts/pivoted/pivoted-o2.sql
device as
(
select
    patientunitstayid AS icustay_id
  , MAX(case
    -- For now, I do MAX, but we should keep track of the ventilation more along the lines of
    -- https://github.com/MIT-LCP/mimic-code/blob/master/concepts/durations/ventilation-durations.sql
        WHEN nursingchartcelltypevallabel = 'O2 Admin Device'
        -- AND in the next line *should* yield the same result, but out of caution we use OR.
        OR  nursingchartcelltypevalname = 'O2 Admin Device'
          then nursingchartvalue
      else null end)
    AS o2_device
  from chart
  -- speed up by only looking at a subset of charted data
  where nursingchartcelltypecat = 'Vital Signs'
  group by patientunitstayid
),

icd_code AS (
SELECT
diag.patientunitstayid,
SAFE_CAST(SUBSTR(diag.icd9code, 0, 3) as INT64) AS icd9code
FROM diag),


icd_presence AS (
SELECT
icd_code.patientunitstayid,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 001 AND 139 THEN 1 END) > 0 AS has_infectous_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 140 AND 239 THEN 1 END) > 0 AS has_neoplasm_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 240 AND 279 THEN 1 END) > 0 AS has_endocrine_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 280 AND 289 THEN 1 END) > 0 AS has_blood_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 290 AND 319 THEN 1 END) > 0 AS has_mental_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 320 AND 389 THEN 1 END) > 0 AS has_nervous_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 390 AND 459 THEN 1 END) > 0 AS has_circulatory_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 460 AND 519 THEN 1 END) > 0 AS has_respiratory_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 520 AND 579 THEN 1 END) > 0 AS has_digestive_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 580 AND 629 THEN 1 END) > 0 AS has_urinary_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 630 AND 679 THEN 1 END) > 0 AS has_pregnancy_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 680 AND 709 THEN 1 END) > 0 AS has_skin_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 710 AND 739 THEN 1 END) > 0 AS has_muscle_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 740 AND 759 THEN 1 END) > 0 AS has_congenital_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 760 AND 779 THEN 1 END) > 0 AS has_perinatal_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 780 AND 799 THEN 1 END) > 0 AS has_other_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 800 AND 999 THEN 1 END) > 0 AS has_injury_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 410 AND 414 THEN 1 END) > 0 AS has_isachaemic_heart_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 427 AND 427 THEN 1 END) > 0 AS has_atrial_fibrillation_disease,
COUNT(CASE WHEN icd_code.icd9code BETWEEN 434 AND 434 THEN 1 END) > 0 AS has_stroke_disease
FROM icd_code
GROUP BY icd_code.patientunitstayid)



SELECT 
  pat.gender,
  ventilation.max_fiO2,
  pat.unittype,
  pat.patientHealthSystemStayID as hospital_stay_id,
  pat.unitVisitNumber as unit_stay_number, -- counter for ICU visits on same hospital stay
  pat.hospitalDischargeYear, -- hospitalAdmitYear is missing in patient table
  pat.uniquepid AS patient_ID,
  pat.patientunitstayid AS icustay_id,
  SAFE_CAST(REGEXP_EXTRACT(pat.age, r"[0-9]+") as FLOAT64) AS age,
--  pat.hospitaladmitoffset AS hospitaladmitoffset,
  pat.unitdischargeoffset / (24 * 60) AS icu_length_of_stay,
  pat.hospitalid AS hospital_id,
  CASE WHEN pat.unitdischargestatus = "Alive" THEN 0 ELSE 1 END AS mortality_in_ICU,
  CASE WHEN pat.hospitaldischargestatus = "Alive" THEN 0 ELSE 1 END AS mortality_in_Hospt,
  icd_presence.*, -- By using `*`, we select patientunitstayid twice
  device.o2_device
FROM pat
LEFT JOIN icd_presence
  ON pat.patientunitstayid = icd_presence.patientunitstayid
LEFT JOIN ventilation
  ON pat.patientunitstayid = ventilation.icustay_id
LEFT JOIN device
  ON pat.patientunitstayid = device.icustay_id