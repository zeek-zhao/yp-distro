# 添加一个开机自启服务：从 make 配方到 systemd

本文面向 Yocto 6.0（wrynose），使用本仓库的 `custom` distro 和 `full`
镜像。完整示例名为 `yp-tutorial-svc`，每 10 秒向 journal 输出一条消息。
下面创建文件、修改镜像的命令是读者实施步骤，不代表仓库已经包含这个服务。
本教程提交本身只新增文档，不修改配方或镜像。

已核对的仓库依据：`layers/meta-yp/classes/yp-service.bbclass`、
`layers/meta-yp/recipes-core/yp-hello-svc/`、
`layers/meta-yp/recipes-core/images/yp-image.bb`、
`layers/meta-yp/conf/distro/yp.conf`。构建环境准备见 [build-env.md](../03-build/build-env.md)。

## 1. 目录与命名

通用布局是 `layers/meta-yp/recipes-demo/<name>/{<name>_0.1.bb, files/*}`：
配方名决定默认 `${PN}`，版本来自文件名中的 `0.1`。本例展开为：

```text
layers/meta-yp/recipes-demo/yp-tutorial-svc/
├── yp-tutorial-svc_0.1.bb
└── files/
    ├── demo.c
    ├── Makefile
    └── yp-tutorial-svc.service
```

这是**待创建**的布局。现有服务参考放在
`layers/meta-yp/recipes-core/yp-hello-svc/`，不是 `recipes-demo/`。
`layers/meta-yp/conf/layer.conf` 的 `BBFILES` 已覆盖 `recipes-*/*/*.bb`，
不需要额外登记本例目录。

在 `/work` 的仓库终端执行：

```bash
cd /work
mkdir -p layers/meta-yp/recipes-demo/yp-tutorial-svc/files
```

把源码、`Makefile`、unit 放在 `files/`，并逐项加入配方的 `SRC_URI`。
`file://demo.c` 等地址由 BitBake 从配方的文件搜索路径取源，不是目标机路径。
6.0 的 `file://` 内容解到 `${UNPACKDIR}`，因此编译目录必须设置
`S = "${UNPACKDIR}"`，不能沿用 `${WORKDIR}`。

## 2. 源码与构建

make 写法参考自远端分支，以下命令只读，不切换工作树：

```bash
git show origin/feat/64-demo-make:layers/meta-yp/recipes-demo/yp-demo-make/yp-demo-make_0.1.bb
git show origin/feat/64-demo-make:layers/meta-yp/recipes-demo/yp-demo-make/files/Makefile
```

该分支的程序输出后退出；本教程改为常驻前台程序，避免用一次性程序验证
`Type=simple` 的持续 `active` 状态。继续在 `/work` 执行：

```bash
cat > layers/meta-yp/recipes-demo/yp-tutorial-svc/files/demo.c <<'EOF'
#include <stdio.h>
#include <unistd.h>

int main(void)
{
    for (;;) {
        if (puts("yp-tutorial-svc alive") == EOF || fflush(stdout) == EOF) {
            perror("journal output");
            return 1;
        }
        sleep(10);
    }
}
EOF

cat > layers/meta-yp/recipes-demo/yp-tutorial-svc/files/Makefile <<'EOF'
TARGET = yp-tutorial-svc
SRC = demo.c

$(TARGET): $(SRC)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(SRC) -o $(TARGET) $(LDFLAGS)
EOF
```

Makefile 的命令行以 **Tab** 开头；复制时不要转为空格。
`fflush(stdout)` 保证输出重定向到 journal 时不因缓冲而迟迟看不到消息。
配方的编译任务如下，第 4 节会给出完整文件：

```bitbake
do_compile() {
    oe_runmake CC="${CC}" CPPFLAGS="${CPPFLAGS}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
}
```

`${CC}` 可以包含交叉编译器和参数，必须保留双引号。编译器、预处理选项、
编译选项、链接选项全部由 BitBake 转发；不要在 Makefile 中写死宿主 `gcc`
或优化参数。编译和安装任务均在 `${S}` 中运行。

## 3. unit 文件

继续在 `/work` 执行：

