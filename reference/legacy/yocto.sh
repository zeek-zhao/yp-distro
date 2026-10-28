#!/bin/bash

get_user_info() {
  HOST_UID=$(id -u)
  HOST_GID=$(id -g)
  HOST_USER=$(id -un)
  export HOST_UID HOST_GID HOST_USER
}

run_container() {
  local IMAGE_NAME="$1"
  local CONTAINER_NAME="$2"
  local WORKSPACE="$3"

  get_user_info

  echo "映射项目目录: $WORKSPACE 到容器 /workspace"
  echo "启动开发容器: $CONTAINER_NAME"
  docker run -d \
    --name "$CONTAINER_NAME" \
    -h "$CONTAINER_NAME" \
    -v "$WORKSPACE:/workspace" \
    --privileged \
    --restart always \
    -w /workspace \
    -e HOST_UID="$HOST_UID" \
    -e HOST_GID="$HOST_GID" \
    -e HOST_USER="$HOST_USER" \
    -v /dev/net/tun:/dev/net/tun \
    --user root \
    "$IMAGE_NAME" \
    bash -c "
            # 创建与宿主机匹配的用户组和用户
            groupadd -f -g \$HOST_GID \$HOST_USER 2>/dev/null || true
            useradd -u \$HOST_UID -g \$HOST_GID -s /bin/bash -m \$HOST_USER 2>/dev/null || true
            echo "\$HOST_USER:123" | sudo chpasswd
            usermod -aG sudo \$HOST_USER

            # 确保工作目录权限正确
            chown -R \$HOST_UID:\$HOST_GID /workspace 2>/dev/null || true

            # 切换到用户并保持容器运行
            exec su \$HOST_USER -c 'sleep infinity'
        "

}
build_yocto(){
  local CONTAINER_NAME="$1"
  local WORKSPACE="$2"
  get_user_info
  docker exec --user $HOST_USER  -it "$CONTAINER_NAME" bash -c "
    cd $WORKSPACE
    source oe-init-build-env build
    echo '设置下载目录...'
    echo 'DL_DIR ?= \"\${TOPDIR}/../../downloads\"' >> conf/local.conf
    echo '设置缓存目录...'
    echo 'SSTATE_DIR ?= \"\${TOPDIR}/../../sstate-cache\"' >> conf/local.conf
    bitbake core-image-minimal
    # https://docs.yoctoproject.org/dev-manual/qemu.html
    runqemu qemux86-64 nographic # 启动模拟器无界面 默认账号 root 无密码
    # Ctrl + A,然后 X 退出模拟器
  "
}

pull_code(){
  local work_dir="$1" && cd $work_dir
  if [ ! -d "poky" ]; then
    echo "Cloning poky repository..."
    # https://github.com/yoctoproject/poky
    git clone https://github.com/yoctoproject/poky.git
  fi
  # https://wiki.yoctoproject.org/wiki/Releases
  # Kirkstone 4.0 2026 -> git checkout kirkstone
  if [ ! -d "kirkstone" ]; then
    echo "Cloning Kirkstone branch of poky repository..."
    cp poky kirkstone -r
    cd kirkstone && git checkout kirkstone && cd -
  fi
  # Scarthgap	5.0 2028 -> git checkout scarthgap
  if [ ! -d "scarthgap" ]; then
    echo "Cloning scarthgap branch of poky repository..."
    cp poky scarthgap -r
    cd scarthgap && git checkout scarthgap && cd -
  fi
}
build_image(){
  local IMAGE_NAME="$1"
  local IMAGE_FILE="$2"
  local WORKSPACE="$3"
  docker build -t "$IMAGE_NAME" $WORKSPACE -f "$IMAGE_FILE"
}
#run_container docker.io/library/zeek_yocto:latest zeek_yocto_container "$PWD" 
#build_yocto zeek_yocto_container "/workspace/Kirkstone/poky"

help(){
  echo "Usage: $0 {pull|run|build_yocto|build_image} [WORKSPACE] [CONTAINER_NAME|IMAGE_NAME]"
  echo "  pull                拉取 Yocto 代码库"
  echo "  run                 运行 Yocto 开发容器"
  echo "  build_yocto        在容器中构建 Yocto 镜像"
  echo "  build_image        构建 Yocto 开发容器镜像"
  echo "  WORKSPACE          项目工作目录，默认为当前目录"
  echo "  CONTAINER_NAME     容器名称，默认为 zeek_yocto_container"
  echo "  IMAGE_NAME         镜像名称，默认为 docker.io/library/zeek_yocto:latest"
  echo ""
  echo "示例:"
  echo "  $0 pull $PWD"
  echo "  $0 build_image $PWD yocto_poky_container yocto_poky:latest"
  echo "  $0 run $PWD yocto_poky_container yocto_poky:latest"
  echo "  https://docs.yoctoproject.org/4.0.31/brief-yoctoprojectqs/index.html "
  echo "  $0 build_yocto /workspace/kirkstone yocto_poky_container"
  echo "  https://docs.yoctoproject.org/5.0.14/brief-yoctoprojectqs/index.html "
  echo "  $0 build_yocto /workspace/scarthgap yocto_poky_container"
}

main(){
  WORKSPACE=${2:-$PWD}
  CONTAINER_NAME=${3:-yocto_poky_container}
  IMAGE_NAME=${4:-yocto_poky:latest}
  case "$1" in
    help|-h|--help)
      help
      ;;
    pull)
      pull_code "$WORKSPACE"
      ;;
    build_yocto)
      build_yocto "$CONTAINER_NAME" "$WORKSPACE"
      ;;
    build_image)
      build_image "$IMAGE_NAME" "$WORKSPACE"/Dockerfile "$WORKSPACE"
      ;;
    run)
      run_container "$IMAGE_NAME" "$CONTAINER_NAME" "$WORKSPACE"
      ;;
    *)
      echo "Usage: $0 {pull|run|build_yocto|help}"
      exit 1
      ;;
  esac
}

main "$@"