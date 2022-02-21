#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$folder"/processing

### field type ###

# extract fields type by record
mlrgo --csv put 'for (k,v in $*) { $[k."_fieldType"] = typeof(v) }' "$folder"/input.csv >"$folder"/processing/field_type.csv

if [ -f "$folder"/processing/field_type ]; then
  rm "$folder"/processing/field_type
fi

# Extract 1000 random lines, to be used as a basis for assigning the field type.
# It is useful for very large input files
mlrgo -I --csv sample -k 1000 "$folder"/processing/field_type.csv

# Extract field names of the field types fields
mlrgo --csv head -n 1 then cut -r -f "_fieldType" then put -q 'for (k in $*){print k}' "$folder"/processing/field_type.csv >"$folder"/processing/field_name

# extract most common field type by field

cat "$folder"/processing/field_name | while read field; do
  mlrgo --icsv --ojsonl most-frequent -f "${field}" then head -n 1 then \
   cut -x -f count then \
   put '$field="'"${field}"'"' then \
   label fieldType "$folder"/processing/field_type.csv >>"$folder"/processing/field_type
done

# clean the field names, remove the "_fieldType" suffix
mlrgo -I --jsonl put '$field=sub($field,"_fieldType","")' "$folder"/processing/field_type

### fields stats ###

if [ -f "$folder"/processing/field_stats ]; then
  rm "$folder"/processing/field_stats
fi

# extract fields stats by record
cat "$folder"/processing/field_type | while read line; do
  fieldType=$(echo $line | mlrgo --ijsonl --onidx cut -f fieldType)
  field=$(echo $line | mlrgo --ijsonl --onidx cut -f field)
  if ([ "$fieldType" == "int" ] || [ "$fieldType" == "float" ]); then
    mlrgo --icsv --ojsonl stats1 -f "$field" -a min,max,mode,mean then \
    put '$field="'"$field"'"' then \
    rename -r ''"${field}"'_,' "$folder"/input.csv >>"$folder"/processing/field_stats
  fi
done

# if all fields are not numeric, create an empty file with all stats null
if [ ! -f "$folder"/processing/field_stats ]; then
  cat "$folder"/processing/field_name | while read field; do
    echo "a=0" | mlrgo --ojsonl put '$min="";$max="";$mode="";$mean="";$field="'"$field"'"' then cut -x -f a >>"$folder"/processing/field_stats
  done
  mlrgo -I --jsonl put '$field=sub($field,"_fieldType","")' "$folder"/processing/field_stats
fi

### join field type and stats ###

mlrgo --ijsonl --ocsv join --ul -j field -f "$folder"/processing/field_type then unsparsify "$folder"/processing/field_stats >"$folder"/file_info.csv

### count distinct ###

if [ -f "$folder"/processing/field_unique ]; then
  rm "$folder"/processing/field_unique
fi

# extract fields unique values count by record
cat "$folder"/processing/field_type | while read line; do
  fieldType=$(echo $line | mlrgo --ijsonl --onidx cut -f fieldType)
  field=$(echo $line | mlrgo --ijsonl --onidx cut -f field)
  mlrgo --icsv --ojsonl uniq -n -f "${field}" then \
  label "${field}_unique" then \
  put '$field="'"$field"'"' then \
  rename -r ''"${field}"'_,' input.csv >>"$folder"/processing/field_unique
done

mlrgo --ijsonl --ocsv cat "$folder"/processing/field_unique >"$folder"/processing/field_unique.csv

### join unique values ###

mlrgo --csv join --ul -j field -f "$folder"/file_info.csv then \
unsparsify "$folder"/processing/field_unique.csv >"$folder"/processing/tmp.csv

mv "$folder"/processing/tmp.csv "$folder"/file_info.csv

### count null ###

if [ -f "$folder"/processing/field_null ]; then
  rm "$folder"/processing/field_null
fi

# Create new field for each input field, and insert 0 for each record, if the field is null
# else insert 1
mlrgo --csv put 'for (k,v in $*) { if (is_null($[k])) {$[k."_nullCheck"] = 1} else {$[k."_nullCheck"] = 0}}' then \
cut -r -f "_nullCheck" then \
rename -r '"_nullCheck",' "$folder"/input.csv >"$folder"/processing/field_null.csv

# extract fields null values count by record
cat "$folder"/processing/field_type | while read line; do
  fieldType=$(echo $line | mlrgo --ijsonl --onidx cut -f fieldType)
  field=$(echo $line | mlrgo --ijsonl --onidx cut -f field)
  mlrgo --icsv --ojsonl stats1 -f "${field}" -a sum then \
  put '$field="'"${field}"'"' then \
  label null processing/field_null.csv >>"$folder"/processing/field_null
done

mlrgo --ijsonl --ocsv cat "$folder"/processing/field_null >"$folder"/processing/field_null.csv

### join null values ###

mlrgo --csv join --ul -j field -f "$folder"/file_info.csv then \
unsparsify "$folder"/processing/field_null.csv >"$folder"/processing/tmp.csv

mv "$folder"/processing/tmp.csv "$folder"/file_info.csv
