#!/usr/bin/env python3
"""
Trae -> WorkBuddy 技能/规则一键迁移工具
========================================
扫描 TraeCode(.trae/skills) 与 TraeWork(.trae-cn/skills) 的全局技能，
解析软链接指向 .agents/skills 的真实内容；扫描 Trae 全局规则
(.trae-cn/user_rules 与 .trae/user_rules)；对每个技能做安全审计；
将审计通过的技能复制到 ~/.workbuddy/skills/，将规则转换为技能。

用法:
  python trae_to_workbuddy.py --dry-run       # 仅扫描+审计，不写入
  python trae_to_workbuddy.py --apply         # 执行导入
  python trae_to_workbuddy.py --apply --include-builtin   # 额外导入内置人格技能
"""
import argparse
import json
import os
import re
import shutil
import sys

HOME = os.path.expanduser("~")
DEST = os.path.join(HOME, ".workbuddy", "skills")

TRAEECODE_GLOBAL = os.path.join(HOME, ".trae", "skills")
TRAEWORK_GLOBAL = os.path.join(HOME, ".trae-cn", "skills")
TRAEECODE_RULES = os.path.join(HOME, ".trae", "user_rules")
TRAEWORK_RULES = os.path.join(HOME, ".trae-cn", "user_rules")
BUILTIN_TRAECODE = os.path.join(HOME, ".trae-cn", "builtin", "trae")
BUILTIN_TRAEWORK = os.path.join(HOME, ".trae-cn", "builtin", "work")

# 危险模式（安全审计用）。命中即标记为需人工复核，不自动安装。
DANGER_PATTERNS = [
    (r"rm\s+-rf\s+/", "rm -rf on absolute path"),
    (r"rmdir\s+/[sq]", "rmdir forced on windows"),
    (r":\(\)\s*\{.*\|:", "fork bomb"),
    (r">\s*/dev/sd", "overwrite block device"),
    (r"curl\s+.{0,200}\|\s*(sh|bash)", "curl piped to shell"),
    (r"wget\s+.{0,200}\|\s*(sh|bash)", "wget piped to shell"),
    (r"powershell\s+-enc", "powershell encoded command"),
    (r"\bIEX\s*\(", "PowerShell Invoke-Expression"),
    (r"Invoke-Expression", "PowerShell Invoke-Expression"),
    (r"base64\s+-d\s*\|\s*(sh|bash)", "base64 decode piped to shell"),
    (r"bash\s+-i\s+>&\s*/dev/tcp", "reverse shell"),
    (r"/dev/tcp/", "bash /dev/tcp reverse shell"),
    (r"cat\s+/etc/shadow", "read shadow file"),
    (r"curl\s+.{0,200}-o\s+/tmp/", "download to tmp via curl"),
    (r"subprocess\.\w+\(.*shell\s*=\s*True", "subprocess shell=True"),
    (r"os\.system\(", "os.system call"),
    (r"eval\s*\(", "eval call"),
    (r"exec\s*\(", "exec call"),
]

DANGER_RE = [(re.compile(p, re.IGNORECASE), d) for p, d in DANGER_PATTERNS]


def find_skill_dirs(root, recursive=False):
    """返回 root 下所有技能目录（解析软链接到真实路径），去重。"""
    out = {}
    if not os.path.isdir(root):
        return out
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        real = os.path.realpath(p)
        if os.path.isdir(real):
            # 递归扫描 builtin 的 * /skills 层级
            if recursive:
                sub = os.path.join(real, "skills")
                if os.path.isdir(sub):
                    for s in find_skill_dirs(sub):
                        out[s] = out.get(s)
                    # 也把该人格目录本身当技能（若含 SKILL.md）
            if os.path.exists(os.path.join(real, "SKILL.md")):
                out[real] = True
            else:
                # 可能是按子目录分组的（如 builtin persona/skills/<skill>）
                for child in sorted(os.listdir(real)):
                    cp = os.path.realpath(os.path.join(real, child))
                    if os.path.isdir(cp) and os.path.exists(os.path.join(cp, "SKILL.md")):
                        out[cp] = True
    return out


# 已人工复核、确认无害的技能（其危险模式为误报）：
#  - dotnet-devcert-trust: rm -rf 仅删除 aspnet 开发证书目录，非用户数据
#  - redis-development: 命中的是 Redis 事务命令 MULTI/EXEC
#  - security-best-practices: 参考文档在讲解应避免 eval/exec 等危险 sink（教学性内容）
REVIEWED_SAFE = {"dotnet-devcert-trust", "redis-development", "security-best-practices"}


def audit_skill(skill_dir):
    """扫描技能目录内容，返回命中的危险项列表。"""
    if os.path.basename(skill_dir.rstrip("/\\")) in REVIEWED_SAFE:
        return []
    hits = []
    for dirpath, _, files in os.walk(skill_dir):
        for fn in files:
            fp = os.path.join(dirpath, fn)
            try:
                with open(fp, "r", encoding="utf-8-sig", errors="ignore") as f:
                    text = f.read()
            except Exception:
                continue
            for rgx, desc in DANGER_RE:
                if rgx.search(text):
                    rel = os.path.relpath(fp, skill_dir)
                    hits.append({"file": rel, "reason": desc})
    return hits


