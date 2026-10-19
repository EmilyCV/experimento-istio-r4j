"""
analise.py — análise estatística do experimento Istio x Resilience4j.

Uso (na pasta do projeto):
    python analise.py

Lê os arquivos gerados pelo rodar-variante.sh em results/<variante>/ e gera:
    results/RESULTADOS.md     tabelas, testes de hipótese e limitações
    results/boxplot_p95.png   latência p95 por variante
    results/boxplot_cpu.png   CPU por variante (aplicação, sidecar e total)

As hipóteses estão explicadas em HIPOTESES.md.
"""

import json
import sys
from datetime import datetime
from math import comb
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # gera os PNGs sem abrir janela
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.stats import mannwhitneyu

# ------------------------------------------------------------------ parâmetros
PASTA = Path(__file__).resolve().parent / "results"
VARIANTES = ["baseline", "r4j", "istio"]
ALFA = 0.05
N_HIPOTESES = 3
ALFA_AJUSTADO = ALFA / N_HIPOTESES  # correção de Bonferroni: 0,05 / 3 ≈ 0,0167

# O metrics-server mostra a média dos últimos ~15 s, com atraso de 10 a 25 s.
# As amostras dos primeiros 30 s de cada repetição ainda misturam o período
# sem carga e por isso são descartadas.
DESCARTE_INICIAL_S = 30

# Hipóteses: (código, nome usado na frase, coluna dos dados, unidade)
HIPOTESES = [
    ("H1", "latência p95", "p95", "ms"),
    ("H2", "CPU total", "cpu_total", "milicores"),
    ("H3", "memória total", "mem_total", "MiB"),
]

avisos = []  # problemas encontrados nos dados, listados no início do relatório


# ------------------------------------------------------------------ leitura dos dados
def ler_execucao(variante):
    """Lê o execucao.txt (chave=valor) com os parâmetros usados na execução."""
    arquivo = PASTA / variante / "execucao.txt"
    if not arquivo.exists():
        return {}
    linhas = arquivo.read_text(encoding="utf-8").splitlines()
    return dict(linha.split("=", 1) for linha in linhas if "=" in linha)


def ler_repeticao(variante, arquivo_json):
    """Lê uma repetição: o resumo do k6 (JSON) e o CSV de recursos."""
    numero = int(arquivo_json.stem.replace("rep", ""))
    k6 = json.loads(arquivo_json.read_text(encoding="utf-8"))
    linha = {
        "variante": variante,
        "repeticao": numero,
        "p50": k6["latencia_ms"]["p50"],
        "p95": k6["latencia_ms"]["p95"],
        "media": k6["latencia_ms"]["media"],
        "requisicoes": k6["requisicoes"],
        "taxa_sucesso": k6["taxa_sucesso"],
        "iteracoes_descartadas": k6["iteracoes_descartadas"],
    }

    recursos = pd.read_csv(PASTA / variante / f"rep{numero}-recursos.csv")

    # Classifica cada container: aplicação, sidecar do Istio ou istiod.
    def categoria(r):
        if r["pod"].startswith("istiod"):
            return "istiod"
        return "sidecar" if r["container"] == "istio-proxy" else "aplicacao"

    recursos["categoria"] = recursos.apply(categoria, axis=1)

    validas = recursos[recursos["segundos"] >= DESCARTE_INICIAL_S]
    if validas.empty:
        avisos.append(
            f"{variante} rep{numero}: nenhuma amostra de recursos depois de "
            f"{DESCARTE_INICIAL_S} s (repetição curta demais); usei todas as amostras."
        )
        validas = recursos

    # Em cada instante de coleta, soma os containers de cada categoria
    # (service-a + service-b); depois tira a média dos instantes da repetição.
    por_instante = (
        validas.groupby(["segundos", "categoria"])[["cpu_milicores", "memoria_mib"]]
        .sum()
        .unstack(fill_value=0)
    )
    media = por_instante.mean()

    def valor(medida, cat):
        return float(media.get((medida, cat), 0.0))

    for medida, prefixo in [("cpu_milicores", "cpu"), ("memoria_mib", "mem")]:
        linha[f"{prefixo}_app"] = valor(medida, "aplicacao")
        linha[f"{prefixo}_sidecar"] = valor(medida, "sidecar")
        linha[f"{prefixo}_total"] = linha[f"{prefixo}_app"] + linha[f"{prefixo}_sidecar"]
        linha[f"{prefixo}_istiod"] = valor(medida, "istiod")
    return linha