```bash
cat > layers/meta-yp/recipes-demo/yp-tutorial-svc/files/yp-tutorial-svc.service <<'EOF'
[Unit]
Description=YP tutorial foreground service
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/bin/yp-tutorial-svc
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
```

`[Unit]` 描述服务及启动顺序；`After=local-fs.target` 只规定顺序，不会替你
拉起任意依赖服务。`[Service]` 的 `ExecStart` 必须是**目标机**中已安装且可执行
的路径；本例对应配方的 `${bindir}/yp-tutorial-svc`（标准配置为 `/usr/bin`）。

`Type=simple` 用于本例这样的前台常驻进程；进程不能自行转入后台。
若任务只是初始化一次就退出，应选 `Type=oneshot`，通常配合 `Restart=no`；
需要完成后仍显示 `active (exited)` 时再设 `RemainAfterExit=yes`，
不要把它误认为还有常驻进程。没有该选项的一次性任务成功后显示 `inactive`
是正常结果。

`Restart=on-failure` 在非零退出或异常终止时重试，正常退出不重启；
`Restart=always` 也重启正常退出的常驻进程；`Restart=no` 不自动重试。
主动 `systemctl stop` 不会被这些策略立即拉起。本例用 `RestartSec=5`
降低失败后的重试频率，持续失败仍可能触发 systemd 的启动频率限制。

`[Install]` 的 `WantedBy=multi-user.target` 为本例的开机启用提供目标：
enable 会建立该 target 到 unit 的 wants 关系。仓库的服务示例也使用这个目标。
对这种依靠 enable 自启的独立服务，这一项必须有；只写 `After=` 或只安装文件
不会创建自启关系。其他类型的 unit 可以有不同激活机制，不应套用本例。

## 4. 配方

继续在 `/work` 创建完整配方：

```bash
cat > layers/meta-yp/recipes-demo/yp-tutorial-svc/yp-tutorial-svc_0.1.bb <<'EOF'
SUMMARY = "YP tutorial foreground service built with make"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://demo.c file://Makefile file://yp-tutorial-svc.service"
S = "${UNPACKDIR}"

inherit yp-service

YP_SERVICE_NAME = "yp-tutorial-svc"
YP_SERVICE_UNIT = "${YP_SERVICE_NAME}.service"
YP_SRC_DIR = "${UNPACKDIR}"

do_compile() {
    oe_runmake CC="${CC}" CPPFLAGS="${CPPFLAGS}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/yp-tutorial-svc ${D}${bindir}/yp-tutorial-svc
}

FILES:${PN} += "${bindir}/yp-tutorial-svc"
EOF
```

这里沿用现有示例的 MIT 声明及公共许可证校验值；实际业务源码应填写自己的
许可证及相应校验值，不要把 MIT 模板当作第三方源码的授权证明。

三个变量与 `yp-service.bbclass` 的实际实现对应如下：

| 变量 | 类中的默认值 | 本例作用 |
|---|---|---|
| `YP_SERVICE_NAME` | `${PN}` | 服务基名 |
| `YP_SERVICE_UNIT` | `${YP_SERVICE_NAME}.service` | 必须匹配 `SRC_URI` 中的 unit 文件名 |
| `YP_SRC_DIR` | `${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}` | 类安装 unit 时读取的源目录 |

本例显式设置三个变量，便于看清关联；没有 `YP_SERVICE_SRC_DIR` 这个接口。
`S` 控制编译任务目录，`YP_SRC_DIR` 控制 unit 的读取目录，两者不能混为一谈。
本例固定为 6.0；`kas/releases/wrynose.yml` 也设置 `YP_SRC_DIR = "${UNPACKDIR}"`。
旧版解包位置和 override 语法不同，不要原样套用本例的 6.0 配方。

`inherit yp-service` 已间接 `inherit systemd`。类实际设置
`SYSTEMD_SERVICE:${PN} = "${YP_SERVICE_UNIT}"` 和
`SYSTEMD_AUTO_ENABLE:${PN} = "enable"`，并保留旧版下划线形式。
它的 `do_install:append()` 将 unit 以 `0644` 安装到
`${D}${systemd_system_unitdir}/${YP_SERVICE_UNIT}`；配方只负责安装业务程序，
不要重复安装 unit，也不要手写在线 enable 命令。

