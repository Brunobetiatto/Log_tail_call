"""
Gerador de graficos de crescimento — subplots por implementacao.

Cada imagem tem 3 subplots lado a lado (Normal | Tail-call | Loop).
Eixo Y compartilhado entre os 3 subplots.
Python excluido dos graficos.
"""

import sys
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.lines as mlines
import seaborn as sns
from pathlib import Path

HERE    = Path(__file__).resolve().parent
ROOT    = HERE.parent
OUT_DIR = ROOT / "outputs"
OUT_DIR.mkdir(exist_ok=True)

LANGS = ['ocaml', 'ruby', 'scheme', 'elixir', 'node']

LANG_DISPLAY = {
    'ocaml':  'OCaml',
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
}

IMPL_CATEGORIES = ['normal', 'tail', 'loop']

IMPL_TITLES = {
    'normal': 'Normal (recursiva)',
    'tail':   'Tail-call',
    'loop':   'Loop',
}

IMPL_STYLE = {
    'normal': {'linestyle': '-',  'marker': 'o'},
    'tail':   {'linestyle': ':',  'marker': '^'},
    'loop':   {'linestyle': '--', 'marker': 's'},
}

ALGO_TITLES = {
    'Factorial':            'Fatorial',
    'Mutually Rec (Even)':  'Recursao Mutua (Even)',
    'Mutually Rec (Odd)':   'Recursao Mutua (Odd)',
    'State Machine':        'Maquina de Estados',
}

def impl_category(impl_name: str) -> str:
    s = str(impl_name).lower()
    if 'normal' in s:
        return 'normal'
    if 'tail' in s or 'tco' in s:
        if 'loop' in s:
            return 'loop'
        return 'tail'
    return 'loop'

# ── Load ─────────────────────────────────────────────────────────────────────
def load_all() -> pd.DataFrame:
    frames = []
    for lang in LANGS:
        path = ROOT / 'bench_results' / f'bench_results_{lang}.csv'
        if not path.exists():
            print(f"[aviso] nao encontrado: {path}")
            continue
        try:
            df = pd.read_csv(path)
        except Exception as e:
            print(f"[erro] {path}: {e}")
            continue
        df['Linguagem'] = LANG_DISPLAY[lang]
        frames.append(df)

    if not frames:
        print("[fatal] nenhum CSV encontrado.")
        sys.exit(1)

    combined = pd.concat(frames, ignore_index=True)
    if 'Run' not in combined.columns:
        combined['Run'] = 1
    if 'Freq_GHz' not in combined.columns:
        combined['Freq_GHz'] = np.nan

    # Compatibilidade: CSVs novos (Ciclos_CPU) e antigos (Tempo_ms)
    if 'Ciclos_CPU' not in combined.columns and 'Tempo_ms' in combined.columns:
        freq_est = 2.0
        combined['Ciclos_CPU']      = pd.to_numeric(combined['Tempo_ms'], errors='coerce') / 1000.0 * freq_est * 1e9
        combined['Ciclos_por_iter'] = combined['Ciclos_CPU'] / pd.to_numeric(combined['Iteracoes'], errors='coerce')
        combined['Freq_GHz']        = freq_est
        print("[aviso] CSVs com schema antigo (Tempo_ms) — convertendo para ciclos estimados")
    else:
        combined['Ciclos_CPU']      = pd.to_numeric(combined['Ciclos_CPU'],      errors='coerce')
        combined['Ciclos_por_iter'] = pd.to_numeric(combined['Ciclos_por_iter'], errors='coerce')
        combined['Freq_GHz']        = pd.to_numeric(combined['Freq_GHz'],        errors='coerce')

    combined['Iteracoes']  = pd.to_numeric(combined['Iteracoes'],  errors='coerce')
    combined['Memoria_KB'] = pd.to_numeric(combined['Memoria_KB'], errors='coerce').clip(lower=0)
    combined['impl_cat']   = combined['Implementacao'].apply(impl_category)

    return combined.dropna(subset=['Ciclos_CPU', 'Iteracoes']).copy()

# ── Aggregate ─────────────────────────────────────────────────────────────────
def aggregate(df, algo, n_filter=None):
    sub = df[df['Algoritmo'] == algo].copy()

    if n_filter is not None:
        sub = sub[sub['N'] == n_filter]

    # Remove valores inválidos para escala log
    sub = sub[
        (sub['Ciclos_CPU'] > 0) &
        (sub['Iteracoes'] > 0)
    ].copy()

    if sub.empty:
        return sub

    agg = (
        sub.groupby(['Linguagem', 'impl_cat', 'Iteracoes'], as_index=False)
           .agg(
               ciclos_mean=('Ciclos_CPU', 'mean'),
               ciclos_std =('Ciclos_CPU', 'std'),
               n_runs     =('Ciclos_CPU', 'count'),
           )
           .assign(ciclos_std=lambda d: d['ciclos_std'].fillna(0))
    )

    return agg

