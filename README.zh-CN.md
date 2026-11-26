# oracle-db-silent-install

一个用于在 RHEL 系 Linux 上静默安装 Oracle Database 11gR2 / 12c / 18c / 19c 的
智能体技能（Agent Skill）——可复现、分阶段、且密码永远不会经过聊天窗口。

[English](README.md) · [安装说明](INSTALL.md) · [示例](examples/) · [参与贡献](CONTRIBUTING.md) · [安全策略](SECURITY.md)

---

## 它解决的是什么问题

静默安装 Oracle 的失败点高度集中，而每一次失败都伪装成别的问题：

| 你看到的现象 | 真正的原因 |
|---|---|
| `cvc-complex-type.2.4.a: Invalid content ... 'memoryType'` | 把 11g 时代的内存键喂给了 19c 的 `dbca` 响应文件 |
| 安装"成功"了，但 `sqlplus` 报 `GLIBC_2.14 not found` | 这台机器的 glibc 根本跑不了这套二进制 |
| 静默安装卡住，在等 MOS 账号 | 精简模板缺了 `DECLINE_SECURITY_UPDATES` |
| 号称"本机测试"的库，局域网里能连上 | `netca` 把监听器绑到了 FQDN，而不是回环地址 |
| 花一小时改 `/etc/hosts`，可它本来就是对的 | `getent hosts` 返回了 IPv6 回环别名 |

让智能体临场发挥只会更糟：它会在一份还没人确认的方案之上，心安理得地
`mkdir`、`chown`、解压；而一个被敲进对话的密码，就等于已经泄露了。

这个技能把"闯过那片雷区"的那次部署固化了下来——CentOS 7.9、3.7 GB 内存、
单实例 19c、监听器只绑回环——抽象成带硬性闸门的分阶段流程，外加一组让响应文件
可确定的生成器。

## 安全模型

六条规则，靠结构约束，而不是靠自觉：

1. **先只读，后写入。** `precheck.sh` 只体检、只报告；方案未获批准前，不建目录、
   不装包、不跑安装器。
2. **root 步骤归人。** `gen_root_prep.sh` 只**打印**命令块。智能体不亲自执行
   `mkdir`/`chown`/`yum`/`sysctl -w`，也绝不索取 root 密码。
3. **密钥材料不外泄。** SSH 私钥由客户端隐式使用；其内容、指纹、Base64 片段不得
   进入任何日志或回复。
4. **密码留在目标机上。** 响应文件里只有 `__CHANGE_ME_SYS__` 这类占位符，由人在
   目标机终端用 `fill_dbca_passwords.sh`（`read -s` 无回显）填写；该脚本没有 TTY
   会直接拒绝执行。
5. **阶段闸门。** 七个阶段、七个检查点。`runInstaller` 和两个 root 脚本未经验证，
   不得启动 `dbca`。
6. **清理放最后，且只切一刀。** 验证通过后，只删那个安装 zip。绝不 `rm -rf` 任何
   `oradata` 目录。

## 快速开始

```bash
git clone https://github.com/huanhui109/oracle-db-silent-install.git
cd oracle-db-silent-install

# 0. 先体检：对目标机的只读普查
ssh <alias> 'bash -s -- 19c' < scripts/precheck.sh

# 1. 看清全貌：每一步由谁执行，一目了然
HOST_ALIAS=<alias> VERSION=19c bash scripts/show_plan.sh 19c

# 2. 生成产物（除指定输出文件外，无任何副作用）
bash scripts/gen_env_file.sh - 19c
bash scripts/gen_root_prep.sh 19c > root_prep.sh
bash scripts/gen_dbca_rsp.sh /home/oracle/dbca.rsp 19c
TNS_OUT=$ORACLE_HOME/network/admin/tnsnames.ora \
  bash scripts/gen_listener_ora.sh $ORACLE_HOME/network/admin/listener.ora
```

或者交给智能体：让它读 `SKILL.md`（见[安装说明](INSTALL.md)），它会沿着同样的
七个阶段推进，并在每个检查点停下来等人确认。

## 目录结构

```
oracle-db-silent-install/
├── SKILL.md                  # 技能入口：规则、阶段、路由
├── references/               # 只在对应阶段需要时才加载的细节
│   ├── version-matrix.md     #   11g / 12c / 18c / 19c 差异：glibc、键位、介质
│   ├── planning.md           #   目录树、空间预算、内存配比、root 命令模板
│   └── pitfalls.md           #   12 个实战踩过的坑与确切解法
├── scripts/                  # 9 个自包含 bash 脚本
├── examples/                 # 两套生成好的配置档案 + 完整走查
├── tests/                    # 离线测试套件（不依赖 Oracle、不联网）
└── 文档位于根目录：INSTALL / CONTRIBUTING / SECURITY / CHANGELOG
```

`references/` 的存在是为了让智能体只在真正要选版本时读那 80 行差异说明，而不是
把整本手册都塞进上下文。

## 七个阶段

