#!/usr/bin/env bash
# =============================================================================
# scripts/dm-verity.sh —— 把已构建的 squashfs 根镜像升级为 dm-verity 保护镜像
#
#   scripts/dm-verity.sh --release <r> [--variant <v>] [--machine <m>]
#                         [--tamper-test] [--revert]
#
# 做三件事（对应 docs/qa/security/dm-verity-feasibility.md 的三步手工活）：
#   1. 容器内 veritysetup format：<rootfs>.squashfs → verity-hash.img
#   2. hash 镜像落 deploy 目录（verity-hash.img）
#   3. 改写 qemuboot.conf：root=/dev/dm-0 + dm-mod.create（含 root hash/salt）
#      + QB_OPT_APPEND 挂 hash 盘 —— 之后 qemu.sh/boot-exec.sh/boot-time.sh
#      走标准 runqemu 链路即可起受保护镜像，无需任何手工参数。
#
# 前置：镜像以 squashfs 构建（kas/features/rootfs-squashfs.yml），
#       内核含 DM_VERITY/DM_INIT（yp-minimal.cfg 已有三版通用配置）。
# --revert：恢复原始 qemuboot.conf 备份并删除 verity-hash.img。
# --tamper-test：翻转 data 镜像一个字节 → 起机 30s → 断言内核报
#                data block N is corrupted → 还原字节。（保护性证据）
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'USAGE'
用法：scripts/dm-verity.sh --release <r> [--variant <v>] [--machine <m>]
                           [--tamper-test] [--revert]

  --variant     默认 custom
  --machine     默认 qemux86-64
  --tamper-test 翻转一个字节起机验证校验生效，然后还原
  --revert      恢复 qemuboot.conf 原始备份并移除 verity-hash.img
USAGE
}