BOM_BYTES = b"\xef\xbb\xbf"
BOM_CHAR = "\ufeff"
TEXT_EXT = (".md", ".markdown", ".yml", ".yaml", ".json", ".txt")


def strip_bom_tree(root):
    """递归剥离目录下所有文本文件的 UTF-8 BOM，返回被修复的文件数。

    原因：WorkBuddy 读取 SKILL.md 用 ``fs.readFile(p, 'utf-8')`` + 正则
    ``/^---\\r?\\n([\\s\\S]*?)\\r?\\n---/`` 解析 frontmatter。Node 的 ``utf-8``
    **不剥离 BOM**，而正则以 ``^`` 锚定且无 ``m`` 标志，因此文件首字节为 BOM 时
    匹配必然失败 → frontmatter 退化为空 → 技能降级为「用目录名当描述」，
    **永远不会自动触发**。Windows 编辑器（记事本、部分 IDE）保存即带 BOM，
    Trae 导出的技能同样常见，必须在导入阶段清掉。
    """
    fixed = 0
    for dirpath, _, files in os.walk(root):
        for fn in files:
            if not fn.lower().endswith(TEXT_EXT):
                continue
            fp = os.path.join(dirpath, fn)
            try:
                with open(fp, "rb") as f:
                    raw = f.read()
            except Exception:
                continue
            if raw[:3] == BOM_BYTES:
                with open(fp, "wb") as f:
                    f.write(raw[len(BOM_BYTES):])
                fixed += 1
    return fixed


def normalize_frontmatter(text):
    """保留 Trae 的 SKILL.md，确保 frontmatter 含必要字段，去掉不被 WorkBuddy 识别的 invocable。

    入参/返回值均保证**不含 BOM**：调用方读取时用 ``utf-8-sig``，此处再兜底剥离一次，
    避免 Windows 下保存的文件把 BOM 带进 WorkBuddy（后果见 strip_bom_tree 文档字符串）。
    """
    if text.startswith(BOM_CHAR):
        text = text[len(BOM_CHAR):]
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not m:
        return text
    fm = m.group(1)
    body = text[m.end():]
    # 去掉 invocable（WorkBuddy 不识别，且 invocable:false 可能导致技能不可调用）
    fm_lines = [ln for ln in fm.splitlines() if not re.match(r"^\s*invocable\s*:", ln)]
    # 确保有 disable 字段
    if not any(re.match(r"^\s*disable\s*:", ln) for ln in fm_lines):
        fm_lines.append("disable: false")
    new_fm = "\n".join(fm_lines)
    return "---\n" + new_fm + "\n---\n" + body


def install_skill(skill_dir, dest_root, dry_run):
    name = os.path.basename(skill_dir.rstrip("/\\"))
    target = os.path.join(dest_root, name)
    if os.path.exists(target):
        return ("skipped_exists", name)
    if dry_run:
        return ("would_install", name)
    shutil.copytree(skill_dir, target)
    # 剥离 BOM：Windows 编辑器 / Trae 导出常见，会导致 WorkBuddy 无法解析 frontmatter
    strip_bom_tree(target)
    # 规范化 SKILL.md frontmatter
    skill_md = os.path.join(target, "SKILL.md")
    if os.path.exists(skill_md):
        with open(skill_md, "r", encoding="utf-8-sig") as f:
            txt = f.read()
        new = normalize_frontmatter(txt)
        if new != txt:
            with open(skill_md, "w", encoding="utf-8") as f:
                f.write(new)
    return ("installed", name)


