"""
Módulo de funções utilitárias para o pacote FractalRiskScaling.
"""

"""
    check_data_quality(df::DataFrame; return_col::String="return") -> Dict

Verifica qualidade dos dados de retorno.

# Argumentos
- `df`: DataFrame com retornos
- `return_col`: Nome da coluna de retornos

# Retorna
Dict com métricas de qualidade
"""
function check_data_quality(df::DataFrame; return_col::String="return")
    validate_input(df, require_cols=("timestamp", return_col))
    
    returns = df[!, return_col]
    n = length(returns)
    
    # Estatísticas básicas
    n_missing = sum(ismissing.(returns))
    n_nan = sum(isnan.(returns))
    n_infinite = sum(isinf.(returns))
    n_zero = sum(returns .== 0.0)
    
    # Outliers (Z-score > 5)
    if n > 1
        μ = mean(returns)
        σ = std(returns)
        if σ > 0
            z_scores = abs.((returns .- μ) ./ σ)
            n_outliers = sum(z_scores .> 5.0)
        else
            n_outliers = 0
        end
    else
        n_outliers = 0
    end
    
    # Lacunas temporais
    if n > 1
        time_diffs = diff(df.timestamp)
        # Assumir que a frequência mais comum é a esperada
        mode_diff = mode(time_diffs)
        large_gaps = sum(time_diffs .> mode_diff * 2)
    else
        large_gaps = 0
    end
    
    # Duplicatas de timestamp
    n_duplicates = nrow(df) - length(unique(df.timestamp))
    
    # Resumo de qualidade
    quality_score = 1.0 - (n_missing + n_nan + n_infinite + n_outliers + large_gaps + n_duplicates) / (n * 6)
    quality_score = max(0.0, quality_score)
    
    return Dict(
        "n_observations" => n,
        "n_missing" => n_missing,
        "n_nan" => n_nan,
        "n_infinite" => n_infinite,
        "n_zero" => n_zero,
        "n_outliers" => n_outliers,
        "n_duplicates" => n_duplicates,
        "large_gaps" => large_gaps,
        "quality_score" => quality_score,
        "quality_level" => quality_score > 0.95 ? "Excelente" : 
                          quality_score > 0.90 ? "Bom" :
                          quality_score > 0.80 ? "Aceitável" : "Problemático"
    )
end

"""
    auto_select_horizons(n_returns::Int; min_blocks::Int=50, max_horizons::Int=8) -> Vector{Int}

Seleciona automaticamente horizontes adequados baseado no tamanho da amostra.

# Argumentos
- `n_returns`: Número de retornos disponíveis
- `min_blocks`: Número mínimo de blocos não sobrepostos por horizonte
- `max_horizons`: Número máximo de horizontes

# Retorna
Vector com horizontes sugeridos
"""
function auto_select_horizons(n_returns::Int; min_blocks::Int=50, max_horizons::Int=8)
    if n_returns < min_blocks
        throw(ArgumentError("Amostra muito pequena: $n_returns < $min_blocks"))
    end
    
    # Horizonte máximo possível
    max_h = div(n_returns, min_blocks)
    
    if max_h < 2
        return [1]
    end
    
    # Gerar sequência logarítmica
    if max_h <= 10
        # Para amostras pequenas, usar sequência simples
        horizons = collect(1:min(max_h, max_horizons))
    else
        # Para amostras grandes, usar escala logarítmica
        log_max = log(max_h)
        log_points = range(0, log_max, length=max_horizons)
        horizons = unique(round.(Int, exp.(log_points)))
        
        # Garantir que h=1 está incluído
        if !(1 in horizons)
            horizons = vcat([1], horizons[horizons .> 1])
        end
        
        # Limitar ao máximo
        horizons = horizons[horizons .<= max_h]
    end
    
    # Ordenar e remover duplicatas
    horizons = sort(unique(horizons))
    
    @info "Horizontes selecionados: $horizons (máx. possível: $max_h)"
    return horizons
end

"""
    estimate_sample_size_needed(horizons::Vector{Int}, min_blocks::Int=50) -> Int

Estima tamanho de amostra necessário para os horizontes especificados.

# Argumentos
- `horizons`: Horizontes desejados
- `min_blocks`: Blocos mínimos por horizonte

# Retorna
Tamanho mínimo de amostra recomendado
"""
function estimate_sample_size_needed(horizons::Vector{Int}, min_blocks::Int=50)
    if isempty(horizons)
        return min_blocks
    end
    
    max_h = maximum(horizons)
    return max_h * min_blocks
end