`${D}` 是打包前的安装暂存根，不是运行中的目标机。
`systemd.bbclass` 负责收集注册的 unit 及离线启用处理。`FILES:${PN}` 的路径
不要带 `${D}`，新增业务文件宜用 `+=`，避免清掉默认打包规则。
本例的可执行文件在 `${bindir}` 下；新增其他位置的配置或数据文件时也必须
安装并覆盖到相应包的 `FILES` 中，否则会出现 `installed-vs-shipped`。

## 5. 进镜像

编辑 `layers/meta-yp/recipes-core/images/yp-image.bb`，在现有
`IMAGE_INSTALL += "wget python3 strace gdbserver"` **下一行**新增：

```bitbake
IMAGE_INSTALL += "yp-tutorial-svc"
```

保留原来的调试工具及后面的 `cpp-hello`、`yp-journald-persist`、
`yp-hello-svc` 行。这个位置的仓库注释说明：新业务只进 `full`，不进 `base`。
构建一个配方只生成包，不会自动把包加入镜像；必须重新构建 `yp-image`。

`IMAGE_INSTALL` 写真实输出包名 `yp-tutorial-svc`（本例就是 `${PN}`），
不是版本文件名或 `virtual/yp-tutorial-svc`。镜像依赖按 `RPROVIDES` 解析；
6.0 的 `virtual-slash` QA 禁止带 `virtual/` 的 `RPROVIDES`，
不能借此把虚拟构建提供者名当作镜像包名。

`layers/meta-yp/conf/distro/yp.conf` 已在 `require conf/distro/poky.conf`
之前写 `INIT_MANAGER = "systemd"`。必须选 `custom` 才使用该 distro 和
`meta-yp` layer；`general` 默认使用 poky 和 `core-image-minimal`，
不能拿它验证本教程的镜像。

## 6. 验证

前提：已按第 1–5 节创建文件并修改镜像；仓库终端有 Docker 权限、对应 release
构建容器及网络，使用非 root 的构建用户。共享环境只串行构建，
不要与其他 BitBake 构建并行运行。下面的构建会消耗磁盘、下载源码，
不是文档静态自验。

在 `/work` 的仓库终端依次执行（失败就先处理错误，不继续起旧镜像）：

```bash
cd /work
mkdir -p work/kas-wrynose-custom work/downloads work/sstate
./project.sh shell --release wrynose --variant custom --machine qemux86-64 -- \
    bash -lc 'KAS_CLONE_DEPTH=1 KAS_WORK_DIR=/work/work/kas-wrynose-custom kas shell /work/kas/targets/wrynose-custom.yml -c "bitbake yp-tutorial-svc"'
bash scripts/build.sh --release wrynose --variant custom --machine qemux86-64 --image full
```

两条命令分别验证配方和包含它的 full 镜像。成功后，在交互终端起机：

```bash
./project.sh shell --release wrynose --variant custom --machine qemux86-64 -- \
    bash -lc 'KAS_WORK_DIR=/work/work/kas-wrynose-custom kas shell /work/kas/targets/wrynose-custom.yml -c "bitbake qemu-helper-native && runqemu yp-image nographic snapshot slirp"'
```

此处直接使用 `runqemu` 保留交互串口；wrynose 的压缩 rootfs 需要 `snapshot`。
到 `login:` 后输入 `root`；full 镜像的 `empty-root-password` 允许串口空密码登录。
**以下命令只在客户机的 root shell 执行，不在构建宿主或 release 容器执行：**

```sh
systemctl is-enabled yp-tutorial-svc.service
systemctl is-active yp-tutorial-svc.service
systemctl status yp-tutorial-svc.service --no-pager
journalctl -u yp-tutorial-svc.service -b --no-pager -n 20
cat /proc/sys/kernel/random/boot_id
systemctl reboot
```

预期前两条分别输出 `enabled`、`active`，journal 能看到
`yp-tutorial-svc alive`。记录本次 boot ID。等客户机重启到登录提示后重新以
`root` 登录，再复制：

```sh
cat /proc/sys/kernel/random/boot_id
systemctl is-enabled yp-tutorial-svc.service
systemctl is-active yp-tutorial-svc.service
journalctl -u yp-tutorial-svc.service -b --no-pager -n 20
```