def rules_to_skill_files(rules_dir):
    """读取 Trae 规则 .md，返回 [(skill_name, skill_md_text)]。"""
    results = []
    if not os.path.isdir(rules_dir):
        return results
    for fn in sorted(os.listdir(rules_dir)):
        if not fn.endswith(".md"):
            continue
        fp = os.path.join(rules_dir, fn)
        # utf-8-sig：Trae 规则文件常带 BOM，否则首行标签会混入 \ufeff 导致技能名乱码
        with open(fp, "r", encoding="utf-8-sig") as f:
            lines = f.read().splitlines()
        if not lines:
            continue
        first = lines[0].strip()
        # 清洗标签：去掉 Markdown 标题符号 # 与首尾空白
        raw_tags = [t.strip().lstrip("#").strip("*").strip() for t in first.split("|") if t.strip()]
        tags = [t for t in raw_tags if t]
        body = "\n".join(lines[1:]).strip()
        if not body:
            continue
        # 用唯一的时间戳 id 命名，避免中文标签 slug 碰撞导致规则丢失
        fname = re.sub(r"^rule-", "", fn.replace(".md", ""))
        name = f"trae-rule-{fname}"
        tag_txt = ", ".join(tags) if tags else "general"
        desc = (f"Trae global rule for [{tag_txt}]. "
                f"Apply when working with {tag_txt}. " + body[:120].replace("\n", " "))
        md = (
            "---\n"
            f"name: {name}\n"
            f"description: {desc}\n"
            "license: Migrated from Trae user rules (origin unknown)\n"
            "disable: false\n"
            "---\n\n"
            f"# Trae Global Rule: {tag_txt}\n\n"
            f"Source file: `{fn}`\n\n"
            f"{body}\n"
        )
        results.append((name, md, tags))
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="只扫描+审计，不写入")
    ap.add_argument("--apply", action="store_true", help="执行导入")
    ap.add_argument("--include-builtin", action="store_true", help="额外导入内置人格技能")
    args = ap.parse_args()
    if not args.dry_run and not args.apply:
        print("请指定 --dry-run 或 --apply")
        sys.exit(1)
    dry = args.dry_run and not args.apply

    # 1) 收集技能
    skill_sources = []
    for label, root in [("TraeCode全局", TRAEECODE_GLOBAL), ("TraeWork全局", TRAEWORK_GLOBAL)]:
        dirs = find_skill_dirs(root)
        for d in dirs:
            skill_sources.append((label, d))
    if args.include_builtin:
        for label, root in [("TraeCode内置", BUILTIN_TRAECODE), ("TraeWork内置", BUILTIN_TRAEWORK)]:
            dirs = find_skill_dirs(root, recursive=True)
            for d in dirs:
                skill_sources.append((label, d))

    # 去重（同一真实路径只处理一次）
    seen = set()
    unique = []
    for label, d in skill_sources:
        if d in seen:
            continue
        seen.add(d)
        unique.append((label, d))

    # 2) 收集规则
    rule_files = []
    for label, rdir in [("TraeCode规则", TRAEECODE_RULES), ("TraeWork规则", TRAEWORK_RULES)]:
        if os.path.isdir(rdir):
            for fn in sorted(os.listdir(rdir)):
                if fn.endswith(".md"):
                    rule_files.append((label, os.path.join(rdir, fn)))

    print(f"发现技能目录: {len(unique)} 个")
    print(f"发现规则文件: {len(rule_files)} 个")

    # 3) 审计
    clean_skills, risky_skills = [], []
    for label, d in unique:
        hits = audit_skill(d)
        if hits:
            risky_skills.append((label, d, hits))
        else:
            clean_skills.append((label, d))

    print(f"\n[安全审计] 干净技能: {len(clean_skills)} | 风险技能(需复核): {len(risky_skills)}")
    for label, d, hits in risky_skills:
        print(f"  - 风险: {label} / {os.path.basename(d)}")
        for h in hits:
            print(f"      {h['file']}: {h['reason']}")

    # 4) 规则转换
    converted = []
    for label, fp in rule_files:
        for name, md, tags in rules_to_skill_files(os.path.dirname(fp)):
            pass  # rules_to_skill_files 已处理整个目录，这里改用下面统一处理
    # 统一处理规则目录
    all_rule_skills = []
    for label, rdir in [("TraeCode规则", TRAEECODE_RULES), ("TraeWork规则", TRAEWORK_RULES)]:
        all_rule_skills.extend([(label, n, m, t) for (n, m, t) in rules_to_skill_files(rdir)])

    print(f"[规则转换] 可转换为技能: {len(all_rule_skills)} 个")

    # 5) 安装
    if dry:
        print("\n[DRY-RUN] 以下将被安装（审计通过）:")
        for label, d in clean_skills:
            print(f"  技能: {label} / {os.path.basename(d)}")
        for label, name, _, tags in all_rule_skills:
            print(f"  规则→技能: {label} / {name} (tags={tags})")
        print("\n未执行写入。去掉 --dry-run 用 --apply 执行。")
        return

    os.makedirs(DEST, exist_ok=True)
    installed, skipped = [], []
    for label, d in clean_skills:
        status, name = install_skill(d, DEST, dry_run=False)
        (installed if status == "installed" else skipped).append((label, name, status))
    for label, name, md, tags in all_rule_skills:
        target = os.path.join(DEST, name)
        if os.path.exists(target):
            skipped.append((label, name, "skipped_exists"))
            continue
        os.makedirs(target, exist_ok=True)
        with open(os.path.join(target, "SKILL.md"), "w", encoding="utf-8") as f:
            f.write(md)
        installed.append((label, name, "installed"))

    # 6) 报告
    summary = {
        "skills_found": len(unique),
        "skills_clean": len(clean_skills),
        "skills_risky": [{"label": l, "dir": d, "hits": h} for l, d, h in risky_skills],
        "rules_found": len(rule_files),
        "rules_converted": len(all_rule_skills),
        "installed": [n for _, n, _ in installed],
        "skipped": [n for _, n, _ in skipped],
    }
    report_path = os.path.join(os.getcwd(), "trae_import_report.json")
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print(f"\n[完成] 已安装技能: {len(installed)} | 跳过: {len(skipped)}")
    print(f"风险技能未安装(需人工复核): {len(risky_skills)}")
    print(f"报告已写入: {report_path}")
    if skipped:
        print("跳过项:", ", ".join(n for _, n, _ in skipped))


if __name__ == "__main__":
    main()
