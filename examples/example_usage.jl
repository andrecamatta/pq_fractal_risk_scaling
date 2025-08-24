"""
Exemplo de uso do pacote FractalRiskScaling.jl

Este script demonstra como usar a NOVA INTERFACE ÚNICA analyze_fractal_risk()
para analisar escala fractal de risco em ativos financeiros brasileiros.

A função consolidada substitui workflows complexos com uma interface simples.
"""

# Setup do pacote 
using Pkg
Pkg.activate("..")
include("../src/FractalRiskScaling.jl")
using .FractalRiskScaling
using Dates

println("="^60)
println("EXEMPLO DE USO - Nova Interface Única")  
println("="^60)
println("Função: analyze_fractal_risk() - Interface Consolidada")

# =======================
# ANÁLISE INDIVIDUAL COM NOVA INTERFACE
# =======================

println("\n1. ANÁLISE INDIVIDUAL - Interface Única")
println("-"^40)

# Exemplo com ação brasileira usando nova interface
ticker = "PETR4.SA"
println("Analisando: $ticker (nova interface simplificada)")

try
    # Nova interface única - substitui run_workflow_simple
    results = analyze_fractal_risk(ticker; 
                                  start_date=Date(2019, 1, 1),
                                  end_date=Date(2024, 8, 23),
                                  var_level=0.99)
    
    if results["success"]
        println("✅ Análise concluída com nova interface!")
        
        # Extrair principais resultados
        alpha_fit = results["alpha_fit"]
        curve = results["curve"]
        quality = results["data_quality"]
        
        println("\n📊 RESULTADOS PRINCIPAIS:")
        println("   α = $(round(alpha_fit["alpha"], digits=4)) ± $(round(alpha_fit["alpha_se"], digits=4))")
        println("   R² = $(round(alpha_fit["r2"], digits=3))")
        println("   Observações: $(quality["n_observations"])")
        println("   Qualidade: $(quality["quality_level"])")
        
        # Interpretação automática
        α = alpha_fit["alpha"]
        if abs(α - 0.5) < 0.05
            println("   📈 Interpretação: Browniano (√h scaling válido)")
        elseif α > 0.5
            println("   📈 Interpretação: Persistência/memória longa")
        else
            println("   📈 Interpretação: Antipersistência/reversão")
        end
        
        # Arquivos gerados (automático)
        println("\n📁 SAÍDA PADRONIZADA:")
        println("   Diretório: $(results["output_dir"])")
        println("   Gráficos: $(length(results["plots"])) arquivos PNG")
        println("   Tabelas: $(length(results["tables"])) arquivos TXT") 
        println("   Relatório: $(basename(results["summary"]))")
        
    else
        println("❌ Erro na análise: $(results["error"])")
    end
    
catch e
    println("❌ Erro: $e")
end

# =======================
# ANÁLISE CUSTOMIZADA - Nova Interface
# =======================

println("\n\n2. ANÁLISE CUSTOMIZADA - Nova Interface")
println("-"^40)

ticker2 = "VALE3.SA"
println("Analisando: $ticker2 (parâmetros personalizados)")

try
    # Parâmetros customizados com nova interface
    results2 = analyze_fractal_risk(ticker2;
                                   start_date=Date(2020, 1, 1),
                                   end_date=Date(2024, 8, 23),
                                   var_level=0.95,  # VaR 95% ao invés de 99%
                                   horizons=[1, 3, 5, 10, 20],  # Horizontes específicos
                                   output_dir="vale_custom")
    
    if results2["success"]
        alpha_fit2 = results2["alpha_fit"]
        period2 = results2["data_quality"]["period_years"]
        
        println("✅ Análise customizada concluída!")
        println("   α = $(round(alpha_fit2["alpha"], digits=4))")
        println("   Período: $(period2) anos")
        println("   VaR 95% (personalizado)")
        
        # Comparar com primeiro ativo se disponível
        if @isdefined(results) && results["success"]
            println("   🔄 Comparação: PETR4 α = $(round(results["alpha_fit"]["alpha"], digits=4)), VALE3 α = $(round(alpha_fit2["alpha"], digits=4))")
        end
    end
    
catch e
    println("❌ Erro na análise customizada: $e")
end

# =======================
# ANÁLISE RÁPIDA - IBOVESPA
# =======================

println("\n\n3. ANÁLISE RÁPIDA - IBOVESPA") 
println("-"^40)

ticker3 = "^BVSP"
println("Análise expressa do Ibovespa (1 ano)")

try
    # Análise rápida com período curto
    results3 = analyze_fractal_risk(ticker3;
                                   start_date=Date(2023, 8, 23),
                                   end_date=Date(2024, 8, 23),
                                   var_level=0.99,
                                   horizons=[1, 2, 5, 10],  # Menos horizontes para velocidade
                                   output_dir="ibovespa_quick")
    
    if results3["success"]
        α3 = results3["alpha_fit"]["alpha"]
        r2_3 = results3["alpha_fit"]["r2"]
        n_obs = results3["data_quality"]["n_observations"]
        
        println("✅ Ibovespa analisado rapidamente!")
        println("   Observações: $n_obs (1 ano)")
        println("   α = $(round(α3, digits=4)) (R² = $(round(r2_3, digits=3)))")
        
        # Interpretação simplificada
        behavior = abs(α3 - 0.5) < 0.1 ? "Browniano" : α3 > 0.5 ? "Persistente" : "Antipersistente"
        println("   Comportamento: $behavior")
        
        println("   📁 Saída: $(basename(results3["output_dir"]))")
    end
    
catch e
    println("❌ Erro: $e")
end

# =======================
# RESUMO - NOVA INTERFACE ÚNICA
# =======================

println("\n\n" * "="^60)
println("RESUMO - INTERFACE ÚNICA CONSOLIDADA")
println("="^60)

println("""
🎯 NOVA INTERFACE ÚNICA DEMONSTRADA:

📊 Função Principal:
   analyze_fractal_risk(ticker; start_date, end_date, var_level, horizons, output_dir)

✅ Vantagens da Interface Consolidada:
   • SUBSTITUI workflows complexos com uma função simples
   • ELIMINA múltiplos scripts de demo redundantes  
   • PADRONIZA saídas em estrutura organizada
   • INCLUI interpretação automática dos resultados
   • GERA todos os 5 gráficos + 2 tabelas + relatório

🔧 Parâmetros Configuráveis:
   • ticker: Ativo ("^BVSP", "PETR4.SA", etc.)
   • start_date/end_date: Período de análise
   • var_level: Nível VaR (0.95, 0.99, 0.995) 
   • horizons: Lista horizontes [1,2,5,10,20,50]
   • output_dir: Diretório personalizado
   
📁 Saída Automática e Padronizada:
   • 5 gráficos PNG (VaR vs horizonte, violações, regressão, rolling α, comparação)
   • 2 tabelas TXT (parâmetros fractais, backtests)
   • 1 relatório interpretativo completo
   • Estrutura organizada: ativo_período/arquivos

🚀 Código Limpo Alcançado:
   • Removidos: demo_complete.jl, demo_ibovespa.jl, demo_completo_todos_graficos.jl
   • Consolidado: Todas funcionalidades em analyze_fractal_risk()
   • Simplificado: Interface intuitiva para todos os casos de uso
""")

println("="^60)
println("✅ Nova Interface Única pronta para produção!")
println("📚 Use analyze_fractal_risk() para todas as análises.")
println("="^60)