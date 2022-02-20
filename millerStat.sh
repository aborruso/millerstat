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

fieldsArray=$(mlrgo --csv head -n 1 then cut -r -f "_fieldType" then put -q 'for (k in $*){print k}' "$folder"/processing/field_type.csv)

SAVEIFS=$IFS         # Save current IFS (Internal Field Separator)
IFS=$'\n'            # Change IFS to newline char
names=($fieldsArray) # split the `names` string into an array
IFS=$SAVEIFS         # Restore original IFS

if [ -f "$folder"/processing/field_type ]; then
  rm "$folder"/processing/field_type
fi

# extract most common field type by field
for ((i = 0; i < ${#names[@]}; i++)); do
  mlrgo --icsv --ojsonl most-frequent -f "${names[$i]}" then head -n 1 then cut -x -f count then put '$field="'"${names[$i]}"'"' then label fieldType "$folder"/processing/field_type.csv >>"$folder"/processing/field_type
done

mlrgo -I --jsonl put '$field=sub($field,"_fieldType","")' "$folder"/processing/field_type

### fields stats ###

if [ -f "$folder"/processing/field_stats ]; then
  rm "$folder"/processing/field_stats
fi

cat "$folder"/processing/field_type | while read line; do
  fieldType=$(echo $line | mlrgo --ijsonl --onidx cut -f fieldType)
  field=$(echo $line | mlrgo --ijsonl --onidx cut -f field)
  if ([ "$fieldType" == "int" ] || [ "$fieldType" == "float" ]); then
    mlrgo --icsv --ojsonl stats1 -f "$field" -a min,max,mode,mean then put '$field="'"$field"'"' then rename -r ''"${field}"'_,' "$folder"/input.csv >>"$folder"/processing/field_stats
  fi
done

### join field type and stats ###

mlrgo --ijsonl --ocsv join --ul -j field -f "$folder"/processing/field_type then unsparsify "$folder"/processing/field_stats >"$folder"/file_info.csv

### count distinct ###

if [ -f "$folder"/processing/field_unique ]; then
  rm "$folder"/processing/field_unique
fi

cat "$folder"/processing/field_type | while read line; do
  fieldType=$(echo $line | mlrgo --ijsonl --onidx cut -f fieldType)
  field=$(echo $line | mlrgo --ijsonl --onidx cut -f field)
  mlrgo --icsv --ojsonl uniq -n -f "${field}" then label "${field}_unique" then put '$field="'"$field"'"' then rename -r ''"${field}"'_,' input.csv >>"$folder"/processing/field_unique
done

mlrgo --ijsonl --ocsv cat "$folder"/processing/field_unique >"$folder"/processing/field_unique.csv

### join unique values ###

mlrgo --csv join --ul -j field -f "$folder"/file_info.csv then unsparsify "$folder"/processing/field_unique.csv >"$folder"/processing/tmp.csv

mv "$folder"/processing/tmp.csv "$folder"/file_info.csv

### count null ###

if [ -f "$folder"/processing/field_null ]; then
  rm "$folder"/processing/field_null
fi

mlrgo --csv put 'for (k,v in $*) { if (is_null($[k])) {$[k."_nullCheck"] = 1} else {$[k."_nullCheck"] = 0}}' then cut -r -f "_nullCheck" then rename -r '"_nullCheck",' "$folder"/input.csv >"$folder"/processing/field_null.csv

cat "$folder"/processing/field_type | while read line; do
  fieldType=$(echo $line | mlrgo --ijsonl --onidx cut -f fieldType)
  field=$(echo $line | mlrgo --ijsonl --onidx cut -f field)
  mlrgo --icsv --ojsonl stats1 -f "${field}" -a sum then put '$field="'"${field}"'"' then label null processing/field_null.csv >>"$folder"/processing/field_null
done

mlrgo --ijsonl --ocsv cat "$folder"/processing/field_null >"$folder"/processing/field_null.csv

### join null values ###

mlrgo --csv join --ul -j field -f "$folder"/file_info.csv then unsparsify "$folder"/processing/field_null.csv >"$folder"/processing/tmp.csv

mv "$folder"/processing/tmp.csv "$folder"/file_info.csv
