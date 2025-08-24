"""
Módulo para calibração do expoente de escala α via regressão log-log
e cálculo de intervalos de confiança por bootstrap.
"""

"""
    fit_alpha_loglog(curve_df::DataFrame; y_col::String="VaR_hat", 
                    min_obs_per_h::Int=50) -> Dict

Ajusta expoente α via regressão log-log: log(VaR_h) = c + α*log(h) + ε

# Argumentos
- `curve_df`: DataFrame com curva VaR/ES (colunas: h, VaR_hat, Nh)
- `y_col`: Nome da coluna da variável dependente (VaR_hat ou ES_hat)  
- `min_obs_per_h`: Mínimo de observações por horizonte para incluir

# Retorna
Dict com parâmetros estimados, erros padrão e estatísticas
"""
function fit_alpha_loglog(curve_df::DataFrame; y_col::String="VaR_hat", 
                         min_obs_per_h::Int=50)
    required_cols = ["h", y_col, "Nh"]
    missing_cols = [col for col in required_cols if !(col in names(curve_df))]
    if !isempty(missing_cols)
        throw(ArgumentError("Colunas faltando: $(join(missing_cols, ", "))"))
    end
    
    # Filtrar horizontes com observações suficientes
    df_filtered = curve_df[curve_df.Nh .>= min_obs_per_h, :]
    
    if nrow(df_filtered) < 3
        throw(ArgumentError("Poucos pontos para regressão ($(nrow(df_filtered)) < 3)"))
    end
    
    # Filtrar valores positivos para log
    y_values = df_filtered[!, y_col]
    valid_mask = y_values .> 0
    
    if sum(valid_mask) < 3
        throw(ArgumentError("Poucos valores positivos para log-transformação"))
    end
    
    df_valid = df_filtered[valid_mask, :]
    
    # Preparar dados para regressão
    log_h = log.(df_valid.h)
    log_y = log.(df_valid[!, y_col])
    
    # Regressão linear: log(y) = c + α*log(h) + ε
    # Usando GLM para estatísticas completas
    reg_df = DataFrame(log_h = log_h, log_y = log_y)
    model = lm(@formula(log_y ~ log_h), reg_df)
    
    # Extrair resultados
    coef_table = coeftable(model)
    alpha_est = coef(model)[2]  # Coeficiente de log_h
    alpha_se = stderror(model)[2]
    c_est = coef(model)[1]      # Intercepto
    c_se = stderror(model)[1]
    
    # R² e estatísticas
    r2 = StatsModels.r2(model)
    adj_r2 = StatsModels.adjr2(model)
    n_points = length(log_h)
    
    # Intervalo de confiança (95%) para α
    t_crit = quantile(TDist(n_points - 2), 0.975)  # 97.5% para IC bilateral
    alpha_ci_lower = alpha_est - t_crit * alpha_se
    alpha_ci_upper = alpha_est + t_crit * alpha_se
    
    # Teste de hipótese α = 0.5 (raiz quadrada)
    t_stat_05 = (alpha_est - 0.5) / alpha_se
    p_value_05 = 2 * (1 - cdf(TDist(n_points - 2), abs(t_stat_05)))
    
    # Validação da qualidade do ajuste
    if r2 < 0.6
        @warn "R² baixo ($(round(r2, digits=3))) - linearidade fraca em escala log-log"
    end
    
    result = Dict(
        "alpha" => alpha_est,
        "alpha_se" => alpha_se,
        "alpha_ci" => (alpha_ci_lower, alpha_ci_upper),
        "intercept" => c_est,
        "intercept_se" => c_se,
        "r2" => r2,
        "adj_r2" => adj_r2,
        "npoints" => n_points,
        "t_stat_alpha_05" => t_stat_05,
        "p_value_alpha_05" => p_value_05,
        "horizons_used" => df_valid.h
    )
    
    @info "Regressão log-log: α = $(round(alpha_est, digits=4)) ± $(round(alpha_se, digits=4)), R² = $(round(r2, digits=3))"
    
    return result
end

"""
    scaled_risk(VaR1::Float64, h::Int, alpha::Float64) -> Float64

Calcula VaR escalado: VaR_h(α) = VaR_1 * h^α

# Argumentos
- `VaR1`: VaR para horizonte 1
- `h`: Horizonte desejado
- `alpha`: Expoente de escala

# Retorna
VaR escalado
"""
function scaled_risk(VaR1::Float64, h::Int, alpha::Float64)
    if h <= 0
        throw(ArgumentError("Horizonte deve ser positivo"))
    end
    
    if VaR1 <= 0
        throw(ArgumentError("VaR1 deve ser positivo"))  
    end
    
    return VaR1 * (Float64(h) ^ alpha)