"""
    format_scientific(x::Float64; digits::Int=3) -> String

Formata número em notação científica compacta.

# Argumentos
- `x`: Número para formatar
- `digits`: Dígitos significativos

# Retorna
String formatada
"""
function format_scientific(x::Float64; digits::Int=3)
    if abs(x) < 1e-3 || abs(x) >= 1e3
        return string(round(x, sigdigits=digits))
    else
        return string(round(x, digits=digits))
    end
end

"""
    create_summary_report(ticker::String, results::Dict; output_path::String="summary_report.txt") -> String

Cria relatório resumo dos resultados da análise.

# Argumentos
- `ticker`: Símbolo do ativo
- `results`: Resultados do workflow
- `output_path`: Caminho para salvar relatório

# Retorna
Caminho do arquivo salvo
"""
function create_summary_report(ticker::String, results::Dict; output_path::String="summary_report.txt")
    
    io = IOBuffer()
    
    # Cabeçalho
    println(io, "="^80)
    println(io, "RELATÓRIO DE ANÁLISE DE ESCALA FRACTAL DE RISCO")
    println(io, "="^80)
    println(io, "Ativo: $ticker")
    println(io, "Data: $(Dates.format(now(), "dd/mm/yyyy HH:MM"))")
    println(io, "Gerado por: FractalRiskScaling.jl")
    println(io, "="^80)
    println(io)
    
    # Dados básicos
    if haskey(results, "curve")
        curve = results["curve"]
        println(io, "1. DADOS E AMOSTRA")
        println(io, "-"^40)
        println(io, "Horizontes analisados: ", join(curve.h, ", "))
        println(io, "Observações por horizonte: ", join(curve.Nh, ", "))
        println(io)
    end
    
    # Calibração α
    if haskey(results, "alpha_fit")
        alpha_fit = results["alpha_fit"]
        println(io, "2. CALIBRAÇÃO DO EXPOENTE α")
        println(io, "-"^40)
        println(io, @sprintf("α estimado: %.4f ± %.4f", alpha_fit["alpha"], alpha_fit["alpha_se"]))
        println(io, @sprintf("Intervalo de confiança (95%%): [%.4f, %.4f]", alpha_fit["alpha_ci"]...))
        println(io, @sprintf("R²: %.3f", alpha_fit["r2"]))
        println(io, @sprintf("Pontos usados: %d", alpha_fit["npoints"]))
        
        # Teste vs H0: α = 0.5
        if haskey(alpha_fit, "p_value_alpha_05")
            p_val = alpha_fit["p_value_alpha_05"]
            conclusion = p_val < 0.05 ? "Rejeita" : "Não rejeita"
            println(io, @sprintf("Teste H0: α = 0.5, p-value: %.4f (%s)", p_val, conclusion))
        end
        
        if alpha_fit["r2"] < 0.6
            println(io, "⚠️  AVISO: R² baixo indica linearidade fraca em escala log-log")
        end
        println(io)
    end
    
    # Comparação de escalas
    if haskey(results, "coverage_comparison") || haskey(results, "comparison")
        comparison_key = haskey(results, "coverage_comparison") ? "coverage_comparison" : "comparison"
        comp = results[comparison_key]
        
        println(io, "3. COMPARAÇÃO DE MÉTODOS DE ESCALA")
        println(io, "-"^40)
        println(io, @sprintf("%-3s %12s %12s %12s %8s %8s %8s", 
                             "h", "VaR Emp.", "VaR √h", "VaR α*", "Erro √h", "Erro α*", "Melhor"))
        println(io, "-"^75)
        
        for row in eachrow(comp)
            erro_sqrt = abs(row.error_sqrt) * 100
            erro_alpha = abs(row.error_alpha) * 100
            melhor = erro_sqrt < erro_alpha ? "√h" : "α*"
            
            println(io, @sprintf("%-3d %12.4f %12.4f %12.4f %8.1f%% %8.1f%% %8s", 
                                 row.h, row.VaR_empirical, row.VaR_sqrt, row.VaR_alpha,
                                 erro_sqrt, erro_alpha, melhor))
        end
        println(io)
        
        # Estatísticas agregadas
        n_melhor_sqrt = sum(abs.(comp.error_sqrt) .< abs.(comp.error_alpha))
        n_melhor_alpha = nrow(comp) - n_melhor_sqrt
        println(io, "Desempenho geral:")
        println(io, "  √h é melhor em $n_melhor_sqrt de $(nrow(comp)) horizontes")
        println(io, "  h^α* é melhor em $n_melhor_alpha de $(nrow(comp)) horizontes")
        println(io)
    end
    
    # α temporal
    if haskey(results, "alpha_roll") && nrow(results["alpha_roll"]) > 0
        alpha_roll = results["alpha_roll"]
        println(io, "4. ANÁLISE TEMPORAL DE α")
        println(io, "-"^40)
        println(io, @sprintf("Janelas analisadas: %d", nrow(alpha_roll)))
        println(io, @sprintf("α médio: %.4f ± %.4f", mean(alpha_roll.alpha), std(alpha_roll.alpha)))
        println(io, @sprintf("α mínimo: %.4f", minimum(alpha_roll.alpha)))
        println(io, @sprintf("α máximo: %.4f", maximum(alpha_roll.alpha)))
        
        # Estabilidade
        coef_var = std(alpha_roll.alpha) / mean(alpha_roll.alpha)
        estabilidade = coef_var < 0.1 ? "Alta" : coef_var < 0.2 ? "Média" : "Baixa"
        println(io, @sprintf("Coeficiente de variação: %.3f (%s estabilidade)", coef_var, estabilidade))
        println(io)
    end
    
    # Qualidade dos dados
    if haskey(results, "data_quality")
        quality = results["data_quality"]
        println(io, "5. QUALIDADE DOS DADOS")
        println(io, "-"^40)
        println(io, @sprintf("Observações: %d", quality["n_observations"]))
        println(io, @sprintf("Score de qualidade: %.1f%% (%s)", 
                             quality["quality_score"] * 100, quality["quality_level"]))
        
        if quality["n_outliers"] > 0
            println(io, "⚠️  $(quality["n_outliers"]) outliers detectados")
        end
        if quality["large_gaps"] > 0
            println(io, "⚠️  $(quality["large_gaps"]) lacunas temporais grandes")
        end
        if quality["n_duplicates"] > 0
            println(io, "⚠️  $(quality["n_duplicates"]) timestamps duplicados")
        end
        println(io)
    end
    
    # Recomendações
    println(io, "6. RECOMENDAÇÕES E INTERPRETAÇÃO")
    println(io, "-"^40)
    
    if haskey(results, "alpha_fit")
        alpha_val = results["alpha_fit"]["alpha"]
        
        if alpha_val ≈ 0.5 
            println(io, "✓ α ≈ 0.5: Processos i.i.d. com escala √h (Movimento Browniano)")
        elseif alpha_val > 0.5
            println(io, "↗ α > 0.5: Persistência/correlação positiva (Movimento Browniano Fracionário)")
            println(io, "  VaR cresce mais rápido que √h com o horizonte")
        elseif alpha_val < 0.5
            println(io, "↙ α < 0.5: Antipersistência/reversão à média")
            println(io, "  VaR cresce mais lentamente que √h")
        end
        
        if haskey(results, "alpha_fit") && results["alpha_fit"]["r2"] > 0.8
            println(io, "✓ Boa linearidade em escala log-log indica comportamento de lei de potência")
        end
    end
    
    println(io)
    println(io, "="^80)
    println(io, "Fim do relatório")
    println(io, "="^80)
    
    # Salvar arquivo
    content = String(take!(io))
    write(output_path, content)
    
    @info "Relatório salvo: $output_path"
    return output_path
