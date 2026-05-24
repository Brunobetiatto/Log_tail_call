"""
Gerador de graficos de crescimento.

Para cada algoritmo, gera um grafico mostrando como o numero de ciclos de
CPU (Y) cresce com o numero de iteracoes (X), uma linha por (linguagem x
implementacao). Cada ponto = media de N runs (barras de erro = desvio padrao).

- Eixo X (iteracoes): log
- Eixo Y (ciclos de CPU): log
- Eixo Y secundario (direita): tempo em ns, usando a mediana da Freq_GHz medida
- Legenda lateral compacta: bloco \"Linguagem\" (cor) + bloco \"Implementacao\" (estilo)

Fatorial: dois arquivos separados (N=10 e N=1000) ja que as escalas diferem
3+ ordens de grandeza.

Saida:
    outputs/growth_Factorial_N10.png
    outputs/growth_Factorial_N1000.png
    outputs/growth_Mutually_Rec_Even.png
    outputs/growth_Mutually_Rec_Odd.png
    outputs/growth_State_Machine.png
    outputs/growth_all_algorithms.png  (montagem 3x2)
"""

import os
import sys
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.lines as mlines
import seaborn as sns
from pathlib import Path

# ----------------------------------------------------------------------------
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent if HERE.name == "outputs" else HERE
OUT_DIR = ROOT / "outputs"
OUT_DIR.mkdir(exist_ok=True)

LANGS = ['ocaml', 'python', 'ruby', 'scheme', 'elixir', 'node']

LANG_DISPLAY = {
    'ocaml':  'OCaml',
    'python': 'Python',
    'ruby':   'Ruby',
    'scheme': 'Scheme',
    'elixir': 'Elixir',
    'node':   'Node.js',
}

LANG_PALETTE = {
    'OCaml':   '#EF8C2D',
    'Node.js': '#68A063',
    'Elixir':  '#7B5EA7',
    'Scheme':  '#3D7EBF',
    'Ruby':    '#CC342D',
    'Python':  '#306998',
}

# Estilo por categoria de implementacao
IMPL_STYLE = {
    'normal': {'linestyle': '-',  'marker': 'o'},  # Recursiva direta
    'tail':   {'linestyle': ':',  'marker': '^'},  # Tail-call (TCO ou tail-acc)
    'loop':   {'linestyle': '--', 'marker': 's'},  # Loop explicito
}
IMPL_LABEL = {
    'normal': 'Normal (recursiva)',
    'tail':   'Tail-call',
    'loop':   'Loop',
}

def impl_category(impl_name: str) -> str:
    s = str(impl_name).lower()
    if 'normal' in s:
        return 'normal'
    if 'tail' in s or 'tco' in s:
        # Loop/Tail (do Node) e' loop explicito, nao TCO
        if 'loop' in s:
            return 'loop'
        return 'tail'
    return 'loop'

ALGO_TITLES = {
    'Factorial':            'Fatorial',
    'Mutually Rec (Even)':  'Recursao Mutua (Even)',
    'Mutually Rec (Odd)':   'Recursao Mutua (Odd)',
    'State Machine':        'Maquina de Estados',
}

# ----------------------------------------------------------------------------
def load_all() -> pd.DataFrame:
    frames = []
    for lang in LANGS:
        path = ROOT / f"bench_results_{lang}.csv"
        if not path.exists():
            print(f"[aviso] arquivo nao encontrado: {path}")
            continue
        try:
            df = pd.read_csv(path)
        except Exception as e:
            print(f"[erro] falha ao ler {path}: {e}")
            continue
        df['Linguagem'] = LANG_DISPLAY[lang]
        frames.append(df)

    if not frames:
        print("[fatal] nenhum CSV encontrado. Rode os benchmarks primeiro.")
        sys.exit(1)

    combined = pd.concat(frames, ignore_index=True)
    if 'Run' not in combined.columns:
        combined['Run'] = 1
    if 'Freq_GHz' not in combined.columns:
        combined['Freq_GHz'] = np.nan

    combined['Ciclos_CPU']      = pd.to_numeric(combined['Ciclos_CPU'], errors='coerce')
    combined['Ciclos_por_iter'] = pd.to_numeric(combined['Ciclos_por_iter'], errors='coerce')
    combined['Freq_GHz']        = pd.to_numeric(combined['Freq_GHz'], errors='coerce')
    combined['Iteracoes']       = pd.to_numeric(combined['Iteracoes'], errors='coerce')
    combined['Memoria_KB']      = pd.to_numeric(combined['Memoria_KB'], errors='coerce').clip(lower=0)

    valid = combined.dropna(subset=['Ciclos_CPU', 'Iteracoes']).copy()
    return valid

