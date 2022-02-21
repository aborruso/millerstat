# Miller stat

A [bash script](millerStat.sh) that uses [Miller](https://miller.readthedocs.io/en/latest/) to extract from a CSV, for each field:

- field type;
- min, max, mode, mean
- unique values count
- null values count

Starting from this

| id | city | value |
| --- | --- | --- |
| 1 | Palermo | 5 |
| 2 | Palermo | 55 |
| 3 | Milano | 6 |
| 4 |  | 2 |
| 5 | Torino | 2 |

you will have

| field | fieldType | min | max | mode | mean | unique | null |
| --- | --- | --- | --- | --- | --- | --- | --- |
| id | int | 1 | 5 | 1 | 3 | 5 | 0 |
| city | string |  |  |  |  | 4 | 1 |
| value | int | 2 | 55 | 2 | 14 | 4 | 0 |

It's a bad script for now, to start thinking about it.
# to do

- [x] add count-distinct by field
- [x] add null value count
- [x] sort fields as they are in input
- [x] remove jq
- [x] to calculate field type on a subset extracting random 1000 record
- [ ] to parallel all