# ── Plot one subplot ──────────────────────────────────────────────────────────
def plot_impl(ax, agg_df, cat):
    sub = agg_df[agg_df['impl_cat'] == cat]
    has_data = False

    for lang_name, color in LANG_PALETTE.items():
        rows = sub[sub['Linguagem'] == lang_name].sort_values('Iteracoes')

        # Remove valores inválidos para escala log
        rows = rows[
            (rows['Iteracoes'] > 0) &
            (rows['ciclos_mean'] > 0)
        ].copy()

        # Remove pontos duplicados no mesmo X para evitar linha vertical
        rows = (
            rows
            .sort_values(['Iteracoes', 'ciclos_mean'])
            .drop_duplicates(subset=['Iteracoes'], keep='last')
        )

        if rows.empty or len(rows) < 2:
            continue
        has_data = True

        x    = rows['Iteracoes'].values
        y    = rows['ciclos_mean'].values
        # Só mostra barras de erro se há mais de 1 run
        yerr = None

        ax.plot(
            x, y,
            color=color,
            label=lang_name,
            linewidth=2.4,
            markersize=7,
            alpha=0.95,
            linestyle=IMPL_STYLE[cat]['linestyle'],
            marker=IMPL_STYLE[cat]['marker'],
            zorder=3,
        )

    ax.set_xscale('log')
    ax.set_yscale('log')
    ax.grid(True, which='both', alpha=0.3, zorder=1)
    ax.set_xlabel('Numero de iteracoes', fontsize=10)
    
    if not has_data:
        ax.text(0.5, 0.5, 'Sem dados\npara esta\nimplementacao',
                ha='center', va='center', transform=ax.transAxes,
                color='#aaa', fontsize=10, style='italic')

    return has_data

# ── Save one chart ────────────────────────────────────────────────────────────
def save_chart(df, algo, freq_ghz, runs_per_point, out_name,
               n_filter=None, suptitle_extra=""):

    agg = aggregate(df, algo, n_filter=n_filter)
    algo_title = ALGO_TITLES.get(algo, algo)
    sup = f'Crescimento: ciclos de CPU vs iteracoes — {algo_title}'
    if suptitle_extra:
        sup += f'  {suptitle_extra}'

    fig, axes = plt.subplots(
        1, 3,
        figsize=(19, 6),
        sharey=False,
        facecolor='#fafafa',
    )
    fig.subplots_adjust(top=0.82, bottom=0.18, left=0.07, right=0.78, wspace=0.1)

    for ax_i, (ax, cat) in enumerate(zip(axes, IMPL_CATEGORIES)):
        plot_impl(ax, agg, cat)
        apply_y_zoom(ax, agg, cat, pad_factor=1.7)
        # Titulo de cada subplot abaixo do titulo geral
        ax.set_title(IMPL_TITLES[cat], fontsize=12, fontweight='bold', pad=6)
        if ax_i == 0:
            ax.set_ylabel('Ciclos de CPU (media de runs)', fontsize=10)
        else:
            ax.set_ylabel('')
            ax.tick_params(labelleft=False)

        # Eixo Y secundario (ns) apenas no ultimo subplot
        if ax_i == 2 and freq_ghz and freq_ghz > 0:
            ns = 1.0 / freq_ghz
            sec = ax.secondary_yaxis(
                'right',
                functions=(lambda c, ns=ns: c * ns,
                           lambda t, ns=ns: t / ns)
            )
            sec.set_ylabel(
                f'Tempo (ns)  —  1 ciclo ≈ {ns:.3f} ns @ {freq_ghz:.2f} GHz',
                fontsize=8, color='#555'
            )
            sec.tick_params(labelsize=8, colors='#555')

    # Legenda fora dos subplots, à direita da figura
    handles = [
        mlines.Line2D([], [], color=LANG_PALETTE[l], linewidth=2.5,
                      marker='o', markersize=6, label=l)
        for l in LANG_PALETTE
    ]
    fig.legend(
        handles=handles, title='Linguagem',
        loc='center right',
        bbox_to_anchor=(0.88, 0.52),
        fontsize=9, title_fontsize=10,
        frameon=True, framealpha=0.95,
    )

    fig.suptitle(sup, fontsize=14, fontweight='bold', y=0.97)
    fig.text(
        0.42, 0.04,
        f'Cada ponto: media de {runs_per_point} runs. '
        f'Eixo Y compartilhado. Eixos log. Seed=42.',
        ha='center', fontsize=8, color='#666', style='italic'
    )

    out_path = OUT_DIR / out_name
    plt.savefig(out_path, dpi=160, bbox_inches='tight', facecolor='#fafafa')
    plt.close(fig)
    print(f"  salvo: {out_path}")