def ler_tudo():
    """Junta todas as repetições de todas as variantes numa tabela (uma linha por repetição)."""
    linhas = []
    for variante in VARIANTES:
        arquivos = sorted((PASTA / variante).glob("rep*.json"), key=lambda a: int(a.stem[3:]))
        if not arquivos:
            avisos.append(f"{variante}: nenhuma repetição encontrada em results/{variante}/.")
        linhas += [ler_repeticao(variante, a) for a in arquivos]
    return pd.DataFrame(linhas)


# ------------------------------------------------------------------ estatística
def cliffs_delta(x, y):
    """δ de Cliff: (nº de pares com x > y − nº de pares com x < y) / total de pares."""
    x, y = np.asarray(x), np.asarray(y)
    maiores = sum((xi > y).sum() for xi in x)
    menores = sum((xi < y).sum() for xi in x)
    return (maiores - menores) / (len(x) * len(y))


def interpretar_delta(d):
    """Interpretação de Romano et al. (2006)."""
    d = abs(d)
    if d < 0.147:
        return "desprezível"
    if d < 0.33:
        return "pequeno"
    if d < 0.474:
        return "médio"
    return "grande"


# ------------------------------------------------------------------ formatação
def fmt(x, casas=1):
    """Número com vírgula decimal, como se escreve em português."""
    return f"{x:.{casas}f}".replace(".", ",")


def pct(novo, base):
    return (novo - base) / base * 100 if base else float("nan")


# ------------------------------------------------------------------ gráficos
# Cores da paleta categórica de referência (validada para daltonismo).
AZUL, LARANJA, VERDE_AGUA = "#2a78d6", "#eb6834", "#1baf7a"
TEXTO, TEXTO_2, GRADE = "#0b0b0b", "#52514e", "#e4e3df"


def estilo(ax, titulo, eixo_x, eixo_y, casas):
    ax.set_title(titulo, color=TEXTO, fontsize=12, loc="left")
    # Números do eixo com vírgula decimal.
    ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: fmt(v, casas)))
    ax.set_xlabel(eixo_x, color=TEXTO_2)
    ax.set_ylabel(eixo_y, color=TEXTO_2)
    ax.grid(axis="y", color=GRADE, linewidth=0.8)
    ax.set_axisbelow(True)
    for lado in ["top", "right"]:
        ax.spines[lado].set_visible(False)
    for lado in ["left", "bottom"]:
        ax.spines[lado].set_color(TEXTO_2)
    ax.tick_params(colors=TEXTO_2)


def caixa(ax, valores, posicao, cor, largura=0.5, hachura=None):
    """Desenha um boxplot e os pontos de cada repetição por cima."""
    bp = ax.boxplot([valores], positions=[posicao], widths=largura, patch_artist=True,
                    medianprops={"color": TEXTO, "linewidth": 2},
                    whiskerprops={"color": TEXTO_2}, capprops={"color": TEXTO_2},
                    flierprops={"marker": ""})
    bp["boxes"][0].set(facecolor=cor, alpha=0.35, edgecolor=cor, linewidth=1.5, hatch=hachura)
    deslocamento = np.linspace(-largura / 5, largura / 5, len(valores)) if len(valores) > 1 else [0]
    ax.scatter(posicao + np.asarray(deslocamento), valores, s=16, color=cor, zorder=3,
               edgecolor="white", linewidth=0.5)


def grafico_p95(dados):
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for i, v in enumerate(VARIANTES):
        caixa(ax, dados.loc[dados.variante == v, "p95"].values, i, AZUL)
    ax.set_xticks(range(len(VARIANTES)), VARIANTES)
    estilo(ax, "Latência p95 por variante (cada ponto é uma repetição)",
           "Variante", "Latência p95 (ms)", casas=2)
    fig.tight_layout()
    fig.savefig(PASTA / "boxplot_p95.png", dpi=200)
    plt.close(fig)


