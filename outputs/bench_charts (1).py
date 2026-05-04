import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import seaborn as sns
from matplotlib.gridspec import GridSpec

# ── 1. Load & clean ──────────────────────────────────────────────────────────
dfs = []
for lang in ['ocaml', 'python', 'ruby', 'scheme', 'elixir', 'node']:
    df = pd.read_csv(f'bench_results_{lang}.csv')
    df['Linguagem'] = lang.upper() if lang != 'node' else 'Node.js'
    dfs.append(df)

combined = pd.concat(dfs, ignore_index=True)
combined['Linguagem'] = combined['Linguagem'].replace({'NODE': 'Node.js'})

# Convert TIMEOUT → NaN, coerce to float
combined['Tempo_ms'] = pd.to_numeric(combined['Tempo_ms'], errors='coerce')

# Normalize: time per single iteration (µs)
combined['us_per_iter'] = (combined['Tempo_ms'] / combined['Iteracoes']) * 1000

# Fix negative / obviously wrong memory values
combined['Memoria_KB'] = combined['Memoria_KB'].clip(lower=0)

# ── 2. Aggregates ────────────────────────────────────────────────────────────
LANG_ORDER   = ['OCAML', 'Node.js', 'ELIXIR', 'SCHEME', 'RUBY', 'PYTHON']
ALGO_ORDER   = ['Factorial', 'Mutually Rec (Even)', 'Mutually Rec (Odd)', 'State Machine']
ALGO_LABELS  = ['Factorial', 'Mut. Rec.\n(Even)', 'Mut. Rec.\n(Odd)', 'State\nMachine']
LANG_PALETTE = {
    'OCAML':   '#EF8C2D',
    'Node.js': '#68A063',
    'ELIXIR':  '#7B5EA7',
    'SCHEME':  '#3D7EBF',
    'RUBY':    '#CC342D',
    'PYTHON':  '#306998',
}

# Best (min) time per algorithm × language
best = (
    combined
    .groupby(['Linguagem', 'Algoritmo'])['us_per_iter']
    .min()
    .reset_index()
)
best['Algoritmo_label'] = best['Algoritmo'].map(dict(zip(ALGO_ORDER, ALGO_LABELS)))

# Memory: median across implementations (ignore extreme Scheme/Elixir factorial outliers)
mem = (
    combined
    .groupby(['Linguagem', 'Algoritmo'])['Memoria_KB']
    .median()
    .reset_index()
)

# Speedup relative to Python (best impl)
python_ref = best[best['Linguagem'] == 'PYTHON'].set_index('Algoritmo')['us_per_iter']
speedup = best.copy()
speedup['speedup'] = speedup.apply(
    lambda r: python_ref.get(r['Algoritmo'], np.nan) / r['us_per_iter'], axis=1
)

# Factorial scaling: N=10 vs N=1000, best impl per group
fact = combined[combined['Algoritmo'] == 'Factorial'].copy()
fact_agg = (
    fact.groupby(['Linguagem', 'N'])['us_per_iter']
    .min()
    .reset_index()
)
fact_agg['N_label'] = fact_agg['N'].map({10: 'N = 10', 1000: 'N = 1 000'})

# ── 3. Style ─────────────────────────────────────────────────────────────────
sns.set_theme(style='whitegrid', font_scale=1.05)
plt.rcParams.update({
    'font.family':     'DejaVu Sans',
    'axes.spines.top':    False,
    'axes.spines.right':  False,
    'grid.color':         '#e0e0e0',
    'figure.facecolor':   '#fafafa',
    'axes.facecolor':     '#fafafa',
})

# ── Figure ────────────────────────────────────────────────────────────────────
fig = plt.figure(figsize=(22, 20), facecolor='#fafafa')
fig.suptitle('Benchmark Comparativo de Linguagens\n(menor = melhor)',
             fontsize=20, fontweight='bold', y=0.99, color='#222')

