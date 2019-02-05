SELECT DISTINCT 
chart.subject_id as patient_ID,
chart.valuenum as spO2_Value, 
chart.valueuom as sp02_Unit,
chart.charttime as measurement_time
FROM `oxygenators-209612.mimiciii_clinical.chartevents` AS chart
WHERE chart.itemid in (220277, 646) 
AND chart.valuenum IS NOT NULL