def grafico_cpu(dados):
    fig, ax = plt.subplots(figsize=(7, 4.5))
    series = [("cpu_app", "Aplicação", AZUL, None),
              ("cpu_sidecar", "Sidecar (istio-proxy)", LARANJA, None),
              ("cpu_total", "Total (aplicação + sidecar)", VERDE_AGUA, "//")]
    for i, v in enumerate(VARIANTES):
        dv = dados[dados.variante == v]
        tem_sidecar = dv["cpu_sidecar"].sum() > 0
        for j, (coluna, rotulo, cor, hachura) in enumerate(series):
            if coluna == "cpu_sidecar" and not tem_sidecar:
                continue  # baseline e r4j não têm sidecar
            caixa(ax, dv[coluna].values, i + (j - 1) * 0.27, cor, largura=0.22, hachura=hachura)
    ax.set_xticks(range(len(VARIANTES)), VARIANTES)
    for _, rotulo, cor, hachura in series:
        ax.bar(0, 0, color=cor, alpha=0.35, edgecolor=cor, hatch=hachura, label=rotulo)
    ax.legend(frameon=False, loc="upper left", labelcolor=TEXTO_2)
    estilo(ax, "CPU por variante (soma de service-a e service-b)",
           "Variante (baseline e r4j não têm sidecar)", "CPU média na repetição (milicores)", casas=0)
    fig.tight_layout()
    fig.savefig(PASTA / "boxplot_cpu.png", dpi=200)
    plt.close(fig)