gs = GridSpec(2, 2, figure=fig, hspace=0.45, wspace=0.35)

ax1 = fig.add_subplot(gs[0, 0])  # Time per iteration (all algos)
ax2 = fig.add_subplot(gs[0, 1])  # Speedup heatmap
ax3 = fig.add_subplot(gs[1, 0])  # Factorial scaling
ax4 = fig.add_subplot(gs[1, 1])  # Memory usage

# ─── Plot 1: Tempo normalizado por iteração ───────────────────────────────────
pivoted = (
    best
    .pivot(index='Algoritmo', columns='Linguagem', values='us_per_iter')
    .reindex(ALGO_ORDER)
    [LANG_ORDER]
)

x = np.arange(len(ALGO_ORDER))
n_langs = len(LANG_ORDER)
width = 0.12
offsets = np.linspace(-(n_langs-1)/2, (n_langs-1)/2, n_langs) * width

for i, lang in enumerate(LANG_ORDER):
    vals = pivoted[lang].values
    bars = ax1.bar(x + offsets[i], vals, width=width * 0.9,
                   color=LANG_PALETTE[lang], label=lang, zorder=3,
                   edgecolor='white', linewidth=0.5)
    # Label on top for readable values
    for bar, v in zip(bars, vals):
        if not np.isnan(v):
            ax1.text(bar.get_x() + bar.get_width()/2,
                     bar.get_height() + max(pivoted.max().max()*0.005, 0.01),
                     f'{v:.2f}' if v < 10 else f'{v:.1f}',
                     ha='center', va='bottom', fontsize=6.5, color='#444')

ax1.set_xticks(x)
ax1.set_xticklabels(ALGO_LABELS, fontsize=11)
ax1.set_ylabel('Tempo por iteração (µs)', fontsize=11)
ax1.set_title('Tempo Normalizado por Iteração\n(melhor implementação por linguagem)', fontsize=12, fontweight='bold')
ax1.legend(title='Linguagem', bbox_to_anchor=(1.01, 1), loc='upper left', fontsize=9, title_fontsize=9)
ax1.set_ylim(bottom=0)
ax1.yaxis.set_tick_params(labelsize=10)

# Note about Python TOUTIMEs
ax1.annotate('* Python: alguns cenários resultaram em TIMEOUT (omitidos)',
             xy=(0.01, -0.08), xycoords='axes fraction',
             fontsize=8, color='gray', style='italic')

# ─── Plot 2: Heatmap de speedup relativo ao Python ───────────────────────────
speedup_pivot = (
    speedup
    .pivot(index='Algoritmo', columns='Linguagem', values='speedup')
    .reindex(ALGO_ORDER)
    [LANG_ORDER]
)

mask = speedup_pivot.isna()
cmap = sns.diverging_palette(20, 145, s=80, l=50, as_cmap=True)

sns.heatmap(
    speedup_pivot,
    ax=ax2,
    cmap=cmap,
    annot=True,
    fmt='.1f',
    linewidths=0.5,
    linecolor='white',
    mask=mask,
    center=1,
    vmin=0,
    cbar_kws={'label': 'Speedup vs Python', 'shrink': 0.8},
    annot_kws={'size': 11, 'weight': 'bold'},
)
ax2.set_xticklabels(ax2.get_xticklabels(), rotation=35, ha='right', fontsize=10)
ax2.set_yticklabels(ALGO_LABELS, rotation=0, fontsize=10)
ax2.set_xlabel('')
ax2.set_ylabel('')
ax2.set_title('Speedup Relativo ao Python\n(valores > 1 = mais rápido que Python)', fontsize=12, fontweight='bold')

# Hatch over NaN cells (TIMEOUT)
for (row, col), val in np.ndenumerate(mask.values):
    if val:
        ax2.add_patch(plt.Rectangle((col, row), 1, 1,
                                    fill=True, color='#cccccc', lw=0,
                                    hatch='///', alpha=0.7, zorder=3))
        ax2.text(col + 0.5, row + 0.5, 'TIMEOUT', ha='center', va='center',
                 fontsize=8, color='#555', fontweight='bold')