# ----------------------------------------------------------------------------
def aggregate(df: pd.DataFrame, algo: str, n_filter=None) -> pd.DataFrame:
    subset = df[df['Algoritmo'] == algo].copy()
    if n_filter is not None:
        subset = subset[subset['N'] == n_filter]
    if subset.empty:
        return subset
    grouped = (
        subset
        .groupby(['Linguagem', 'Implementacao', 'N', 'Iteracoes'], as_index=False)
        .agg(
            ciclos_mean=('Ciclos_CPU', 'mean'),
            ciclos_std =('Ciclos_CPU', 'std'),
            n_runs     =('Ciclos_CPU', 'count'),
        )
    )
    grouped['ciclos_std'] = grouped['ciclos_std'].fillna(0.0)
    return grouped

# ----------------------------------------------------------------------------
def add_ns_secondary_axis(ax, freq_ghz: float):
    """Eixo Y secundario (direita) em nanosegundos."""
    ns_per_cycle = 1.0 / freq_ghz
    sec = ax.secondary_yaxis('right',
                              functions=(lambda c: c * ns_per_cycle,
                                         lambda t: t / ns_per_cycle))
    sec.set_ylabel(f'Tempo (ns)  -  1 ciclo = {ns_per_cycle:.3f} ns @ {freq_ghz:.3f} GHz',
                   fontsize=10, color='#444')
    sec.tick_params(labelsize=9, colors='#444')
    return sec

def build_compact_legends(ax, langs_used, impls_used, bbox=(1.18, 1.0), fontsize=8.5):
    """Duas legendas laterais lado a lado: Linguagem (cor) + Implementacao (estilo)."""
    lang_handles = [
        mlines.Line2D([], [], color=LANG_PALETTE[l], linewidth=2.5, marker='o',
                      markersize=5, label=l)
        for l in langs_used
    ]
    impl_handles = [
        mlines.Line2D([], [], color='#444',
                      linestyle=IMPL_STYLE[c]['linestyle'],
                      marker=IMPL_STYLE[c]['marker'],
                      linewidth=2.0, markersize=5,
                      label=IMPL_LABEL[c])
        for c in impls_used
    ]
    leg1 = ax.legend(handles=lang_handles, title='Linguagem',
                     loc='upper left', bbox_to_anchor=bbox,
                     fontsize=fontsize, title_fontsize=fontsize + 0.5,
                     frameon=True, framealpha=0.92)
    ax.add_artist(leg1)
    ax.legend(handles=impl_handles, title='Implementacao',
              loc='upper left', bbox_to_anchor=(bbox[0], bbox[1] - 0.45),
              fontsize=fontsize, title_fontsize=fontsize + 0.5,
              frameon=True, framealpha=0.92)

