#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import sys


def parse_xiaoliuren(raw_data):
    try:
        xl = raw_data.get("xiaoliuren", {})
        analysis = xl.get("analysis", {})
        stages = analysis.get("stages", [])
        scores = {
            "大安": 0.95,
            "留连": 0.35,
            "速喜": 0.85,
            "赤口": 0.20,
            "小吉": 0.75,
            "空亡": 0.10,
        }
        tones = {
            "大安": "success",
            "留连": "warning",
            "速喜": "accent",
            "赤口": "error",
            "小吉": "info",
            "空亡": "error",
        }
        roles = {1: "初传", 2: "二传", 3: "三传"}
        out_stages = []
        deities_detail = []
        for s in stages:
            name = s.get("name", "")
            info = s.get("info", {})
            pos = s.get("pos", 1)
            raw_yi = [
                line.strip() for line in s.get("yi", "").split("\n") if line.strip()
            ]
            desc = raw_yi[1] if len(raw_yi) > 1 else raw_yi[0] if raw_yi else ""
            remedy = (
                raw_yi[-1]
                if len(raw_yi) > 2 and "拜" in raw_yi[-1]
                else f"可礼敬{info.get('deity', '正神')}"
            )

            fw = info.get("fangwei", "").replace("正", "")
            out_stages.append(
                {
                    "pos": roles.get(pos, f"第{pos}传"),
                    "name": name,
                    "tone": tones.get(name, "accent"),
                    "wuxing": f"{info.get('wuxing', '')}·{fw}",
                    "score": scores.get(name, 0.5),
                }
            )
            deities_detail.append(
                {
                    "title": f"{roles.get(pos, '')} · {name} ({info.get('wuxing', '')}·{fw})",
                    "meaning": desc,
                    "remedy": remedy,
                }
            )

        verdict = "气运平稳，静待良机。"
        if len(out_stages) >= 3:
            s3 = out_stages[2]["name"]
            if s3 == "大安":
                verdict = "终局大安：稳中求胜，增长虽缓但大吉圆满。"
            elif s3 == "速喜":
                verdict = "终局速喜：意料之喜，贵人相助，速战速决。"
            elif s3 == "小吉":
                verdict = "终局小吉：吉神照临，各得其所，诸谋顺遂。"
            elif s3 == "留连":
                verdict = "终局留连：反复纠缠，易有停滞，宜缓不宜急。"
            elif s3 == "赤口":
                verdict = "终局赤口：谨防口舌争执破耗，谨言慎行转危为安。"
            elif s3 == "空亡":
                verdict = "终局空亡：虚耗无功，事宜退守静候吉时。"

        return {
            "stages": out_stages,
            "verdict": verdict,
            "deities": deities_detail,
        }
    except Exception:
        return {}