end

"""
    validate_workflow_params(params::Dict) -> Nothing

Valida parâmetros do workflow antes da execução.

# Argumentos
- `params`: Dict com parâmetros do workflow

# Lança
ArgumentError se parâmetros inválidos
"""
function validate_workflow_params(params::Dict)
    # Ticker obrigatório
    if !haskey(params, "ticker") || isempty(params["ticker"])
        throw(ArgumentError("Ticker é obrigatório"))
    end
    
    # Nível de confiança
    if haskey(params, "q")
        q = params["q"]
        if !(0.5 < q < 0.999)
            throw(ArgumentError("Nível de confiança q deve estar entre 0.5 e 0.999"))
        end
    end
    
    # Horizontes
    if haskey(params, "horizons")
        h = params["horizons"]
        if !isa(h, Vector) || any(h .<= 0) || !all(isa(x, Integer) for x in h)
            throw(ArgumentError("Horizontes devem ser vector de inteiros positivos"))
        end
    end
    
    # Janela para rolling
    if haskey(params, "window")
        window = params["window"]
        if !isa(window, Integer) || window <= 0
            throw(ArgumentError("Janela deve ser inteiro positivo"))
        end
    end
    
    # Bootstrap
    if haskey(params, "mbb")
        mbb = params["mbb"]
        if !isa(mbb, Dict)
            throw(ArgumentError("Parâmetros MBB devem ser Dict"))
        end
        
        required_mbb = ["block_len", "B"]
        for key in required_mbb
            if !haskey(mbb, key) || !isa(mbb[key], Integer) || mbb[key] <= 0
                throw(ArgumentError("MBB.$key deve ser inteiro positivo"))
            end
        end
    end
    
    @debug "Parâmetros do workflow validados com sucesso"
end