end

"""
    rolling_alpha(r::Vector{Float64}, horizons::Vector{Int}, q::Float64;
                 window::Int=750, step::Int=20, overlap::Bool=true, 
                 mbb::Union{Nothing, Dict}=nothing) -> DataFrame

Calcula α em janelas móveis com opção de bootstrap para IC.

# Argumentos
- `r`: Vetor de retornos
- `horizons`: Horizontes para análise
- `q`: Nível de confiança
- `window`: Tamanho da janela
- `step`: Passo entre janelas
- `overlap`: Agregação sobreposta
- `mbb`: Dict com parâmetros para Moving Block Bootstrap: block_len, B, random_state

# Retorna
DataFrame com α temporal e ICs (se bootstrap especificado)
"""
function rolling_alpha(r::Vector{Float64}, horizons::Vector{Int}, q::Float64;
                      window::Int=750, step::Int=20, overlap::Bool=true, 
                      mbb::Union{Nothing, Dict}=nothing)
    n = length(r)
    
    if window > n
        throw(ArgumentError("Janela ($window) maior que série ($n)"))
    end
    
    # Calcular número de janelas
    n_windows = div(n - window, step) + 1
    
    results = DataFrame()
    
    for i in 1:n_windows
        start_idx = (i-1) * step + 1
        end_idx = start_idx + window - 1
        
        if end_idx > n
            break
        end
        
        # Extrair janela
        r_window = r[start_idx:end_idx]
        
        try
            # Construir curva VaR para esta janela
            curve = build_var_es_curve(r_window, horizons, q; overlap=overlap)
            
            # Ajustar α
            alpha_fit = fit_alpha_loglog(curve)
            
            # Calcular IC via bootstrap se especificado
            alpha_ci_lower = missing
            alpha_ci_upper = missing
            
            if mbb !== nothing
                try
                    ci = mbb_alpha_ci(r_window, horizons, q; 
                                    block_len=mbb["block_len"], 
                                    B=mbb["B"], 
                                    random_state=get(mbb, "random_state", 123))
                    alpha_ci_lower, alpha_ci_upper = ci
                catch e
                    @warn "Bootstrap falhou na janela $i: $e"
                end
            end
            
            # Armazenar resultado
            push!(results, (
                window_id = i,
                start_idx = start_idx,
                end_idx = end_idx,
                alpha = alpha_fit["alpha"],
                alpha_se = alpha_fit["alpha_se"],
                alpha_ci_lower_param = alpha_fit["alpha_ci"][1],
                alpha_ci_upper_param = alpha_fit["alpha_ci"][2],
                alpha_ci_lower_boot = alpha_ci_lower,
                alpha_ci_upper_boot = alpha_ci_upper,
                r2 = alpha_fit["r2"],
                npoints = alpha_fit["npoints"]
            ), cols=:subset)
        catch e
            @warn "Erro na janela $i: $e"
            continue
        end
    end
    
    if isempty(results)
        throw(ArgumentError("Nenhuma janela pôde ser processada"))
    end
    
    @info "α rolling calculado: $(nrow(results)) janelas"
    return results
end

# Sobrecarga para DataFrame como entrada
function rolling_alpha(df::DataFrame, horizons::Vector{Int}, q::Float64;
                      window::Int=750, step::Int=20, overlap::Bool=true,
                      mbb::Union{Nothing, Dict}=nothing, return_col::String="return")
    validate_input(df, require_cols=("timestamp", return_col))
    
    # Extrair retornos ordenados
    df_sorted = sort(df, :timestamp)
    r = df_sorted[!, return_col]
    
    result = rolling_alpha(r, horizons, q; window=window, step=step, 
                          overlap=overlap, mbb=mbb)
    
    # Adicionar timestamps correspondentes
    if nrow(result) > 0
        # Mapear índices para timestamps
        timestamps = df_sorted.timestamp
        result.start_date = [timestamps[idx] for idx in result.start_idx]
        result.end_date = [timestamps[min(idx, length(timestamps))] for idx in result.end_idx]
        
        # Data central da janela para plotting
        result.center_date = result.start_date .+ (result.end_date .- result.start_date) ./ 2
    end
    
    return result
end