def parse_qimen(raw_data):
    try:
        text = raw_data.get("snapshot_text", "")
        pan = raw_data.get("pan", {})
        sections = {
            s["title"]: s["body"]
            for s in raw_data.get("export_snapshot", {}).get("sections", [])
        }

        tian = pan.get("tianPanList", [])
        ren = pan.get("renPanList", [])
        shen = pan.get("shenPanList", [])
        di = pan.get("diPanList", [])
        palace_names = [
            "坎一",
            "坤二",
            "震三",
            "巽四",
            "中五",
            "乾六",
            "兑七",
            "艮八",
            "离九",
        ]
        stars = ["蓬", "芮", "冲", "辅", "禽", "心", "柱", "任", "英"]
        door_scores = {
            "生": 0.95,
            "开": 0.90,
            "休": 0.85,
            "景": 0.60,
            "杜": 0.45,
            "惊": 0.30,
            "伤": 0.25,
            "死": 0.10,
        }

        zhifu = pan.get("zhiFu", "天内")
        zhishi = pan.get("zhiShi", "死门")

        palaces = []
        for i in range(9):
            door = ren[i] if i < len(ren) else ""
            god = shen[i] if i < len(shen) else ""
            t_stem = tian[i] if i < len(tian) else ""
            d_stem = di[i] if i < len(di) else ""
            star = stars[i] if i < len(stars) else ""
            score = door_scores.get(door, 0.5)

            door_full = (door + "门") if door else "中五"
            status = "平"
            if door in ["生", "开", "休"]:
                status = "吉门"
            elif door in ["死", "惊", "伤"]:
                status = "凶门"

            if door_full == zhishi:
                status = "★值使"
            if star in zhifu:
                status = "★值符"

            godstar = f"{god}·{star}" if god else star

            palaces.append(
                {
                    "palace": palace_names[i],
                    "door": door_full,
                    "godstar": godstar,
                    "stems": f"{t_stem}/{d_stem}",
                    "status": status,
                    "score": score,
                }
            )

        m_ji = re.search(r"吉格.*?：([^\n]+)", text)
        m_xiong = re.search(r"凶格.*?：([^\n]+)", text)

        def clean_sec(raw_sec):
            lines = [
                row.strip()
                for row in raw_sec.split("\n")
                if row.strip() and not row.startswith("|")
            ]
            return " · ".join(lines[:2])

        career_txt = clean_sec(sections.get("事业七要", ""))
        wealth_txt = clean_sec(sections.get("财富七要", ""))
        love_txt = clean_sec(sections.get("恋爱姻缘", ""))

        remedy_lines = [
            row.strip()
            for row in sections.get("化解方案", "").split("\n")
            if "灭象" in row
        ]
        remedy_summary = (
            remedy_lines[0].split("|")[-2].strip()
            if remedy_lines
            else "若临击刑白虎方位，宜移出尖锐金属，适度摆放常青绿植以舒缓气场。"
        )

        return {
            "ju": pan.get("juText", "时家奇门"),
            "zhifu": zhifu,
            "zhishi": zhishi,
            "jieqi": pan.get("jieqiText", ""),
            "jige": m_ji.group(1).strip() if m_ji else "格局平稳",
            "xiongge": m_xiong.group(1).strip() if m_xiong else "无明显凶煞",
            "palaces": palaces,
            "career": career_txt
            if career_txt
            else "开门见生，谋事顺遂，利见贵人大人。",
            "wealth": wealth_txt
            if wealth_txt
            else "生门得位，本钱安稳，求财循序渐进。",
            "love": love_txt if love_txt else "干合与六合相生，情缘和顺，相知相守。",
            "remedy": remedy_summary,
        }
    except Exception:
        return {}


def parse_india(raw_data):
    try:
        text = raw_data.get("snapshot_text", "")
        sections = {
            s["title"]: s["body"]
            for s in raw_data.get("export_snapshot", {}).get("sections", [])
        }
        planets = []
        in_p = False

        m_lord = re.search(r"命主星：([^\n]+)", text)
        m_md = re.search(r"当前大运.*?：([^\n]+)", text)
        m_ad = re.search(r"当前小运.*?：([^\n]+)", text)
        m_nak = re.search(r"月宿：([^\n]+)", text)

        for line in text.split("\n"):
            if "| 星曜 | 落座 | 落宫 |" in line:
                in_p = True
                continue
            if in_p:
                if line.startswith("| ---"):
                    continue
                if line.startswith("|"):
                    parts = [p.strip() for p in line.split("|")[1:-1]]
                    if len(parts) >= 3 and parts[0]:
                        name = parts[0].split("(")[0].strip()
                        raw_sign = parts[1].split("；")[0].strip()
                        # Shorten sign like 9˚天秤27分 -> 天秤9°
                        deg_match = re.search(r"(\d+)˚([^\d分]+)", raw_sign)
                        sign_short = (
                            f"{deg_match.group(2)}{deg_match.group(1)}°"
                            if deg_match
                            else raw_sign
                        )
                        house = parts[2].replace("第", "").replace("宫", "") + "宫"
                        is_retro = "逆行" in parts[1] or (
                            len(parts) > 5 and "逆行" in parts[5]
                        )
                        score = 0.45 if is_retro else 0.85
                        if "木" in name or "金" in name:
                            score = min(0.95, score + 0.1)
                        planets.append(
                            {
                                "name": name,
                                "sign": sign_short,
                                "house": house,
                                "status": "逆行" if is_retro else "顺行",
                                "score": score,
                            }
                        )
                elif line.startswith("["):
                    in_p = False

        yogas_raw = sections.get("瑜伽格局 Yogas", "")
        yogas = []
        for line in yogas_raw.split("\n"):
            if (
                line.startswith("|")
                and not line.startswith("| 瑜伽")
                and not line.startswith("| ---")
            ):
                pts = [p.strip() for p in line.split("|")[1:-1]]
                if len(pts) >= 4:
                    yogas.append(
                        {
                            "name": pts[0].split("（")[0].strip(),
                            "strength": pts[2],
                            "stars": pts[4] if len(pts) > 4 else "",
                        }
                    )

        lord_clean = m_lord.group(1).strip() if m_lord else "火星"
        lord_short = lord_clean.split("（")[0].strip()

        return {
            "lord": lord_short,
            "mahadasha": m_md.group(1).strip() if m_md else "金星",
            "antardasha": m_ad.group(1).strip() if m_ad else "土星",
            "nakshatra": m_nak.group(1).strip() if m_nak else "胃宿",
            "planets": planets[:9],
            "yogas": yogas[:3],
            "remedy": "尊奉伊什塔主神，配戴木星黄玉或金星白玉，念诵护持明咒提振能量。",
        }
    except Exception:
        return {}


