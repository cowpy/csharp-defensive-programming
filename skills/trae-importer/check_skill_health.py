#!/usr/bin/env python3
"""WorkBuddy 技能健康检查 + 上下文成本统计。

背景：Trae 导出的 SKILL.md 可能带 UTF-8 BOM，导致 WorkBuddy 的 YAML
frontmatter 解析失败 —— 该技能只会显示 "name: name"（拿 name 当 description），
结果是永远不会被自动触发，等于白装。本脚本用于体检并修复。

用法：
    python check_skill_health.py             # 只检查，报告问题
    python check_skill_health.py --fix       # 自动去除 BOM（改动前自动备份 .bak）
    python check_skill_health.py --dir PATH  # 指定其他技能目录

检查项：
    1. BOM         —— 前 3 字节 239,187,191，SKILL.md 绝不能带
    2. frontmatter —— 能否正确解析出 name / description
    3. description —— 长度 < 30 字符预警（太短会漏触发）
附带输出上下文成本：常驻（name+description）与按需（正文）的体量对比。

作者：LHG
"""
import argparse
import os
import re
import shutil
import sys

DEFAULT_DIR = os.path.join(os.path.expanduser("~"), ".workbuddy", "skills")
BOM = b"\xef\xbb\xbf"

FM = re.compile(r"^---\s*\n(.*?)\n---", re.S)
NAME = re.compile(r'^name:\s*"?(.+?)"?\s*$', re.M)
DESC = re.compile(r'^description:\s*"?(.+?)"?\s*$', re.M)

SHORT_DESC = 30


def parse(skill_dir):
    """解析单个技能，返回 (name, description, body_len)。"""
    p = os.path.join(skill_dir, "SKILL.md")
    raw = open(p, "rb").read()
    has_bom = raw[:3] == BOM
    text = raw.decode("utf-8-sig", errors="ignore")
    m = FM.match(text)
    name, desc = os.path.basename(skill_dir), ""
    if m:
        nm, dm = NAME.search(m.group(1)), DESC.search(m.group(1))
        if nm:
            name = nm.group(1).strip()
        if dm:
            desc = dm.group(1).strip()
    body = text[m.end():] if m else text
    return name, desc, len(body), has_bom


def scan(base):
    """扫描技能目录，返回 [(dirname, name, desc, body_len, has_bom)]."""
    rows = []
    for d in sorted(os.listdir(base)):
        if os.path.isfile(os.path.join(base, d, "SKILL.md")):
            name, desc, blen, bom = parse(os.path.join(base, d))
            rows.append((d, name, desc, blen, bom))
    return rows


def fix_bom(base, rows):
    """去除带 BOM 的 SKILL.md，改动前备份 .bak。返回修复数量。"""
    fixed = 0
    for d, _, _, _, has_bom in rows:
        if not has_bom:
            continue
        p = os.path.join(base, d, "SKILL.md")
        shutil.copy2(p, p + ".bak")
        raw = open(p, "rb").read()
        open(p, "wb").write(raw[len(BOM):])
        print(f"  [已修复] {d}  (备份 {os.path.basename(p)}.bak)")
        fixed += 1
    return fixed


def report(rows):
    """输出体检报告。"""
    n = len(rows)
    bom_list = [r for r in rows if r[4]]
    bad_fm = [r for r in rows if not r[2] and not r[4]]
    short = [r for r in rows if 0 < len(r[2]) < SHORT_DESC]

    tot_name = sum(len(r[1]) for r in rows)
    tot_desc = sum(len(r[2]) for r in rows)
    tot_body = sum(r[3] for r in rows)

    print("=" * 62)
    print(f"WorkBuddy 技能健康检查  ({n} 个技能)")
    print("=" * 62)

    print("\n【1】BOM 检查")
    if bom_list:
        print(f"  ✗ {len(bom_list)} 个带 BOM，会导致 description 解析失败、技能永不触发：")
        for r in bom_list:
            print(f"      - {r[0]}")
        print("      → 运行 --fix 自动去除")
    else:
        print("  ✓ 无 BOM 问题")

    print("\n【2】frontmatter 解析")
    if bad_fm:
        print(f"  ✗ {len(bad_fm)} 个无法解析出 description：")
        for r in bad_fm:
            print(f"      - {r[0]}")
    else:
        print("  ✓ 全部可正常解析")

    print("\n【3】description 长度")
    if short:
        print(f"  ! {len(short)} 个描述过短（<{SHORT_DESC} 字符），可能漏触发：")
        for r in short:
            print(f"      - {r[0]}  ->  {r[2]!r}")
    else:
        print("  ✓ 描述长度正常")

    print("\n【4】上下文成本")
    print(f"  常驻（name + description）: {tot_name + tot_desc:,} 字符  "
          f"≈ {int((tot_name + tot_desc) / 3):,} tokens")
    print(f"  按需（SKILL.md 正文）      : {tot_body:,} 字符  "
          f"≈ {int(tot_body / 3):,} tokens")
    if tot_body:
        print(f"  常驻仅占正文 {((tot_name + tot_desc) / tot_body * 100):.1f}% —— "
              "技能多不等于开销大，真正成本是误触发")

    ok = not bom_list and not bad_fm
    print("\n" + ("=" * 62))
    print("结论：" + ("健康" if ok else f"发现 {len(bom_list) + len(bad_fm)} 个问题，建议修复"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="WorkBuddy 技能健康检查")
    ap.add_argument("--dir", default=DEFAULT_DIR, help="技能目录，默认 ~/.workbuddy/skills")
    ap.add_argument("--fix", action="store_true", help="自动去除 BOM")
    args = ap.parse_args()

    if not os.path.isdir(args.dir):
        print(f"目录不存在：{args.dir}")
        return 2

    print(f"扫描目录：{args.dir}\n")
    if args.fix:
        fixed = fix_bom(args.dir, scan(args.dir))
        print(f"\n共修复 {fixed} 个\n")
    return report(scan(args.dir))


if __name__ == "__main__":
    sys.exit(main())