def plot_algorithm(ax, algo_df: pd.DataFrame, algo_name: str,
                   freq_ghz: float, runs_per_point: int,
                   show_legend: bool = True, legend_bbox=(1.18, 1.0)):
    title = ALGO_TITLES.get(algo_name, algo_name)
    if algo_df.empty:
        ax.text(0.5, 0.5, f'Sem dados para {algo_name}',
                ha='center', va='center', transform=ax.transAxes,
                fontsize=12, color='gray')
        ax.set_title(title, fontsize=13, fontweight='bold')
        return

    langs_used = []
    impls_used = []

    for lang in LANG_PALETTE.keys():
        for impl in sorted(algo_df['Implementacao'].unique()):
            sub = algo_df[
                (algo_df['Linguagem'] == lang) &
                (algo_df['Implementacao'] == impl)
            ].sort_values('Iteracoes')
            if sub.empty:
                continue
            cat = impl_category(impl)
            style = IMPL_STYLE[cat]
            color = LANG_PALETTE[lang]

            x = sub['Iteracoes'].values
            y = sub['ciclos_mean'].values
            yerr = sub['ciclos_std'].values

            ax.errorbar(x, y, yerr=yerr,
                        color=color, ecolor=color,
                        linewidth=1.8, markersize=5.5, capsize=3,
                        elinewidth=0.8, alpha=0.92,
                        linestyle=style['linestyle'],
                        marker=style['marker'],
                        zorder=3)

            if lang not in langs_used:
                langs_used.append(lang)
            if cat not in impls_used:
                impls_used.append(cat)

    ax.set_xscale('log')
    ax.set_yscale('log')
    ax.set_xlabel('Numero de iteracoes', fontsize=11)
    ax.set_ylabel('Ciclos de CPU (media de runs)', fontsize=11)
    ax.set_title(title, fontsize=13, fontweight='bold')
    ax.grid(True, which='both', alpha=0.3, zorder=1)

    if freq_ghz and freq_ghz > 0:
        add_ns_secondary_axis(ax, freq_ghz)

    if show_legend and langs_used:
        # Ordena impls por convencao normal -> tail -> loop
        order = {'normal': 0, 'tail': 1, 'loop': 2}
        impls_used = sorted(set(impls_used), key=lambda c: order[c])
        build_compact_legends(ax, langs_used, impls_used, bbox=legend_bbox)

# ----------------------------------------------------------------------------
def save_single_chart(df, algo, freq_ghz, runs_per_point, out_name, n_filter=None,
                       suptitle_extra=""):
    agg = aggregate(df, algo, n_filter=n_filter)
    fig, ax = plt.subplots(figsize=(12, 7), facecolor='#fafafa')
    plot_algorithm(ax, agg, algo, freq_ghz, runs_per_point, show_legend=True)

    sup = f'Crescimento: ciclos de CPU vs iteracoes - {ALGO_TITLES[algo]}'
    if suptitle_extra:
        sup += f'  {suptitle_extra}'
    fig.suptitle(sup, fontsize=14, fontweight='bold', y=1.0)
    fig.text(0.01, 0.01,
             f'Cada ponto: media de {runs_per_point} runs (barras = std). '
             f'Eixos log. Seed=42. Config em bench_config.json.',
             fontsize=8, color='#666', style='italic')
    plt.tight_layout(rect=[0, 0.03, 0.82, 0.97])
    out_path = OUT_DIR / out_name
    plt.savefig(out_path, dpi=160, bbox_inches='tight', facecolor='#fafafa')
    plt.close(fig)
    print(f"  salvo: {out_path}")