def apply_y_zoom(ax, agg_df, cat, pad_factor=1.6):
    sub = agg_df[agg_df['impl_cat'] == cat]
    vals = sub['ciclos_mean'].dropna()
    vals = vals[vals > 0]

    if vals.empty:
        return

    ymin = vals.min() / pad_factor
    ymax = vals.max() * pad_factor
    ax.set_ylim(ymin, ymax)

# ── Main ──────────────────────────────────────────────────────────────────────
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
        print("[fatal] dataframe vazio")
        return

    freq_series = df['Freq_GHz'].dropna()
    freq_series = freq_series[freq_series > 0.1]
    freq_ghz = float(freq_series.median()) if not freq_series.empty else 2.0
    print(f"Freq mediana: {freq_ghz:.4f} GHz  ->  1 ciclo = {1/freq_ghz:.3f} ns")

    runs_per_point = int(
        df.groupby(['Algoritmo', 'impl_cat', 'N', 'Iteracoes', 'Linguagem'])['Run']
          .nunique().median()
    ) or 10
    print(f"Runs por ponto (mediana): {runs_per_point}")

    save_chart(df, 'Factorial', freq_ghz, runs_per_point,
               'growth_Factorial_N10.png',   n_filter=10,   suptitle_extra='(N=10)')
    save_chart(df, 'Factorial', freq_ghz, runs_per_point,
               'growth_Factorial_N1000.png', n_filter=1000, suptitle_extra='(N=1000, bignum)')
    for algo, out_name in [
        ('Mutually Rec (Even)', 'growth_Mutually_Rec_Even.png'),
        ('Mutually Rec (Odd)',  'growth_Mutually_Rec_Odd.png'),
        ('State Machine',       'growth_State_Machine.png'),
    ]:
        save_chart(df, algo, freq_ghz, runs_per_point, out_name)

    # ── Figura combinada 5 x 3 ────────────────────────────────────────────────
    PANELS = [
        ('Factorial',           10,   'Fatorial (N=10)'),
        ('Factorial',           1000, 'Fatorial (N=1000)'),
        ('Mutually Rec (Even)', None, 'Rec. Mutua (Even)'),
        ('Mutually Rec (Odd)',  None, 'Rec. Mutua (Odd)'),
        ('State Machine',       None, 'Maq. de Estados'),
    ]

    fig, axes = plt.subplots(
    5, 3,
        figsize=(26, 36),
        sharey=False,
        facecolor='#fafafa',
        )
    fig.subplots_adjust(
        top=0.94, bottom=0.05,
        left=0.08, right=0.86,
        hspace=0.55, wspace=0.18
    )

    # Cabecalhos das colunas (uma vez no topo)
    for col_i, cat in enumerate(IMPL_CATEGORIES):
        axes[0, col_i].set_title(IMPL_TITLES[cat], fontsize=13,
                                 fontweight='bold', pad=10)

    for row_i, (algo, n_filter, row_label) in enumerate(PANELS):
        agg = aggregate(df, algo, n_filter=n_filter)
        for col_i, cat in enumerate(IMPL_CATEGORIES):
            ax = axes[row_i, col_i]
            plot_impl(ax, agg, cat)
            apply_y_zoom(ax, agg, cat, pad_factor=1.8)
            if col_i == 0:
                ax.set_ylabel('Ciclos de CPU', fontsize=9)
                ax.annotate(
                    row_label,
                    xy=(-0.30, 0.5), xycoords='axes fraction',
                    fontsize=10, fontweight='bold', rotation=90,
                    va='center', ha='center', color='#333'
                )
            else:
                ax.set_ylabel('')
                ax.tick_params(labelleft=False)
            if row_i < 4:
                ax.set_xlabel('')

    
    # Legenda unica fora dos subplots
    handles = [
        mlines.Line2D([], [], color=LANG_PALETTE[l], linewidth=2.5,
                      marker='o', markersize=6, label=l)
        for l in LANG_PALETTE
    ]
    fig.legend(
        handles=handles, title='Linguagem',
        loc='center right', bbox_to_anchor=(0.99, 0.50),
        fontsize=10, title_fontsize=11,
        frameon=True, framealpha=0.95,
    )

    fig.suptitle(
        'Crescimento: ciclos de CPU vs iteracoes\n(cada coluna = uma implementacao)',
        fontsize=16, fontweight='bold', y=0.98
    )
    fig.text(
        0.47, 0.01,
        f'Eixo Y compartilhado por linha. Eixos log. Seed=42. '
        f'Freq CPU = {freq_ghz:.3f} GHz (1 ciclo = {1/freq_ghz:.3f} ns).',
        ha='center', fontsize=9, color='#555', style='italic'
    )

    combo_path = OUT_DIR / "growth_all_algorithms.png"
    plt.savefig(combo_path, dpi=220, bbox_inches='tight', facecolor='#fafafa')
    plt.close(fig)
    print(f"  salvo: {combo_path}")
    print("\nPronto.")

if __name__ == '__main__':
    main()