#!/bin/bash
#set -x

work_dir=$(pwd)
scan_dir=$work_dir/scan_dir && mkdir -p $scan_dir
scan_tar=$work_dir/scan_tar && mkdir -p $scan_tar
sacntool="$work_dir/scancode-toolkit-31.2.6/scancode"
report_dir=$work_dir/report_dir && mkdir -p $report_dir
# 获取 scan_tar 目录下的所有 tar.gz 文件并解压到 scan_dir 目录
for tar_file in $scan_tar/*.tar.gz; do
    file_name=$(basename "$tar_file" .tar.gz)
    if [ -d "$scan_dir/$file_name" ]; then
        echo "$scan_dir/$file_name already exists, skipping extraction."
        continue
    fi
    echo "Extracting $tar_file to $scan_dir"
    mkdir -p "$scan_dir/$file_name"
    tar -zxf "$tar_file" -C "$scan_dir/$file_name"
done


for dir in $scan_dir/*/; do
    echo "Processing directory: $dir"
    echo "cmd: $sacntool -v --processes 32 --license --license-clarity-score --license-score 70 --license-text --copyright --package --info --consolidate --classify --summary --tallies --url --email --csv $report_dir/$(basename "$dir").csv --json-pp $report_dir/$(basename "$dir").json $dir"
    $sacntool \
    -v \
    --processes 32 \
    --license \
    --license-clarity-score \
    --license-score 70 \
    --license-text \
    --copyright \
    --package \
    --info \
    --consolidate \
    --classify \
    --summary \
    --tallies \
    --url \
    --email \
    --csv $report_dir/$(basename "$dir").csv \
    --json-pp $report_dir/$(basename "$dir").json \
    "$dir"
done

tar -czvf scancode_toolkit_reports.tar.gz -C $report_dir .