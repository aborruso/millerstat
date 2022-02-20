#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$folder"/processing

#mlr --icsv --opprint put -q '
#  is_null(@valuemax) || $value > @valuemax {@valuemax = $value; @recmax = $*};
#  end {emit @recmax}
#' input.csv

### fields list ###

fields=$(mlrgo --icsv --ojsonl head -n 1 "$folder"/input.csv | jq -c '.|keys' | sed -r 's/(\[|\])//g')

### field type ###

# extract fields type by record
mlrgo --csv put 'for (k,v in $*) { $[k."_fieldType"] = typeof(v) }' "$folder"/input.csv >"$folder"/processing/field_type.csv

fields=$(mlrgo --icsv --ojsonl head -n 1 then cut -r -f "_fieldType" "$folder"/processing/field_type.csv | jq -c '.|keys' | sed -r 's/(\[|\])//g')
fieldsArray=$(mlrgo --icsv --ojsonl head -n 1 then cut -r -f "_fieldType" "$folder"/processing/field_type.csv | jq -r '.|keys[]')

SAVEIFS=$IFS         # Save current IFS (Internal Field Separator)
IFS=$'\n'            # Change IFS to newline char
names=($fieldsArray) # split the `names` string into an array
IFS=$SAVEIFS         # Restore original IFS

if [ -f "$folder"/processing/field_type ]; then
  rm "$folder"/processing/field_type
fi

# extract most common field type by field
for ((i = 0; i < ${#names[@]}; i++)); do
  mlrgo --icsv --ojsonl most-frequent -f "${names[$i]}" then head -n 1 then cut -x -f count then put '$field="'"${names[$i]}"'"' then label fiedlType "$folder"/processing/field_type.csv >>"$folder"/processing/field_type
done

mlrgo -I --jsonl put '$field=sub($field,"_fieldType","")' "$folder"/processing/field_type

### fields stats ###

if [ -f "$folder"/processing/field_stats ]; then
  rm "$folder"/processing/field_stats
fi

cat "$folder"/processing/field_type | while read line; do
  fiedlType=$(echo $line | jq -r '.fiedlType')
  field=$(echo $line | jq -r '.field')
  if ( [ "$fiedlType" == "int" ] || [ "$fiedlType" == "float" ] ); then
    mlrgo --icsv --ojsonl stats1 -f "$field" -a min,max,mode,mean then put '$field="'"$field"'"' then rename -r ''"${field}"'_,' "$folder"/input.csv >>"$folder"/processing/field_stats
  fi
done

### join field type and stats ###

mlrgo --ijsonl --ocsv join --ul -j field -f "$folder"/processing/field_type then unsparsify "$folder"/processing/field_stats
