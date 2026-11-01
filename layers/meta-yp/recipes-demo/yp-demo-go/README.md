# yp-demo-go

Yocto 的关键变量是 `GO_IMPORT`；`go-mod` 使用
`${UNPACKDIR}/src/${GO_IMPORT}` 中的源码，`yp-service` 注册并启用 systemd unit。
配方只安装可执行文件，unit 由公共类安装；加入 full 镜像由人工集成完成。

`vendor/example.com/yp/greeting` 是本示例自有的 MIT 模块，不依赖外部下载。
`vendor/modules.txt` 与 `go.mod` 对应；`-mod=vendor`、`GOPROXY=off` 和
`GOSUMDB=off` 强制离线构建，因此不需要下载校验用的 `go.sum`。
`-trimpath` 移除源码及构建目录中的宿主路径，交叉编译参数沿用 Yocto 类。

本机可在此目录执行：

```sh
GOSUMDB=off GOPROXY=off go build -mod=vendor -trimpath -o /tmp/yp-demo-go .
/tmp/yp-demo-go --help
/tmp/yp-demo-go --version
/tmp/yp-demo-go --json
```

默认输出一次问候并退出；服务使用 `--json --daemon` 每 10 秒向 journal 输出一次，
收到 SIGTERM 或 SIGINT 后正常退出。未知选项或多余参数返回非零退出码。
