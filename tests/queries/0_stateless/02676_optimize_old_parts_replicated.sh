#!/usr/bin/env bash
# Tags: long

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

# Wait for number of parts in table $1 to become $2.
# Print the changed value. If no changes for $3 seconds, prints initial value.
wait_for_number_of_parts() {
    for _ in `seq $3`
    do
        sleep 1
        res=`$CLICKHOUSE_CLIENT -q "SELECT count(*) FROM system.parts WHERE database = currentDatabase() AND table='$1' AND active"`
        if [ "$res" -eq "$2" ]
        then
            echo "$res"
            return
        fi
    done
    echo "$res"
}

$CLICKHOUSE_CLIENT -nmq "
DROP TABLE IF EXISTS test_without_merge;
DROP TABLE IF EXISTS test_replicated;
DROP TABLE IF EXISTS test_replicated_limit;

SELECT 'Without merge';

CREATE TABLE test_without_merge (i Int64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{database}/test02676_without_merge', 'node') ORDER BY i SETTINGS merge_selecting_sleep_ms=1000;
INSERT INTO test_without_merge SELECT 1;
INSERT INTO test_without_merge SELECT 2;
INSERT INTO test_without_merge SELECT 3;"

wait_for_number_of_parts 'test_without_merge' 1 10

$CLICKHOUSE_CLIENT -nmq "
DROP TABLE test_without_merge;

SELECT 'With merge replicated any part range';

CREATE TABLE test_replicated (i Int64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{database}/test02676', 'node')  ORDER BY i
SETTINGS min_age_to_force_merge_seconds=1, merge_selecting_sleep_ms=1000, min_age_to_force_merge_on_partition_only=false;
INSERT INTO test_replicated SELECT 1;
INSERT INTO test_replicated SELECT 2;
INSERT INTO test_replicated SELECT 3;"

wait_for_number_of_parts 'test_replicated' 1 100

$CLICKHOUSE_CLIENT -nmq "
DROP TABLE test_replicated;

SELECT 'With merge replicated partition only';

CREATE TABLE test_replicated (i Int64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{database}/test02676_partition_only', 'node')  ORDER BY i
PARTITION BY i
SETTINGS min_age_to_force_merge_seconds=1, merge_selecting_sleep_ms=1000, min_age_to_force_merge_on_partition_only=true;
INSERT INTO test_replicated SELECT 1;
INSERT INTO test_replicated SELECT 2;
SELECT sleep(3) FORMAT Null; -- Sleep so the first partition is older
INSERT INTO test_replicated SELECT 2 SETTINGS insert_deduplicate = 0;"

wait_for_number_of_parts 'test_replicated' 2 100

$CLICKHOUSE_CLIENT -nmq "
SELECT sleepEachRow(1) FROM numbers(9) SETTINGS function_sleep_max_microseconds_per_block = 10000000 FORMAT Null; -- Sleep for 9 seconds and verify that we keep the old part because it's the only one
SELECT (now() - modification_time) > 5 FROM system.parts WHERE database = currentDatabase() AND table='test_replicated' AND active;

DROP TABLE test_replicated;"

# Partition 2 will ignore max_bytes_to_merge_at_max_space_in_pool
$CLICKHOUSE_CLIENT -mq "
SELECT 'With merge replicated partition only and disable limit';

CREATE TABLE test_replicated_limit (i Int64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{database}/test02676_partition_only_limit', 'node')  ORDER BY i
PARTITION BY i
SETTINGS min_age_to_force_merge_seconds=1, merge_selecting_sleep_ms=1000, min_age_to_force_merge_on_partition_only=true, enable_max_bytes_limit_for_min_age_to_force_merge=false, max_bytes_to_merge_at_max_space_in_pool=1;
INSERT INTO test_replicated_limit SELECT 1;
INSERT INTO test_replicated_limit SELECT 2;
SELECT sleep(3) FORMAT Null; -- Sleep so the first partition is older
INSERT INTO test_replicated_limit SELECT 2 SETTINGS insert_deduplicate = 0;"

wait_for_number_of_parts 'test_replicated_limit' 2 100

# Partition 2 will limit by max_bytes_to_merge_at_max_space_in_pool
$CLICKHOUSE_CLIENT -mq "
DROP TABLE test_replicated_limit SYNC;

SELECT 'With merge replicated partition only and enable limit';

CREATE TABLE test_replicated_limit (i Int64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{database}/test02676_partition_only_limit', 'node')  ORDER BY i
PARTITION BY i
SETTINGS min_age_to_force_merge_seconds=1, merge_selecting_sleep_ms=1000, min_age_to_force_merge_on_partition_only=true, enable_max_bytes_limit_for_min_age_to_force_merge=true, max_bytes_to_merge_at_max_space_in_pool=1;
INSERT INTO test_replicated_limit SELECT 1;
INSERT INTO test_replicated_limit SELECT 2;
SELECT sleep(3) FORMAT Null; -- Sleep so the first partition is older
INSERT INTO test_replicated_limit SELECT 2 SETTINGS insert_deduplicate = 0;"

wait_for_number_of_parts 'test_replicated_limit' 3 100

$CLICKHOUSE_CLIENT -mq "
DROP TABLE test_replicated_limit;"