# ─── Plot 3: Fatorial — escala N=10 vs N=1000 ────────────────────────────────
fact_pivot = fact_agg.pivot(index='Linguagem', columns='N_label', values='us_per_iter').reindex(LANG_ORDER)
n_vals = ['N = 10', 'N = 1 000']
width2 = 0.3
x3 = np.arange(len(LANG_ORDER))

for j, (n_label, hatch) in enumerate(zip(n_vals, ['', '///'])):
    offset = (j - 0.5) * width2
    vals = fact_pivot[n_label].values if n_label in fact_pivot.columns else [np.nan]*len(LANG_ORDER)
    colors = [LANG_PALETTE[l] for l in LANG_ORDER]
    alpha = 1.0 if j == 0 else 0.55
    bars = ax3.bar(x3 + offset, vals, width=width2 * 0.9,
                   color=colors, alpha=alpha, zorder=3,
                   edgecolor='white', linewidth=0.5, hatch=hatch)
    for bar, v in zip(bars, vals):
        if not np.isnan(v) and v > 0:
            ax3.text(bar.get_x() + bar.get_width()/2,
                     bar.get_height() + max(np.nanmax(vals)*0.01, 0.01),
                     f'{v:.1f}',
                     ha='center', va='bottom', fontsize=7.5, color='#444')

ax3.set_xticks(x3)
ax3.set_xticklabels(LANG_ORDER, fontsize=10)
ax3.set_ylabel('Tempo por iteração (µs)', fontsize=11)
ax3.set_title('Fatorial: Escala com Tamanho N\n(melhor implementação)', fontsize=12, fontweight='bold')

patch_n10  = mpatches.Patch(facecolor='gray', alpha=1.0,               label='N = 10')
patch_n1k  = mpatches.Patch(facecolor='gray', alpha=0.55, hatch='///', label='N = 1 000')
ax3.legend(handles=[patch_n10, patch_n1k], fontsize=9, loc='upper left')
ax3.set_yscale('log')
ax3.set_ylabel('Tempo por iteração (µs) — escala log', fontsize=11)
ax3.yaxis.set_tick_params(labelsize=10)

# ─── Plot 4: Memória mediana por algoritmo ────────────────────────────────────
mem_pivot = (
    mem
    .pivot(index='Algoritmo', columns='Linguagem', values='Memoria_KB')
    .reindex(ALGO_ORDER)
    [LANG_ORDER]
)

for i, lang in enumerate(LANG_ORDER):
    vals = mem_pivot[lang].values
    bars = ax4.bar(x + offsets[i], vals, width=width * 0.9,
                   color=LANG_PALETTE[lang], label=lang, zorder=3,
                   edgecolor='white', linewidth=0.5)

ax4.set_xticks(x)
ax4.set_xticklabels(ALGO_LABELS, fontsize=11)
ax4.set_ylabel('Memória mediana (KB) — escala log', fontsize=11)
ax4.set_title('Uso de Memória por Algoritmo\n(mediana das implementações)', fontsize=12, fontweight='bold')
ax4.set_yscale('log')
ax4.yaxis.set_tick_params(labelsize=10)
ax4.legend(title='Linguagem', bbox_to_anchor=(1.01, 1), loc='upper left', fontsize=9, title_fontsize=9)
ax4.annotate('* Scheme/Elixir: picos de memória no Fatorial N=1000 (big-number alloc)',
             xy=(0.01, -0.08), xycoords='axes fraction',
             fontsize=8, color='gray', style='italic')

# ── Save ─────────────────────────────────────────────────────────────────────
plt.savefig('benchmark_comparativo.png',
            dpi=160, bbox_inches='tight', facecolor='#fafafa')
print("Saved!")
