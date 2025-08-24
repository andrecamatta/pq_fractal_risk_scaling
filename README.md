# FractalRiskScaling.jl

[![Julia](https://img.shields.io/badge/Julia-1.10+-blue.svg)](https://julialang.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Um pacote Julia para análise de **escala fractal de risco** em ativos financeiros, implementando calibração do expoente α via regressão log-log e backtests de cobertura VaR.

## 📋 Funcionalidades

### Core Features
- 📈 **Ingestão de dados**: Download automático via YFinance.jl (diário e intradiário)
- 🧮 **Pré-processamento**: Cálculo de retornos, agregação por horizonte, limpeza
- 📊 **Medidas de risco**: VaR/ES empíricos por horizonte
- 🔬 **Calibração α**: Regressão log-log com intervalos de confiança
- 🎯 **Backtests**: Testes de Kupiec e Christoffersen para cobertura
- 📱 **Bootstrap**: Moving Block Bootstrap para robustez estatística
- 📈 **Rolling analysis**: Evolução temporal do expoente α
- 🎨 **Interface única**: `analyze_fractal_risk()` - substitui workflows complexos
- 📊 **Saída padronizada**: 5 gráficos + 2 tabelas + relatório interpretativo

### 📁 Artefatos Gerados Automaticamente
- **[GRÁFICO 1]**: `var_vs_horizon.png` - log(h) vs log(VaR): pontos + √h + h^α com IC
- **[GRÁFICO 2]**: `violations_by_horizon.png` - Taxa de violações por horizonte  
- **[GRÁFICO 3]**: `loglog_regression.png` - Regressão log-log com estatísticas
- **[GRÁFICO 4]**: `rolling_alpha.png` - α temporal (rolling) com bandas bootstrap
- **[GRÁFICO 5]**: `scaling_comparison.png` - Comparação VaR empírico vs teórico
- **[TABELA 1]**: `coverage_backtest.txt` - Cobertura empírica + testes Kupiec
- **[TABELA 2]**: `fractal_parameters.txt` - Comparação √h vs h^α* por horizonte
- **[RELATÓRIO]**: `summary_report.txt` - Interpretação completa dos resultados

## 🚀 Instalação

```julia
using Pkg
Pkg.add(url="https://github.com/usuario/FractalRiskScaling.jl")
```

Ou localmente:
```julia
Pkg.activate(".")
Pkg.instantiate()
```

## 💡 Uso Básico

### 🎯 Interface Única: `analyze_fractal_risk()`

O pacote oferece uma **interface única** que substitui workflows complexos:

```julia
using FractalRiskScaling
using Dates

# Análise completa com parâmetros padrão
results = analyze_fractal_risk("PETR4.SA"; 
                              start_date=Date(2020, 1, 1),
                              end_date=Date(2024, 8, 23))

# Resultados principais
if results["success"]
    α = results["alpha_fit"]["alpha"]
    α_se = results["alpha_fit"]["alpha_se"]
    r² = results["alpha_fit"]["r2"]
    
    println("✅ Expoente de escala: α = $α ± $α_se")
    println("📊 R² = $r²")
    
    # Arquivos gerados automaticamente
    println("📁 Diretório: $(results["output_dir"])")
    println("📈 Gráficos: $(length(results["plots"])) arquivos PNG")
    println("📋 Tabelas: $(length(results["tables"])) arquivos TXT")
end
```

### Análise Customizada

```julia
# Parâmetros personalizados
results = analyze_fractal_risk("VALE3.SA";
                              start_date=Date(2022, 1, 1),
                              end_date=Date(2024, 8, 23),
                              var_level=0.95,  # VaR 95% ao invés de 99%
                              horizons=[1, 3, 5, 10, 20],  # Horizontes específicos
                              output_dir="vale_custom")    # Diretório personalizado

if results["success"]
    println("🎯 Análise customizada de $(results["ticker"]) concluída")
    quality = results["data_quality"]
    println("📊 Qualidade: $(quality["quality_level"]) ($(quality["n_observations"]) obs.)")
end
```

### Análise Rápida (Período Curto)

```julia
# Ibovespa - último ano
results = analyze_fractal_risk("^BVSP";
                              start_date=Date(2023, 8, 23),
                              end_date=Date(2024, 8, 23),
                              horizons=[1, 2, 5, 10])  # Menos horizontes = mais rápido

if results["success"]
    α = results["alpha_fit"]["alpha"]
    behavior = abs(α - 0.5) < 0.1 ? "Browniano" : α > 0.5 ? "Persistente" : "Antipersistente"
    println("📈 Comportamento: $behavior (α = $(round(α, digits=3)))")
end
```

## 📊 Interpretação dos Resultados

### Expoente α
- **α ≈ 0.5**: Processo i.i.d. (Movimento Browniano), escala √h válida
- **α > 0.5**: Persistência/memória longa, VaR cresce mais que √h
- **α < 0.5**: Antipersistência/reversão à média

### Qualidade do Ajuste
- **R² > 0.8**: Boa linearidade em escala log-log 
- **R² < 0.6**: Comportamento não-fractal ou dados problemáticos

### Backtests
- **p-value > 0.05**: Cobertura adequada (não rejeita H₀)
- **p-value < 0.05**: Cobertura inadequada (modelo falha)

## 🏗️ Arquitetura do Código

```
src/
├── FractalRiskScaling.jl    # Módulo principal
├── data_io.jl               # Ingestão YFinance  
├── preprocessing.jl         # Retornos e agregação
├── risk_measures.jl         # VaR/ES empíricos
├── scaling.jl               # Calibração α e bootstrap
├── backtest.jl              # Testes Kupiec/Christoffersen
├── plotting.jl              # Gráficos e tabelas
├── workflow.jl              # Orquestração end-to-end
└── utils.jl                 # Funções auxiliares
```

## 📈 Exemplo Completo

```julia
using FractalRiskScaling
using Dates

# 1. Análise completa com interface única
results = analyze_fractal_risk("PETR4.SA";
                              start_date=Date(2020, 1, 1),
                              end_date=Date(2024, 8, 23),
                              var_level=0.99,
                              horizons=[1, 2, 5, 10, 20],
                              output_dir="petr4_analysis")

if results["success"]
    # 2. Extrair resultados principais
    alpha_fit = results["alpha_fit"]
    α = alpha_fit["alpha"]
    α_se = alpha_fit["alpha_se"]
    r² = alpha_fit["r2"]
    ci = alpha_fit["alpha_ci"]
    
    println("🎯 ANÁLISE DE ESCALA FRACTAL - PETR4.SA")
    println("="^50)
    println("📊 α = $(round(α, digits=4)) ± $(round(α_se, digits=4))")
    println("📊 IC 95%: [$(round(ci[1], digits=3)), $(round(ci[2], digits=3))]")
    println("📊 R² = $(round(r², digits=3))")
    
    # 3. Interpretação automática
    if abs(α - 0.5) < 0.05
        println("📈 Comportamento: Browniano (√h scaling válido)")
    elseif α > 0.5
        println("📈 Comportamento: Persistência/memória longa")
    else
        println("📈 Comportamento: Antipersistência/reversão")
    end
    
    # 4. Arquivos gerados (5 gráficos + 2 tabelas + relatório)
    println("\n📁 ARTEFATOS GERADOS:")
    println("📂 Diretório: $(results["output_dir"])")
    
    # Gráficos
    plots = results["plots"]
    println("📈 Gráficos ($(length(plots)) arquivos PNG):")
    for (name, path) in plots
        println("   • $name: $(basename(path))")
    end
    
    # Tabelas
    tables = results["tables"]
    println("📋 Tabelas ($(length(tables)) arquivos TXT):")
    for (name, path) in tables
        println("   • $name: $(basename(path))")
    end
    
    # Relatório
    println("📄 Relatório: $(basename(results["summary"]))")
    
    # 5. Análise comparativa √h vs h^α
    comparison = results["comparison"]
    println("\n📊 COMPARAÇÃO DE MÉTODOS:")
    println("h\tVaR Emp.\tErro √h\tErro α\tMelhor")
    println("-"^45)
    for row in eachrow(comparison)
        erro_sqrt = round(abs(row.error_sqrt) * 100, digits=1)
        erro_alpha = round(abs(row.error_alpha) * 100, digits=1)
        melhor = erro_sqrt < erro_alpha ? "√h" : "α"
        println("$(row.h)\t$(round(row.VaR_empirical, digits=3))\t$(erro_sqrt)%\t$(erro_alpha)%\t$melhor")
    end
    
else
    println("❌ Erro na análise: $(results["error"])")
end
```

### 📊 Estrutura de Retorno

```julia
results = Dict(
    "success" => true,
    "ticker" => "PETR4.SA",
    "alpha_fit" => Dict("alpha" => 0.52, "alpha_se" => 0.03, "r2" => 0.95, "alpha_ci" => [0.46, 0.58]),
    "curve" => DataFrame,        # Curva VaR vs horizonte
    "comparison" => DataFrame,   # Comparação √h vs α
    "data_quality" => Dict,     # Métricas de qualidade
    "output_dir" => "petr4_20200101_20240823",
    "plots" => Dict(            # 5 gráficos PNG
        "var_horizon" => "var_vs_horizon.png",
        "violations" => "violations_by_horizon.png", 
        "loglog" => "loglog_regression.png",
        "rolling" => "rolling_alpha.png",
        "comparison" => "scaling_comparison.png"
    ),
    "tables" => Dict(           # 2 tabelas TXT
        "coverage" => "coverage_backtest.txt",
        "parameters" => "fractal_parameters.txt"
    ),
    "summary" => "summary_report.txt"  # Relatório interpretativo
)
```

## 🧪 Testes

```julia
using Pkg
Pkg.test("FractalRiskScaling")
```

Os testes incluem:
- ✅ **Interface única**: `analyze_fractal_risk()` com dados sintéticos
- ✅ **Processos sintéticos**: i.i.d. (α ≈ 0.5) e AR(1) persistentes (α > 0.5)  
- ✅ **Funções individuais**: 89 testes unitários (100% sucesso)
- ✅ **Integração completa**: end-to-end com dados reais

## 📚 Background Teórico

### Escala Fractal de Risco

Para processos com dependência temporal, o VaR pode escalar como:

**VaRₕ = VaR₁ × h^α**

onde:
- **α = 0.5**: Movimento Browniano (escala √h clássica)
- **α ≠ 0.5**: Processos fractais com memória longa/curta

### Calibração

Regressão log-log:
```
log(VaRₕ) = c + α·log(h) + εₕ
```

### Backtesting

Teste de Kupiec (1995):
- **H₀**: Taxa de violação = (1-q)
- **H₁**: Taxa de violação ≠ (1-q)

## 🔍 Limitações

- **Dados Yahoo Finance**: Limitações de histórico intradiário
- **Bootstrap**: Computacionalmente intensivo para amostras grandes
- **Linearidade**: Requer comportamento de lei de potência em log-log
- **Dependência temporal**: MBB assume estrutura de blocos adequada

## 📖 Referências

- **Gatheral, J., Jaisson, T., Rosenbaum, M.** (2018). Volatility is rough. *Quantitative Finance*, 18(6), 933-949.
- **Kupiec, P. H.** (1995). Techniques for verifying the accuracy of risk measurement models. *Journal of Derivatives*, 3(2), 73-84.
- **Christoffersen, P. F.** (1998). Evaluating interval forecasts. *International Economic Review*, 39(4), 841-862.
- **McNeil, A. J., Frey, R., Embrechts, P.** (2015). *Quantitative Risk Management*. Princeton University Press.

## 🤝 Contribuições

Contribuições são bem-vindas! Por favor:

1. Fork o repositório
2. Crie branch para feature (`git checkout -b feature/AmazingFeature`)
3. Commit mudanças (`git commit -m 'Add AmazingFeature'`)
4. Push para branch (`git push origin feature/AmazingFeature`)
5. Abra Pull Request

## 📄 Licença

Distribuído sob licença MIT. Veja `LICENSE` para mais informações.

## 👨‍💻 Autor

Andre Camatta - [GitHub](https://github.com/usuario)

## 🙏 Agradecimentos

- YFinance.jl para dados financeiros
- Comunidade Julia para ferramentas estatísticas
- Literatura acadêmica em risco quantitativo