def parse_tarot(raw_data):
    try:
        text = raw_data.get("snapshot_text", "")
        cards = []
        in_tbl = False
        for line in text.split("\n"):
            if line.startswith("| 位置") and "位义" in line:
                in_tbl = True
                continue
            if in_tbl:
                if line.startswith("| ---"):
                    continue
                if line.startswith("|"):
                    pts = [p.strip() for p in line.split("|")[1:-1]]
                    if len(pts) >= 6 and pts[0].startswith("位置"):
                        cards.append(
                            {
                                "pos": pts[0].split("(")[0].strip(),
                                "role": pts[1],
                                "card": pts[2],
                                "upright": pts[3] == "正位",
                                "keywords": pts[5],
                            }
                        )
                else:
                    in_tbl = False
        verdict = ""
        vi = text.find("[综合断语]")
        if vi != -1:
            verdict = " ".join(
                x.strip() for x in text[vi:].split("\n")[1:5] if x.strip()
            )
        return {
            "spread": raw_data.get("spread", "three"),
            "cards": cards,
            "verdict": verdict[:260],
        }
    except Exception:
        return {}


def main():
    tool = sys.argv[1] if len(sys.argv) > 1 else "xiaoliuren"
    try:
        raw = sys.stdin.read()
        input_data = json.loads(raw) if raw.strip() else {}
    except Exception:
        input_data = {}

    home = os.path.expanduser("~")
    uv_path = shutil.which("uv") or os.path.join(home, ".local", "bin", "uv")
    if not os.path.exists(uv_path):
        uv_path = None

    git_spec = "git+https://github.com/Horace-Maxwell/horosa-skill.git#subdirectory=horosa-skill"
    skill_dir = os.environ.get("HOROSA_SKILL_DIR", "")
    if not skill_dir or not os.path.isdir(skill_dir):
        candidates = [
            os.path.join(home, ".local", "share", "horosa-skill"),
            os.path.join(home, "horosa-skill"),
        ]
        skill_dir = next((p for p in candidates if os.path.isdir(p)), "")

    # 1. 本地目录存在
    if skill_dir and uv_path:
        cmd = [uv_path, "--directory", skill_dir, "run", "horosa-skill", "tool", "run", tool, "--stdin"]
    # 2. 系统中已有 horosa-skill 命令
    elif shutil.which("horosa-skill"):
        cmd = ["horosa-skill", "tool", "run", tool, "--stdin"]
    # 3. 拥有 uv，直接通过 Git URL 自动下载、安装并执行（零配置）
    elif uv_path:
        cmd = [uv_path, "tool", "run", "--from", git_spec, "horosa-skill", "tool", "run", tool, "--stdin"]
    else:
        print(json.dumps({
            "ok": False,
            "error": "未检测到 horosa-skill 或 uv。建议安装 uv (curl -LsSf https://astral.sh/uv/install.sh | sh) 即可自动联网运行"
        }, ensure_ascii=False))
        return
    try:
        res = subprocess.run(
            cmd, input=json.dumps(input_data), capture_output=True, text=True
        )
        if res.returncode == 0:
            env = json.loads(res.stdout)
            raw_data = env.get("data", {})
            result = {
                "ok": True,
                "tool": tool,
            }
            if tool == "xiaoliuren":
                result["xiaoliuren"] = parse_xiaoliuren(raw_data)
            elif tool == "qimen":
                result["qimen"] = parse_qimen(raw_data)
            elif tool in ("vedic", "india_chart"):
                result["vedic"] = parse_india(raw_data)
                result["india_chart"] = result["vedic"]
            elif tool == "tarot":
                result["tarot"] = parse_tarot(raw_data)
            print(json.dumps(result, ensure_ascii=False))
        else:
            print(json.dumps({"ok": False, "error": res.stderr}))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))


if __name__ == "__main__":
    main()
