#!/usr/bin/env python3
import json
import os
import re
import sys
import urllib.request


def get_api_key():
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if key:
        return key
    home = os.path.expanduser("~")
    for fname in [".zshenv", ".zshrc", ".bash_profile", ".profile"]:
        path = os.path.join(home, fname)
        if os.path.exists(path):
            try:
                with open(path, encoding="utf-8") as f:
                    for line in f:
                        if "DEEPSEEK_API_KEY" in line and "=" in line:
                            val = line.split("=", 1)[1].strip().strip('"').strip("'")
                            if val:
                                return val
            except Exception:
                pass
    return ""


def detect_lang(text: str) -> str:
    if re.search(r"[\u3040-\u30ff]", text):
        return "日语"
    if re.search(r"[\uac00-\ud7af]", text):
        return "韩语"
    if re.search(r"[\u4e00-\u9fff]", text):
        return "简体中文"
    if re.search(r"[а-яА-Я]", text):
        return "俄语"
    if re.search(r"[a-zA-Z]", text):
        return "英语"
    return ""


def env_lang() -> str:
    val = os.environ.get("LANG", "")
    if not val:
        home = os.path.expanduser("~")
        for fname in (".zshenv", ".zshrc", ".zprofile"):
            try:
                with open(os.path.join(home, fname), encoding="utf-8") as f:
                    for line in f:
                        if line.startswith("export LANG="):
                            val = line.split("=", 1)[1].strip().strip('"').strip("'")
                            break
            except Exception:
                pass
            if val:
                break
    return val


_LANG_NAMES = {"ja": "日语", "ko": "韩语", "zh": "简体中文", "ru": "俄语", "en": "英语"}


def answer_lang(question: str) -> str:
    d = detect_lang(question)
    if d:
        return d
    code = (env_lang() or "").split("_")[0].split(".")[0].lower()
    return _LANG_NAMES.get(code, "简体中文")


SYSTEM_PROMPT = """你是一位懂易经、奇门、六壬和印度占星的解读者，更像一位温和通透的朋友，而不是故弄玄虚的老先生。

说话方式：
- 用现代人日常聊天的语气，亲切自然，像在咖啡馆里跟朋友聊天
- 少用文言句式和生僻术语；提到专业概念时，顺手用一句大白话解释
- 有洞见但不武断，给的是参考和视角，不是判决书
- 关心提问的人：先接住情绪和处境，再谈盘面，最后落到具体的、可执行的小建议
- 语气里有温度，带一点生活智慧和幽默感，但不油腻、不鸡汤
- 每种术数都有它自己的味道：六爻讲时机与变化，小六壬轻快直接，奇门讲格局与方位，吠陀讲周期与内在成长——解读时体现出来

输出规则（必须遵守）：
- 你的回复会原样显示在占卜面板上，是一段独白文字，不是聊天消息
- 全程直接对求测的人本人说话，用「你」称呼；禁止出现「你朋友」「他」「求测者」这类转述口吻
- 卦名和盘面数据是既定事实，直接解读，禁止反问、质疑、确认（不要出现「你说的应该是」「是不是摇出了」这类句式）
- 不要出现问候语、开场白和「希望对你有帮助」之类的收尾
- 用「{LANG}」书写整段回复：正文与建议全部用该语言；段首【】标题按该语言意译（此条优先于用户消息里出现的中文标题示例）"""


def main():
    api_key = get_api_key()
    if not api_key:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "未检测到 DEEPSEEK_API_KEY 环境变量，请在 ~/.zshenv 中配置",
                }
            )
        )
        return

    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        data = {}

    mode = data.get("mode", "iching")
    q = str(data.get("question", "") or "").strip()
    system = SYSTEM_PROMPT.replace("{LANG}", answer_lang(q))
    qlead = f"所问之事：「{q}」。解读必须贴着这件事说，不要泛泛而谈。" if q else ""
    if mode == "iching":
        p = data.get("primary", "乾为天")
        c = data.get("changed", "")
        ch_str = f"{'，摇出了变卦「' + c + '，事情正在起变化' if c else '，六爻安静没有变卦'}"
        prompt = (
            f"{qlead}有人刚用三枚铜钱摇了一卦，本卦「{p}」{ch_str}。请你直接对这位摇卦的人说话："
            f"这一卦在说 TA 当下的处境大概什么样（先共情），再给两条具体、接地气的建议。"
            f"150字以内，分两段，段首用【这一卦在说】【可以试试】。"
        )
    elif mode == "xiaoliuren":
        stages = " → ".join(data.get("stages", ["速喜", "留连", "大安"]))
        prompt = (
            f"{qlead}有人起了个小六壬课，三传：{stages}。直接对起课的人说话，用轻快的聊天语气讲讲："
            f"这件事开头、过程、结尾各是什么节奏，哪里要留心，什么时候适合发力。"
            f"150字以内，分两段，段首用【这一课的节奏】【给你的建议】。"
        )
    elif mode == "qimen":
        ju = data.get("ju", "时家奇门")
        zf = data.get("zhifu", "天内")
        zs = data.get("zhishi", "死门")
        jg = data.get("jige", "平稳")
        xg = data.get("xiongge", "无")
        prompt = (
            f"{qlead}有人起了一张奇门盘：{ju}，值符「{zf}」，值使「{zs}」，吉格「{jg}」，凶格「{xg}」。"
            f"直接对起盘的人说话，用大白话讲清：局面顺不顺、卡点在哪、突破口在哪，"
            f"再给两条能落地的小策略（该主动还是观望、找什么人帮忙）。"
            f"150字以内，分两段，段首用【现在的局面】【怎么走比较好】。"
        )
    elif mode == "tarot":
        spread = data.get("spread", "three")
        cards = "、".join(data.get("cards", [])) or "（未抽牌）"
        prompt = (
            f"{qlead}有人抽了塔罗牌（{spread} 牌阵），抽到：{cards}。直接对抽牌的人说话："
            f"整体牌阵在说当下的处境与走向（先共情），再给两条具体建议。"
            f"150字以内，分两段，段首用【牌阵在说】【可以试试】。"
        )
    elif mode in ("vedic", "india_chart"):
        lord = data.get("lord", "火星")
        dasha = data.get("dasha", "金星")
        nak = data.get("nakshatra", "月宿")
        birth = data.get("birth_text", "")
        if birth:
            prompt = (
                f"{qlead}这个人出生于 {birth}，吠陀本命盘：命主星{lord}，月宿{nak}，当前走{dasha}大运。"
                f"直接对本人说话：聊聊这个大运阶段的主题（是扩张期、还债期还是打基础期），"
                f"天性和当下课题各点一句，日常做点什么更顺。150字以内，分两段，段首用【这个阶段的你】【日常小建议】。"
            )
        else:
            prompt = (
                f"{qlead}有人用当下时刻起了一张吠陀即时盘（不是本命盘，没有出生信息）：命主星{lord}，月宿{nak}。"
                f"直接对起盘的人说话：只谈此刻的时机和氛围——现在适合推进、观望还是沟通，"
                f"不要谈性格和命运。150字以内，分两段，段首用【此刻的星象】【眼下适合做】。"
            )
    else:
        prompt = "用温和现代的语气，给一段关于当下运势的短小解读。100字以内。"

    url = "https://api.deepseek.com/chat/completions"
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}
    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": 350,
        "temperature": 0.75,
    }

    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"), headers=headers
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            answer = res["choices"][0]["message"]["content"]
            print(json.dumps({"ok": True, "answer": answer}, ensure_ascii=False))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
