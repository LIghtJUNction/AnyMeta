# KernelSU 发布流程

AnyMeta 的源码和开发 Release 在 `LIghtJUNction/AnyMeta`。KernelSU 组织仓库不由
个人直接创建，官方流程是在 `KernelSU-Modules-Repo/submission` 提交 Issue：

```text
[submission] AnyMeta
```

机器人会创建同名的 `KernelSU-Modules-Repo/AnyMeta` 仓库，并邀请作者为管理员。
本项目的正式申请：

https://github.com/KernelSU-Modules-Repo/submission/issues/84

申请中已提供模块 ID、作者、许可证、源码仓库和 `v0.1.0` Release。组织仓库创建后，
维护者应在该仓库运行：

```sh
kam workflow install LIghtJUNction/AnyMeta
```

由于上游仓库与镜像仓库不同，Kam 会安装
`.github/workflows/mirror-upstream-release.yml`，按小时同步源码仓库的最新
GitHub Release，不重新打包 ZIP。镜像仓库必须保留根目录 `module.json`、
`README.md` 和由 Release 机器人生成的模块元数据。

## Developer key

不要重新生成 developer key。主仓库 CI 的 `exec.yml` 只读取 GitHub Actions Secret
`KAM_PRIVATE_KEY`；将已有 KernelSU developer 私钥以多行 PEM 文本写入该 Secret，
即可启用 Kam 签名发布。私钥绝不能提交到源码仓库、组织镜像仓库、Issue 或工作流日志。

公钥申请入口：

https://github.com/KernelSU-Modules-Repo/developers/issues/new?template=keyring.yml