boot ID 应不同；没有手动 `start` 或 `enable`，服务仍为 `enabled`、`active`，
当前启动的 journal 仍有消息，才算完成重启自启验证。若 QEMU 在 reboot 时结束，
重新执行起机命令，再检查 boot ID 和服务状态。退出 QEMU 使用 Ctrl-a 然后 x。
snapshot 不保留客户机运行期手改，正好检查构建产物是否已经带有自启关系。

### 常见错误：现象 → 原因 → 怎么改

- `System has not been booted with systemd` / `Failed to connect to bus` → 在构建宿主或容器执行了在线 `systemctl`，那不是目标机的 systemd → 运行期检查放到客户机；rootfs 离线启用须使用 `systemctl --root=${D}`，由 `systemd.bbclass` 代劳，不要在配方手写在线 enable。
- unit 已装但 `systemctl is-enabled` 输出 `disabled` → 未继承 `systemd`（本仓库应 `inherit yp-service`）、`SYSTEMD_SERVICE:${PN}` 名字与安装文件不一致，或启用配置被覆盖 → 核对继承、`YP_SERVICE_UNIT` 与实际文件名，以及 `SYSTEMD_AUTO_ENABLE:${PN}` 为 `"enable"`，重建并启动新镜像；文件名不一致也可能先在构建期报错。
- `status=203/EXEC` → `ExecStart` 文件没有进入包或没有执行位，也可能路径、解释器或架构不对 → 对照安装路径和 `FILES:${PN}`，用 `install -m 0755` 安装程序，使用 BitBake 的交叉编译器，再重建镜像。
- `do_compile` 找不到源文件 → 沿用了 `S = "${WORKDIR}"`，6.0 的本地文件不解到那里 → 本例改为 `S = "${UNPACKDIR}"`，unit 源目录也用 `YP_SRC_DIR = "${UNPACKDIR}"`，核对 `SRC_URI` 是否列齐文件。
- 改了源码树里的 unit，重启仍是老行为 → 镜像里的 unit 是构建期安装的，重启没有替换旧 rootfs → 重建配方及 `yp-image` 并启动或部署新镜像；`systemctl daemon-reload` 只重新读取运行机上已经改过的 unit，不能把仓库文件送进目标机。
- 服务起了立刻退出，journal 只见 `Main process exited` → `Type=simple` 的前台进程自行转入后台，或本来就是一次性程序 → 常驻程序保持前台运行；真正一次性任务改用 `Type=oneshot`，按需要设置 `RemainAfterExit=yes`，不要用无限重启掩盖类型错误。
- `installed-vs-shipped` QA 报错 → 新配置或数据文件已经安装到 `${D}`，但没有任何包收走 → 将对应目标路径加入 `FILES:${PN} += "..."`（不带 `${D}`），重跑打包和镜像构建。
- 想用 `/etc/init.d/*`、`update-rc.d` 或 `start-stop-daemon` 实现自启 → 混用了旧式服务管理；仓库是 systemd-only，6.0 没有这条兼容退路 → 不要这么做，也不要加 pidfile 或 LSB 头；使用 `.service`、前台进程和 `inherit yp-service`。
- 构建成功但客户机 `Unit ... could not be found` → 只构建了配方，没把真实包加入 `yp-image`，或启动了旧镜像 / general 镜像 → 核对第 5 节的 `IMAGE_INSTALL`，构建 `custom/full`，明确用 `runqemu yp-image` 启动新产物。

### 证据边界

**仓库读取已确认**：三个 `YP_*` 接口、unit 安装及注册规则、默认 enable、
现成 `yp-hello-svc` 的前台日志模式、full 镜像添加位置、distro 的 systemd 设置，
以及构建入口的 release/variant/image 参数和 wrynose 起机的 snapshot 用法。

**仍须 L3 实际构建及起机确认**：本文新配方的交叉编译和 QA、程序及 unit 是否
进入新镜像、离线启用是否最终产出正确关系、运行期 `enabled` / `active` / journal
输出，以及重启后自动启动。本次文档自验不等于这些验证，未执行 L3，
也不能据此宣称已在真实硬件验证；硬件部署另须使用对应 machine 的镜像及启动流程。
