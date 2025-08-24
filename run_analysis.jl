#!/usr/bin/env julia

"""
Interface simples para análise de escala fractal de risco.
Uso: julia run_analysis.jl TICKER [--years=N] [--var-level=0.99] [--simple]
"""

using Pkg
Pkg.activate(@__DIR__)
using FractalRiskScaling, Dates

function main()
    # Parse argumentos simples
    args = ARGS
    if length(args) == 0 || args[1] == "--help"
        println("""
Análise de Escala Fractal de Risco

Uso:
    julia run_analysis.jl TICKER                    # Análise padrão (5 anos)
    julia run_analysis.jl TICKER --years=3          # Últimos 3 anos
    julia run_analysis.jl TICKER --simple           # Análise rápida
    julia run_analysis.jl TICKER --var-level=0.95   # VaR 95%
    julia run_analysis.jl TICKER --quiet            # Saída mínima

Exemplos:
    julia run_analysis.jl PETR4.SA
    julia run_analysis.jl ^BVSP --years=2 --simple
    julia run_analysis.jl VALE3.SA --var-level=0.95
        """)
        return
    end
    
    # Ticker obrigatório
    ticker = args[1]
    
    # Defaults
    years = 5
    var_level = 0.99
    simple = false
    quiet = false
    
    # Parse argumentos opcionais
    for arg in args[2:end]
        if startswith(arg, "--years=")
            years = parse(Int, split(arg, "=")[2])
        elseif startswith(arg, "--var-level=")
            var_level = parse(Float64, split(arg, "=")[2])
        elseif arg == "--simple"
            simple = true
        elseif arg == "--quiet"
            quiet = true
        end
    end
    
    # Datas
    end_date = Date(2024, 12, 31)
    start_date = end_date - Year(years)
    
    # Horizontes
    horizons = simple ? [1, 2, 5, 10] : [1, 2, 5, 10, 20, 50]
    
    if !quiet
        println("🎯 ANÁLISE FRACTAL DE RISCO: $ticker")
        println("Período: $start_date a $end_date")
        println("VaR: $(Int(var_level*100))%, Horizontes: $(join(horizons, ", "))")
        println("="^50)
    end
    
    try
        # Chamada da função
        result = analyze_fractal_risk(ticker;
            start_date=start_date,
            end_date=end_date,
            var_level=var_level,
            horizons=horizons,
            output_dir="fractal_results"
        )
        
        if result["success"]
            α = result["alpha_fit"]["alpha"] 
            α_se = result["alpha_fit"]["alpha_se"]
            r2 = result["alpha_fit"]["r2"]
            
            if quiet
                println("$(round(α, digits=4))")
            else
                println("\n✅ RESULTADOS:")
                println("α = $(round(α, digits=4)) ± $(round(α_se, digits=4))")
                println("R² = $(round(r2, digits=4))")
                
                behavior = abs(α - 0.5) < 0.05 ? "Browniano" : 
                          α > 0.5 ? "Persistente" : "Antipersistente"
                println("Comportamento: $behavior")
                
                println("\n📁 Arquivos: $(result["output_dir"])")
                println("📊 $(length(result["plots"])) gráficos")
                println("📋 $(length(result["tables"])) tabelas")
            end
        else
            println("❌ Erro: $(result["error"])")
        end
        
    catch e
        println("❌ Erro: $e")
        exit(1)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end