def main():
    sns.set_theme(style='whitegrid', font_scale=1.0)
    plt.rcParams.update({
        'font.family':        'DejaVu Sans',
        'axes.spines.top':    False,
        'axes.spines.right':  False,
        'figure.facecolor':   '#fafafa',
        'axes.facecolor':     '#fafafa',
    })

    df = load_all()
    if df.empty:
        print("[fatal] dataframe vazio apos limpeza")
        return

    freq_series = df['Freq_GHz'].dropna()
    freq_series = freq_series[freq_series > 0.1]
    freq_ghz = float(freq_series.median()) if not freq_series.empty else 2.0
    print(f"Freq mediana detectada: {freq_ghz:.4f} GHz  ->  1 ciclo = {1/freq_ghz:.3f} ns")

    runs_per_point = int(
        df.groupby(['Algoritmo', 'Implementacao', 'N', 'Iteracoes', 'Linguagem'])['Run']
          .nunique().median()
    ) or 10
    print(f"Runs por ponto (mediana): {runs_per_point}")

    # ---------- Figuras individuais ----------
    # Factorial: 2 arquivos separados (N=10 e N=1000)
    save_single_chart(df, 'Factorial', freq_ghz, runs_per_point,
                      'growth_Factorial_N10.png', n_filter=10,
                      suptitle_extra='(N=10)')
    save_single_chart(df, 'Factorial', freq_ghz, runs_per_point,
                      'growth_Factorial_N1000.png', n_filter=1000,
                      suptitle_extra='(N=1000, bignum)')

    # Demais algoritmos: 1 arquivo cada
    for algo, out_name in [
        ('Mutually Rec (Even)', 'growth_Mutually_Rec_Even.png'),
        ('Mutually Rec (Odd)',  'growth_Mutually_Rec_Odd.png'),
        ('State Machine',       'growth_State_Machine.png'),
    ]:
        save_single_chart(df, algo, freq_ghz, runs_per_point, out_name)

    # ---------- Figura combinada (3 linhas x 2 colunas) ----------
    fig, axes = plt.subplots(3, 2, figsize=(22, 18), facecolor='#fafafa')
    panels = [
        ('Factorial',           10,   axes[0, 0]),
        ('Factorial',           1000, axes[0, 1]),
        ('Mutually Rec (Even)', None, axes[1, 0]),
        ('Mutually Rec (Odd)',  None, axes[1, 1]),
        ('State Machine',       None, axes[2, 0]),
    ]
    for algo, n_filter, ax in panels:
        agg = aggregate(df, algo, n_filter=n_filter)
        plot_algorithm(ax, agg, algo, freq_ghz, runs_per_point,
                       show_legend=False)
        if n_filter is not None:
            ax.set_title(f'{ALGO_TITLES[algo]} (N={n_filter})',
                         fontsize=13, fontweight='bold')

    # Painel vazio (axes[2,1]) vira a legenda combinada
    leg_ax = axes[2, 1]
    leg_ax.axis('off')
    all_langs = list(LANG_PALETTE.keys())
    all_impls = ['normal', 'tail', 'loop']
    lang_handles = [
        mlines.Line2D([], [], color=LANG_PALETTE[l], linewidth=3, marker='o',
                      markersize=7, label=l)
        for l in all_langs
    ]
    impl_handles = [
        mlines.Line2D([], [], color='#444',
                      linestyle=IMPL_STYLE[c]['linestyle'],
                      marker=IMPL_STYLE[c]['marker'],
                      linewidth=2.5, markersize=7,
                      label=IMPL_LABEL[c])
        for c in all_impls
    ]
    l1 = leg_ax.legend(handles=lang_handles, title='Linguagem (cor)',
                       loc='upper left', bbox_to_anchor=(0.05, 0.95),
                       fontsize=12, title_fontsize=13, frameon=True)
    leg_ax.add_artist(l1)
    leg_ax.legend(handles=impl_handles, title='Implementacao (estilo)',
                  loc='upper left', bbox_to_anchor=(0.55, 0.95),
                  fontsize=12, title_fontsize=13, frameon=True)

    fig.suptitle('Crescimento: ciclos de CPU vs iteracoes (todos os algoritmos)',
                 fontsize=18, fontweight='bold', y=0.995)
    fig.text(0.5, 0.005,
             f'Cada ponto: media de {runs_per_point} runs. Barras = std em Y. '
             f'Eixos log. Seed=42. Freq CPU mediana = {freq_ghz:.3f} GHz '
             f'(1 ciclo = {1/freq_ghz:.3f} ns).',
             ha='center', fontsize=10, color='#555', style='italic')
    plt.tight_layout(rect=[0, 0.015, 1, 0.985])
    combo_path = OUT_DIR / "growth_all_algorithms.png"
    plt.savefig(combo_path, dpi=160, bbox_inches='tight', facecolor='#fafafa')
    plt.close(fig)
    print(f"  salvo: {combo_path}")
    print("\nPronto.")

if __name__ == '__main__':
    main()