| 阶段 | 执行者 | 产物 |
|---|---|---|
| 0 — 体检 | 智能体，只读 | 带 `BLOCKER:` 行的体检报告 |
| 1 — 方案与批准 | 智能体，再由人拍板 | `plan-19c.txt` |
| 2 — 系统准备 | **root，由人执行** | `root_prep.sh` |
| 3 — 软件安装 | oracle 用户 | `db_install.rsp` → `runInstaller` |
| 4 — root 脚本 | **root，由人执行** | `orainstRoot.sh`、`root.sh` |
| 5 — 监听器与建库 | oracle 用户，密码由人输入 | `listener.ora`、`dbca.rsp` |
| 6 — 验证与清理 | 智能体，只读 | `verify.sh` 报告 |

## 脚本清单

九个脚本。会写文件的那几个，都只写一个文件，并且把它写出来告诉你。

| 脚本 | 用途 | 写入 |
|---|---|---|
| `precheck.sh` | 只读体检，输出 `BLOCKER:`/`WARN:` 结论 | 无 |
| `verify.sh` | 只读安装后验证（实例、CDB 标志、字符集、内存、监听） | 无 |
| `show_plan.sh` | 打印分阶段方案，标注 `[AGENT]`/`[ROOT]`/`[ORACLE]` | 无（标准输出） |
| `gen_root_prep.sh` | 按真实内存推导并打印 root 准备块 | 无（标准输出） |
| `gen_env_file.sh` | oracle 用户环境块（`ORACLE_BASE/HOME/SID/PATH/...`） | 一个文件 |
| `gen_db_install_rsp.sh` | 基于介质模板生成软件安装响应文件 | 一个文件 |
| `gen_dbca_rsp.sh` | 生成 `dbca` 响应文件，键位随版本，密码为占位符 | 一个文件 |
| `gen_listener_ora.sh` | 生成回环 `listener.ora`（可选同时生成 `tnsnames.ora`） | 一到两个文件 |
| `fill_dbca_passwords.sh` | 交互式无回显填写密码，必须有 TTY | 编辑一个文件 |

每个脚本都自包含——没有公共库、不 `source` 任何东西——所以
`ssh host 'bash -s -- args' < script.sh` 可行。只读脚本正是靠这种"流式"方式
抵达目标机，不在对方磁盘上留任何东西。

## 版本支持

| 版本 | glibc 下限 | 介质形态 | `dbca` 内存键 | 状态 |
|---|---|---|---|---|
| 19c | `GLIBC_2.14` | 镜像 zip，直接解压进 `ORACLE_HOME` | `initParams` | 推荐 |
| 18c | `GLIBC_2.14` | 镜像 zip | `initParams` | 可用，已停止支持 |
| 12cR2 | `GLIBC_2.14` | 镜像 zip | `initParams` | 已停止支持 |
| 11gR2 | 2.12 即可 | 双 zip，先解压到暂存目录 | `sgaTarget` / `pgaAggregateTarget` | 已停止支持 |

CentOS / Rocky / Alma 属于 Oracle 官方**不支持**的平台。二进制能跑，
`CV_ASSUME_DISTID=OL7` 配合 `-ignorePrereqFailure` 可以绕过 OS 检查。技能要求
智能体必须把这一点明确说出来，并写进方案。

细节见 [`references/version-matrix.md`](references/version-matrix.md)。

## 一次真实部署的全程复盘

[`examples/19c-minimal-centos79/walkthrough.md`](examples/19c-minimal-centos79/walkthrough.md)
逐阶段记录了命令、关键输出，以及两个转折：一台机器上"还没开始就结束"的 glibc
阻断，和另一台机器上耗掉一下午的 `dbca` XSD 报错。

## 测试

```bash
make test          # 等价于 bash tests/run_tests.sh
make lint          # 全量 bash -n，装了 shellcheck 就跑
```

28 组用例（83 条断言），可在 macOS 和 Linux 上离线运行：不需要 Oracle、不联网、
不用 root。断言的都是要紧的契约——键位随版本正确、安装选项不重复、响应文件权限为
`600`、密码填写脚本无 TTY 时以退出码 3 拒绝执行、任何生成产物都不可能出现明文密码。

## 环境要求

- 跑生成器的机器需要 bash 3.2+（macOS 与 Linux 均可）
- 目标机为 RHEL 系、bash 4+，阶段 2 与 4 需要 root
- Oracle 安装介质需你自行从 Oracle 获取。本仓库不下载、不分发任何 Oracle 软件

## 参与贡献

先读 [CONTRIBUTING.md](CONTRIBUTING.md)。要点：脚本保持自包含、`set -eu`、只写一个
文件、写完把结果打印出来、每新增一种行为就补一个测试。永远不要提交带真实密码的
响应文件。

## 许可证与免责声明

MIT，见 [LICENSE](LICENSE)。

本项目与 Oracle 公司无隶属、背书或支持关系。Oracle Database 是 Oracle 公司的商标。
你的安装是否需要授权由你负责；本仓库只固化了机械性的部署步骤。