"""
    mbb_alpha_ci(r_window::Vector{Float64}, horizons::Vector{Int}, q::Float64;
                block_len::Int=25, B::Int=500, random_state::Int=123) -> Tuple{Float64, Float64}

Calcula IC para α via Moving Block Bootstrap.

# Argumentos  
- `r_window`: Janela de retornos
- `horizons`: Horizontes para análise
- `q`: Nível de confiança
- `block_len`: Tamanho dos blocos para bootstrap
- `B`: Número de réplicas bootstrap
- `random_state`: Seed para reprodutibilidade

# Retorna
Tupla (α_lower, α_upper) com IC 95%
"""
function mbb_alpha_ci(r_window::Vector{Float64}, horizons::Vector{Int}, q::Float64;
                     block_len::Int=25, B::Int=500, random_state::Int=123)
    n = length(r_window)
    
    if n < block_len * 2
        throw(ArgumentError("Janela muito pequena para bootstrap com block_len=$block_len"))
    end
    
    if block_len <= 0 || B <= 0
        throw(ArgumentError("block_len e B devem ser positivos"))
    end
    
    Random.seed!(random_state)
    
    alpha_boot = Float64[]
    
    for b in 1:B
        try
            # Gerar amostra bootstrap com blocos móveis
            r_boot = mbb_sample(r_window, block_len)
            
            # Construir curva e ajustar α
            curve_boot = build_var_es_curve(r_boot, horizons, q; overlap=true)
            alpha_fit_boot = fit_alpha_loglog(curve_boot)
            
            push!(alpha_boot, alpha_fit_boot["alpha"])
            
        catch e
            # Se falhar nesta réplica, pular
            @debug "Bootstrap réplica $b falhou: $e"
            continue
        end
    end
    
    if length(alpha_boot) < B * 0.5  # Se menos de 50% das réplicas funcionaram
        throw(ArgumentError("Muitas réplicas bootstrap falharam: $(length(alpha_boot))/$B"))
    end
    
    # Calcular percentis 2.5% e 97.5%
    alpha_ci_lower = quantile(alpha_boot, 0.025)
    alpha_ci_upper = quantile(alpha_boot, 0.975)
    
    @debug "Bootstrap concluído: $(length(alpha_boot)) réplicas válidas"
    
    return (alpha_ci_lower, alpha_ci_upper)
end

"""
    mbb_sample(x::Vector{Float64}, block_len::Int) -> Vector{Float64}

Gera amostra bootstrap usando Moving Block Bootstrap.

# Argumentos
- `x`: Série original
- `block_len`: Tamanho dos blocos

# Retorna
Série bootstrap do mesmo tamanho da original
"""
function mbb_sample(x::Vector{Float64}, block_len::Int)
    n = length(x)
    
    if block_len > n
        throw(ArgumentError("Tamanho do bloco maior que série"))
    end
    
    # Número de blocos necessários
    n_blocks_needed = ceil(Int, n / block_len)
    
    # Índices possíveis para início de blocos
    max_start = n - block_len + 1
    
    # Gerar amostra
    x_boot = Float64[]
    
    for i in 1:n_blocks_needed
        # Escolher início aleatório do bloco
        start_idx = rand(1:max_start)
        end_idx = start_idx + block_len - 1
        
        # Adicionar bloco
        append!(x_boot, x[start_idx:end_idx])
    end
    
    # Truncar para tamanho original
    return x_boot[1:n]
end

"""
    test_alpha_hypothesis(alpha_fit::Dict, null_value::Float64=0.5) -> Dict

Testa hipótese H0: α = null_value vs H1: α ≠ null_value.

# Argumentos
- `alpha_fit`: Resultado de fit_alpha_loglog
- `null_value`: Valor sob H0 (default: 0.5 para escala √h)

# Retorna
Dict com estatística t, p-value e conclusão
"""
function test_alpha_hypothesis(alpha_fit::Dict, null_value::Float64=0.5)
    alpha_est = alpha_fit["alpha"]
    alpha_se = alpha_fit["alpha_se"]
    npoints = alpha_fit["npoints"]
    
    # Estatística t
    t_stat = (alpha_est - null_value) / alpha_se
    
    # p-value bilateral
    p_value = 2 * (1 - cdf(TDist(npoints - 2), abs(t_stat)))
    
    # Conclusão com α = 5%
    reject_h0 = p_value < 0.05
    
    return Dict(
        "null_value" => null_value,
        "t_statistic" => t_stat,
        "p_value" => p_value,
        "reject_h0" => reject_h0,
        "conclusion" => reject_h0 ? "Rejeita H0: α ≠ $null_value" : "Não rejeita H0: α = $null_value"
    )
end