# ------------------------------------------------------------------ relatório
def relatorio(dados):
    med = dados.groupby("variante").median(numeric_only=True)
    execucoes = {v: ler_execucao(v) for v in VARIANTES}
    linhas = []
    w = linhas.append

    w("# Resultados do experimento Istio × Resilience4j\n")
    w(f"Gerado por `analise.py` em {datetime.now():%Y-%m-%d %H:%M}.\n")
    w("> **Importante:** o cenário não tem falhas, então o retry e o circuit breaker "
      "nunca são acionados. Os números medem **o custo de ter a resiliência configurada** "
      "(o sidecar no caminho × a biblioteca dentro da aplicação), e não a resiliência em ação.\n")

    # --- condições da execução e verificações
    w("## Condições da execução\n")
    w("| Variante | Repetições | Duração (s) | Taxa (req/s) | Menor taxa de sucesso | Iterações descartadas (soma) |")
    w("|---|---|---|---|---|---|")
    for v in VARIANTES:
        dv = dados[dados.variante == v]
        e = execucoes[v]
        w(f"| {v} | {len(dv)} | {e.get('duracao_s', '?')} | {e.get('taxa_rps', '?')} | "
          f"{fmt(dv['taxa_sucesso'].min() * 100, 2)}% | {int(dv['iteracoes_descartadas'].sum())} |")
        if len(dv) and dv["taxa_sucesso"].min() < 1:
            avisos.append(f"{v}: houve requisições com erro (sucesso < 100%).")
        if len(dv) and dv["iteracoes_descartadas"].sum() > 0:
            avisos.append(f"{v}: o k6 descartou iterações; a taxa pedida não foi mantida.")
    w("")
    w(f"CPU e memória: média das amostras do `kubectl top` (a cada 15 s), "
      f"descartando os primeiros {DESCARTE_INICIAL_S} s de cada repetição.\n")

    n_istio = (dados.variante == "istio").sum()
    n_r4j = (dados.variante == "r4j").sum()
    if n_istio and n_r4j:
        p_minimo = 1 / comb(n_istio + n_r4j, n_istio)
        if p_minimo >= ALFA_AJUSTADO:
            avisos.append(
                f"com {n_istio} e {n_r4j} repetições, o menor p-valor possível é "
                f"{fmt(p_minimo, 4)}, maior que o α ajustado ({fmt(ALFA_AJUSTADO, 4)}): "
                "nenhuma diferença pode dar significativa. Use 10 repetições por variante.")

    if avisos:
        w("### Avisos\n")
        for a in avisos:
            w(f"- {a}")
        w("")

    # --- tabela descritiva
    w("## Medianas por variante\n")
    w("Mediana das repetições. CPU em milicores (1000 = 1 núcleo); memória em MiB. "
      "\"Total\" = aplicação + sidecar, somando service-a e service-b.\n")
    w("| Medida | " + " | ".join(VARIANTES) + " |")
    w("|---|" + "---|" * len(VARIANTES))
    medidas = [("p50", "Latência p50 (ms)", 2), ("p95", "Latência p95 (ms)", 2),
               ("cpu_app", "CPU aplicação", 1), ("cpu_sidecar", "CPU sidecar", 1),
               ("cpu_total", "CPU total", 1), ("mem_app", "Memória aplicação", 1),
               ("mem_sidecar", "Memória sidecar", 1), ("mem_total", "Memória total", 1)]
    for coluna, nome, casas in medidas:
        w(f"| {nome} | " + " | ".join(fmt(med.loc[v, coluna], casas) if v in med.index else "—"
                                      for v in VARIANTES) + " |")
    w("")

    # --- testes de hipótese
    w("## Testes de hipótese (Istio × Resilience4j)\n")
    w(f"Mann-Whitney U unilateral (H1: Istio > Resilience4j), α = 0,05 com correção de "
      f"Bonferroni para 3 hipóteses: α ajustado = 0,05 / 3 ≈ {fmt(ALFA_AJUSTADO, 4)}. "
      "A correção é usada porque, ao fazer vários testes, aumenta a chance de achar uma "
      "diferença \"significativa\" só por acaso; dividir o α pelo número de testes mantém "
      "essa chance total em no máximo 5%. Tamanho de efeito: δ de Cliff (Romano et al., 2006).\n")
    w("| Hipótese | Medida | Mediana r4j | Mediana istio | Diferença | Diferença (%) | p-valor | δ de Cliff | Efeito | Significativa? |")
    w("|---|---|---|---|---|---|---|---|---|---|")
    frases = []
    for codigo, nome, coluna, unidade in HIPOTESES:
        istio = dados.loc[dados.variante == "istio", coluna].values
        r4j = dados.loc[dados.variante == "r4j", coluna].values
        if len(istio) == 0 or len(r4j) == 0:
            continue
        p = mannwhitneyu(istio, r4j, alternative="greater").pvalue
        d = cliffs_delta(istio, r4j)
        efeito = interpretar_delta(d)
        m_i, m_r = np.median(istio), np.median(r4j)
        dif, dif_pct = m_i - m_r, pct(m_i, m_r)
        signif = p < ALFA_AJUSTADO
        w(f"| {codigo} | {nome} ({unidade}) | {fmt(m_r, 2)} | {fmt(m_i, 2)} | {fmt(dif, 2)} | "
          f"{fmt(dif_pct, 1)}% | {fmt(p, 4)} | {fmt(d, 2)} | {efeito} | {'sim' if signif else 'não'} |")
        verbo = "aumentou" if dif >= 0 else "reduziu"
        frases.append(
            f"- **{codigo}.** O Istio {verbo} a {nome} em {fmt(abs(dif), 2)} {unidade} "
            f"({fmt(abs(dif_pct), 1)}%) em relação ao Resilience4j. A diferença "
            f"{'é' if signif else 'não é'} estatisticamente significativa "
            f"(p = {fmt(p, 4)}; α ajustado = {fmt(ALFA_AJUSTADO, 4)}) e o efeito é {efeito} "
            f"(δ de Cliff = {fmt(d, 2)}). "
            + ("Rejeita-se H0." if signif else "Não se rejeita H0."))
    w("")
    w("\n".join(frases))
    w("")

    # --- comparação com o baseline (só descritiva)
    w("## Custo em relação ao baseline (descritivo, sem teste)\n")
    w("Diferença entre as medianas de cada abordagem e as do baseline (sem resiliência e sem sidecar).\n")
    w("| Medida | r4j − baseline | istio − baseline |")
    w("|---|---|---|")
    if "baseline" in med.index:
        for coluna, nome, unidade in [("p95", "Latência p95", "ms"), ("cpu_total", "CPU total", "milicores"),
                                      ("mem_total", "Memória total", "MiB")]:
            celulas = []
            for v in ["r4j", "istio"]:
                if v in med.index:
                    b, x = med.loc["baseline", coluna], med.loc[v, coluna]
                    celulas.append(f"{fmt(x - b, 2)} {unidade} ({fmt(pct(x, b), 1)}%)")
                else:
                    celulas.append("—")
            w(f"| {nome} | " + " | ".join(celulas) + " |")
    w("")

    # --- istiod (custo fixo do plano de controle)
    w("## Plano de controle do Istio (istiod), descritivo\n")
    w("O `istiod` ficou instalado durante as três variantes, mas só atende sidecars na variante "
      "istio. É um custo fixo, compartilhado por todo o mesh e fora do caminho da requisição; "
      "por isso não entra no \"total\" das hipóteses.\n")
    w("| Variante | CPU istiod (milicores) | Memória istiod (MiB) |")
    w("|---|---|---|")
    for v in VARIANTES:
        if v in med.index:
            w(f"| {v} | {fmt(med.loc[v, 'cpu_istiod'], 1)} | {fmt(med.loc[v, 'mem_istiod'], 1)} |")
    w("")

    # --- gráficos
    w("## Gráficos\n")
    w("![Latência p95 por variante](boxplot_p95.png)\n")
    w("![CPU por variante](boxplot_cpu.png)\n")

    # --- limitações
    w("## Limitações\n")
    for item in [
        "**Ambiente local:** um cluster kind com um único nó, num notebook (Docker Desktop no "
        "Windows/WSL2). Outros processos da máquina podem interferir, e os números absolutos "
        "não valem para um cluster de produção.",
        "**Uma versão de cada ferramenta:** Istio 1.24.2 (já fora do período de suporte), "
        "Kubernetes 1.31, Spring Boot 3.5.16 e Resilience4j 2.4.0.",
        "**Aplicação sintética:** dois serviços com 5 ms de CPU por requisição, a 20 req/s.",
        "**Cenário sem falhas:** mede o custo de ter a resiliência configurada, não a "
        "resiliência em ação (retry e circuit breaker nunca são acionados).",
        "**mTLS:** o mTLS padrão do Istio entre os sidecars está incluído no custo do sidecar.",
        "**Uma réplica por serviço.**",
        "**Repetições no mesmo deploy:** as repetições de uma variante rodam em sequência, sem "
        "reiniciar os pods; por isso não são totalmente independentes.",
        "**Medição de recursos:** o `kubectl top` (metrics-server) tem resolução de 15 s e "
        "responde com atraso; as amostras são médias aproximadas, não medidas exatas por requisição.",
        "**Recursos do sidecar:** o `istio-proxy` usa os `requests`/`limits` padrão do Istio, "
        "diferentes dos da aplicação.",
    ]:
        w(f"- {item}")
    w("")

    # --- dados brutos (permite conferir os gráficos)
    w("## Dados por repetição\n")
    w("| Variante | Rep. | p50 (ms) | p95 (ms) | CPU app | CPU sidecar | CPU total | Mem. app | Mem. sidecar | Mem. total |")
    w("|---|---|---|---|---|---|---|---|---|---|")
    ordem = dados.assign(ordem=dados.variante.map(VARIANTES.index)).sort_values(["ordem", "repeticao"])
    for _, r in ordem.iterrows():
        w(f"| {r.variante} | {r.repeticao} | {fmt(r.p50, 2)} | {fmt(r.p95, 2)} | {fmt(r.cpu_app)} | "
          f"{fmt(r.cpu_sidecar)} | {fmt(r.cpu_total)} | {fmt(r.mem_app)} | {fmt(r.mem_sidecar)} | "
          f"{fmt(r.mem_total)} |")
    w("")

    (PASTA / "RESULTADOS.md").write_text("\n".join(linhas), encoding="utf-8")


# ------------------------------------------------------------------ programa principal
if __name__ == "__main__":
    # O console do Windows usa cp1252 e não imprime caracteres como "α"; força UTF-8.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    dados = ler_tudo()
    if dados.empty:
        raise SystemExit("Nenhum resultado encontrado em results/. Rode o rodar-variante.sh antes.")
    grafico_p95(dados)
    grafico_cpu(dados)
    relatorio(dados)
    print(f"Repetições lidas: {len(dados)}")
    for a in avisos:
        print(f"AVISO: {a}")
    print("Gerados: results/RESULTADOS.md, results/boxplot_p95.png, results/boxplot_cpu.png")