release="" variant="custom" machine="qemux86-64" do_tamper=0 do_revert=0
while (($# > 0)); do
    case "$1" in
        --release) (($# >= 2)) || die "--release 缺少参数"; release="$2"; shift 2 ;;
        --variant) (($# >= 2)) || die "--variant 缺少参数"; variant="$2"; shift 2 ;;
        --machine) (($# >= 2)) || die "--machine 缺少参数"; machine="$2"; shift 2 ;;
        --tamper-test) do_tamper=1; shift ;;
        --revert) do_revert=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) die "未知参数：$1（--help 看用法）" ;;
    esac
done
[[ -n "${release}" ]] || { usage; die "必须指定 --release"; }

machine_sfx=""
[[ "${machine}" == "qemux86-64" ]] || machine_sfx="-${machine}"
deploy="${ROOT_DIR}/work/kas-${release}-${variant}${machine_sfx}/build/tmp/deploy/images/qemux86-64"
[[ -d "${deploy}" ]] || die "deploy 目录不存在：${deploy}（先构建镜像）"

qb="${deploy}/yp-image-minimal-qemux86-64.rootfs.qemuboot.conf"
[[ -f "${qb}" ]] || die "qemuboot.conf 不存在：${qb}"

# ---- --revert：恢复备份 ----
if ((do_revert)); then
    [[ -f "${qb}.pre-verity" ]] || die "没有 pre-verity 备份可恢复"
    cp "${qb}.pre-verity" "${qb}"
    rm -f "${deploy}/verity-hash.img"
    echo "dm-verity: 已恢复 ${qb}.pre-verity 并移除 verity-hash.img"
    exit 0
fi

data_img="$(readlink -f "${deploy}/yp-image-minimal-qemux86-64.rootfs.squashfs" 2>/dev/null || true)"
[[ -n "${data_img}" && -f "${data_img}" ]] ||
    die "找不到 squashfs 根镜像（先叠加 kas/features/rootfs-squashfs.yml 构建）"

# ---- 1/2：容器内 veritysetup format ----
echo "dm-verity: veritysetup format（容器内，数据 $(stat -Lc %s "${data_img}") 字节）"
rm -f "${deploy}/verity-hash.img"
truncate -s 32M "${deploy}/verity-hash.img"
vf_output="$(docker run --rm -u root \
    -v "${deploy}:/verity" \
    "ghcr.io/zeek-zhao/yp-distro/${release}:latest" bash -c '
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq cryptsetup >/dev/null 2>&1
veritysetup format /verity/'"$(basename "${data_img}")"' /verity/verity-hash.img' 2>/dev/null)"

root_hash="$(printf '%s\n' "${vf_output}" | awk '/^Root hash:/{print $3}')"
salt="$(printf '%s\n' "${vf_output}" | awk '/^Salt:/{print $2}')"
data_blocks="$(printf '%s\n' "${vf_output}" | awk '/^Data blocks:/{print $3}')"
[[ -n "${root_hash}" && -n "${salt}" && -n "${data_blocks}" ]] ||
    { echo "${vf_output}" >&2; die "veritysetup 输出解析失败"; }
table_sectors=$((data_blocks * 8))
echo "dm-verity: blocks=${data_blocks} root_hash=${root_hash:0:12}… salt=${salt:0:12}…"

# ---- 3：改写 qemuboot.conf（幂等：备份一次，之后在备份基础上重打）----
if [[ ! -f "${qb}.pre-verity" ]]; then
    cp "${qb}" "${qb}.pre-verity"
fi
python3 - "${qb}" "${table_sectors}" "${root_hash}" "${salt}" <<'PY'
import configparser, sys
qb, sectors, root_hash, salt = sys.argv[1:5]
cp = configparser.ConfigParser(interpolation=None)
cp.optionxform = str
cp.read(qb)
s = 'config_bsp'
# 表：0 <len 扇区> verity 1 <data> <hash> 4096 4096 <blocks> 1 sha256 <roothash> <salt>
# （长度单位是 512 字节扇区 = 数据块数 × 8；hash_start=1 跳过 cryptsetup superblock；
#   salt 是第 10 个必需参数——三条规则的出处见 docs/knowledge-base.md KB-15）
data_blocks = int(sectors) // 8
dm_table = f'0 {sectors} verity 1 /dev/vda /dev/vdb 4096 4096 {data_blocks} 1 sha256 {root_hash} {salt}'
dm = f'dm-mod.create="verityroot,,,ro,{dm_table}"'
# 大小写不敏感地删除旧键再写入——文件里键是小写，大小写变体会造成
# DuplicateOptionError，runqemu 的 configparser 直接崩（首版踩过）
def del_keys(section, name):
    for k in [k for k in section if k.lower() == name.lower()]:
        del section[k]
for key in ('QB_DEFAULT_FSTYPE', 'QB_KERNEL_ROOT', 'QB_KERNEL_CMDLINE_APPEND', 'QB_OPT_APPEND'):
    del_keys(cp[s], key)
cp[s]['QB_DEFAULT_FSTYPE'] = 'squashfs'
cp[s]['QB_KERNEL_ROOT'] = '/dev/dm-0 ro rootfstype=squashfs rootwait'
base_cmd = ' '.join(
    tok for tok in cp[s].get('qb_kernel_cmdline_append', '').split()
    if not tok.startswith('dm-mod.create='))
cp[s]['qb_kernel_cmdline_append'] = (base_cmd + ' ' + dm).strip()
opt = cp[s].get('qb_opt_append', '')
opt = ' '.join(tok for tok in opt.split() if 'verity-hash.img' not in tok)
cp[s]['qb_opt_append'] = (opt + ' -drive file=@DEPLOY_DIR_IMAGE@/verity-hash.img,if=virtio,format=raw').strip()
with open(qb, 'w') as f:
    cp.write(f, space_around_delimiters=False)
print('qemuboot.conf 已更新（root=/dev/dm-0，hash 盘经 QB_OPT_APPEND 挂载）')
PY

echo "dm-verity: 完成（处理对象 yp-image-minimal；full/base 不受影响）。标准链路直接可用："
echo "  bash scripts/qemu.sh --release ${release} --variant ${variant} --machine ${machine}"
echo "  回退：bash scripts/dm-verity.sh --release ${release} --revert"

# ---- 可选：篡改自检 ----
if ((do_tamper)); then
    echo "dm-verity: 篡改自检（翻转 data 10MB 处 1 字节 → 起机 40s → 还原）"
    python3 - "${data_img}" <<'PY'
import sys
f = open(sys.argv[1], 'r+b')
f.seek(10 * 1024 * 1024)
b = f.read(1)
f.seek(10 * 1024 * 1024)
f.write(bytes([b[0] ^ 0xFF]))
f.close()
PY
    # 必须显式 YP_IMAGE：qemu.sh 默认起 full（未打补丁），受保护对象是 minimal
    YP_IMAGE=yp-image-minimal bash "${ROOT_DIR}/scripts/qemu.sh" --release "${release}" \
        --variant "${variant}" --machine "${machine}" --timeout 40 \
        >"/tmp/dm-verity-tamper-${release}.log" 2>&1 || true
    python3 - "${data_img}" <<'PY'
import sys
f = open(sys.argv[1], 'r+b')
f.seek(10 * 1024 * 1024)
b = f.read(1)
f.seek(10 * 1024 * 1024)
f.write(bytes([b[0] ^ 0xFF]))
f.close()
PY
    if grep -aq "data block .* is corrupted" "/tmp/dm-verity-tamper-${release}.log"; then
        echo "dm-verity: 篡改被逐块检出 ✓（见 /tmp/dm-verity-tamper-${release}.log）"
    else
        die "篡改未被检出——校验未生效，检查 dm 表"
    fi
fi
