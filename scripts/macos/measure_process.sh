#!/bin/sh
set -eu

if [ "$#" -lt 3 ]; then
	echo "usage: $0 <pid> <sample-count> <output-directory>" >&2
	exit 64
fi

SIDEY_MEASURE_PID=$1
SIDEY_MEASURE_COUNT=$2
SIDEY_MEASURE_OUTPUT=$3

case "$SIDEY_MEASURE_PID:$SIDEY_MEASURE_COUNT" in
	*[!0-9:]*|:*|*:|0:*|*:0)
		echo "pid and sample-count must be positive integers" >&2
		exit 64
		;;
esac

mkdir -p "$SIDEY_MEASURE_OUTPUT"
SIDEY_MEASURE_CSV="$SIDEY_MEASURE_OUTPUT/samples.csv"
SIDEY_MEASURE_CPU_SORTED="$SIDEY_MEASURE_OUTPUT/cpu.sorted"
SIDEY_MEASURE_RSS_SORTED="$SIDEY_MEASURE_OUTPUT/rss.sorted"
SIDEY_MEASURE_SUMMARY="$SIDEY_MEASURE_OUTPUT/summary.txt"

printf 'sample,epoch,cpu_percent,rss_kb\n' > "$SIDEY_MEASURE_CSV"
SIDEY_MEASURE_INDEX=1
while [ "$SIDEY_MEASURE_INDEX" -le "$SIDEY_MEASURE_COUNT" ]; do
	if ! kill -0 "$SIDEY_MEASURE_PID" 2>/dev/null; then
		echo "process exited before sample $SIDEY_MEASURE_INDEX" >&2
		exit 1
	fi
	SIDEY_MEASURE_VALUES=$(ps -p "$SIDEY_MEASURE_PID" -o %cpu=,rss= | awk 'NF == 2 { print $1 "," $2 }')
	if [ -z "$SIDEY_MEASURE_VALUES" ]; then
		echo "could not sample pid $SIDEY_MEASURE_PID" >&2
		exit 1
	fi
	printf '%s,%s,%s\n' \
		"$SIDEY_MEASURE_INDEX" \
		"$(date +%s)" \
		"$SIDEY_MEASURE_VALUES" >> "$SIDEY_MEASURE_CSV"
	SIDEY_MEASURE_INDEX=$((SIDEY_MEASURE_INDEX + 1))
	if [ "$SIDEY_MEASURE_INDEX" -le "$SIDEY_MEASURE_COUNT" ]; then
		sleep 1
	fi
done

awk -F, 'NR > 1 { print $3 }' "$SIDEY_MEASURE_CSV" | sort -n > "$SIDEY_MEASURE_CPU_SORTED"
awk -F, 'NR > 1 { print $4 }' "$SIDEY_MEASURE_CSV" | sort -n > "$SIDEY_MEASURE_RSS_SORTED"

SIDEY_MEASURE_CPU_STATS=$(awk '
	{ values[NR] = $1; sum += $1 }
	END {
		if (NR % 2) median = values[(NR + 1) / 2]
		else median = (values[NR / 2] + values[NR / 2 + 1]) / 2
		p95_index = int((NR * 95 + 99) / 100)
		printf "%.3f %.3f %.3f", median, values[p95_index], sum / NR
	}
' "$SIDEY_MEASURE_CPU_SORTED")
SIDEY_MEASURE_RSS_STATS=$(awk '
	{ values[NR] = $1; sum += $1 }
	END {
		if (NR % 2) median = values[(NR + 1) / 2]
		else median = (values[NR / 2] + values[NR / 2 + 1]) / 2
		p95_index = int((NR * 95 + 99) / 100)
		printf "%.0f %.0f %.0f", median, values[p95_index], sum / NR
	}
' "$SIDEY_MEASURE_RSS_SORTED")

set -- $SIDEY_MEASURE_CPU_STATS
SIDEY_MEASURE_CPU_MEDIAN=$1
SIDEY_MEASURE_CPU_P95=$2
SIDEY_MEASURE_CPU_MEAN=$3
set -- $SIDEY_MEASURE_RSS_STATS
SIDEY_MEASURE_RSS_MEDIAN_KB=$1
SIDEY_MEASURE_RSS_P95_KB=$2
SIDEY_MEASURE_RSS_MEAN_KB=$3

{
	printf 'pid=%s\n' "$SIDEY_MEASURE_PID"
	printf 'samples=%s\n' "$SIDEY_MEASURE_COUNT"
	printf 'cpu_median_percent=%s\n' "$SIDEY_MEASURE_CPU_MEDIAN"
	printf 'cpu_p95_percent=%s\n' "$SIDEY_MEASURE_CPU_P95"
	printf 'cpu_mean_percent=%s\n' "$SIDEY_MEASURE_CPU_MEAN"
	printf 'rss_median_kb=%s\n' "$SIDEY_MEASURE_RSS_MEDIAN_KB"
	printf 'rss_p95_kb=%s\n' "$SIDEY_MEASURE_RSS_P95_KB"
	printf 'rss_mean_kb=%s\n' "$SIDEY_MEASURE_RSS_MEAN_KB"
} | tee "$SIDEY_MEASURE_SUMMARY"
