#!/bin/bash
work_dir=$(pwd) && export resources_dir
resources_dir=$work_dir/resources && mkdir -p $resources_dir && export resources_dir

# hello bbappend + scancode
sample1(){
  rm -rf $work_dir/kirkstone/meta-zeek  $work_dir/kirkstone/meta-spdxscanner
  cd $resources_dir
  if [ ! -d "$resources_dir/meta-spdxscanner" ]; then
    git clone -b kirkstone https://git.yoctoproject.org/meta-spdxscanner
  fi
  if [ ! -d "$resources_dir/scancode-toolkit-31.2.6" ]; then
    wget https://github.com/aboutcode-org/scancode-toolkit/archive/refs/tags/v31.2.6.tar.gz
    tar -xvf v31.2.6.tar.gz -C .
    cd ./scancode-toolkit-31.2.6/
    ./scancode -h
  fi
  if [ ! -d "$work_dir/kirkstone/meta-zeek" ]; then
    cp -rf $work_dir/meta-zeek $work_dir/kirkstone/meta-zeek
  fi
  if [ ! -d "$work_dir/kirkstone/meta-spdxscanner" ]; then
    cp -rf $resources_dir/meta-spdxscanner $work_dir/kirkstone/meta-spdxscanner
    rm $work_dir/kirkstone/meta-spdxscanner/recipes-devtools/python/python3-charset-normalizer_%.bbappend
    rm $work_dir/kirkstone/meta-spdxscanner/recipes-devtools/python/python3-fasteners_%.bbappend
  fi
  cd $work_dir/kirkstone
  rm -rf build/conf
  source ./oe-init-build-env build
  echo 'DL_DIR ?= "${TOPDIR}/../../downloads"' >> conf/local.conf
  echo 'SSTATE_DIR ?= "${TOPDIR}/../../sstate-cache"' >> conf/local.conf
  echo 'INHERIT += "buildhistory"' >> conf/local.conf
  echo 'BUILDHISTORY_COMMIT = "1"' >> conf/local.conf
  # 根据 bitbake-layers show-layers 的 priority，在 build/conf/bblayers.conf 中高到底
  bitbake-layers add-layer ../meta-zeek
  bitbake-layers add-layer ../meta-spdxscanner
  echo 'SCANCODE_HOST_DIR = "/workspace/resources/scancode-toolkit-31.2.6"' >> conf/local.conf
  echo 'INHERIT += "create-spdx"' >> conf/local.conf
  echo 'SPDX_PRETTY = "1"' >> conf/local.conf
  echo 'SPDX_INCLUDE_SOURCES = "1"' >> conf/local.conf
  echo 'SPDX_ARCHIVE_SOURCES = "1"' >> conf/local.conf
  echo 'SPDX_ARCHIVE_PACKAGED = "1"' >> conf/local.conf
  echo 'PREFERRED_PROVIDER_virtual/cpp-hello = "cpp-hello"' >> conf/local.conf
  bitbake core-image-minimal
  # bitbake cpp-hello scancode-toolkit-native -c cleanall && bitbake cpp-hello 
  ls $work_dir/kirkstone/build/tmp/work/core2-64-poky-linux/cpp-hello-scancode/0.1-r0/scancode*
  ls $work_dir/kirkstone/build/tmp/deploy/spdx/
  # 验证spdx文件合法性
  # pip install spdx-tools
  # export PATH="$HOME/.local/bin:$PATH"
  # pyspdxtools -i $work_dir/kirkstone/build/tmp/deploy/spdx/qemux86-64/packages/cpp-hello.spdx.json

  #bitbake cpp-hello -c cleanall  && reset && bitbake cpp-hello -DDD > debug_log.txt 2>&1
}

common_cmd(){
  bitbake -s # 显示所有可用的配方
  bitbake cpp-hello # 构建配方
  bitbake cpp-hello -c listtasks # 列出配方的所有任务
  bitbake cpp-hello -e # 显示配方的环境变量
  bitbake cpp-hello -c cleansstate # 清除配方的状态
  bitbake cpp-hello -g -DDD # 生成依赖关系图和调试日志
  # 根据 bitbake-layers show-layers 的 priority，在 build/conf/bblayers.conf 中是高到底
  bitbake-layers show-layers # 显示所有已添加的图层
  bitbake-layers show-recipes | grep cpp-hello # 显示包含特定配方的图层
  bitbake-layers add-layer ../meta-zeek # 添加图层
  bitbake-layers remove-layer ../meta-zeek # 移除图层
  bitbake-layers create-layer ../meta-newlayer # 创建新图层
}

scancode_cmd(){
  scancode_dir=$resources_dir/scancode-toolkit-31.2.6
  work_dir=$resources_dir/work_dir && mkdir -p $work_dir
  scancode_file=$1
  scancode_name=$(basename "$scancode_file" .tar.gz)
  tar -xvf  $scancode_file -C $work_dir/$scancode_name
  $scancode_dir/scancode \
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
    --csv $scancode_name.csv \
    --json-pp $scancode_name.json \
    --spdx-tv $scancode_name.spdx \
    $work_dir/$scancode_name
}

sample1

