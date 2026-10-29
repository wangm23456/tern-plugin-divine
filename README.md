# Tern Divine Plugin (周易神算)

Tern terminal divination panel integrating traditional Chinese & Vedic divination methods:

- **周易六爻 (I Ching Liu Yao)**: Coin-toss hexagram casting and change-line analysis.
- **小六壬神课 (Xiao Liu Ren)**: Quick time/event horary divination.
- **奇门遁甲 (Qi Men Dun Jia)**: Hour-based celestial plate layout.
- **吠陀占星 (Vedic Astrology)**: Planetary positions and D9/D10 timing.
- **AI 解读 (AI Interpretation)**: Optional DeepSeek LLM interpretation for cast results.

## Requirements

- [Tern Terminal](https://stencil.so/tern)
- Optional: `DEEPSEEK_API_KEY` set in your shell environment for AI readings.
- Optional: `horosa-skill` CLI installed for advanced Qi Men / Vedic computations.

## Installation

```bash
mkdir -p ~/.config/tern/plugins
git clone https://github.com/wangm23456/tern-plugin-divine.git ~/.config/tern/plugins/divine
```

Open via Tern command palette: `周易神算`.
