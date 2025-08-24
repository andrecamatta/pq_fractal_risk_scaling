"""
Módulo para backtesting de cobertura VaR usando testes de Kupiec e Christoffersen.
Implementa comparação entre diferentes métodos de escala.
"""

"""
    kupiec_pof(violations::Int, N::Int, q::Float64) -> Dict

Teste de Kupiec (1995) - Proportion of Failures.
H0: taxa de violação = (1-q)
H1: taxa de violação ≠ (1-q)

# Argumentos
- `violations`: Número de violações observadas
- `N`: Número total de observações
- `q`: Nível de confiança (ex: 0.99)

# Retorna
Dict com estatística LR e p-value
"""
function kupiec_pof(violations::Int, N::Int, q::Float64)
    if !(0 < q < 1)
        throw(ArgumentError("q deve estar entre 0 e 1"))
    end
    
    if violations < 0 || N <= 0 || violations > N
        throw(ArgumentError("Violações e N devem ser não-negativos e violations ≤ N"))
    end
    
    # Taxa esperada de violação
    p_expected = 1 - q
    
    # Taxa observada de violação  
    p_observed = violations / N
    
    # Estatística de teste (log-likelihood ratio)
    if violations == 0
        # Caso especial: sem violações
        if p_expected > 0
            lr_stat = -2 * N * log(q)
        else
            lr_stat = 0.0
        end
    elseif violations == N
        # Caso especial: todas violações
        if p_expected < 1
            lr_stat = -2 * N * log(1 - q)  
        else
            lr_stat = 0.0
        end
    else
        # Caso geral
        log_like_h0 = violations * log(p_expected) + (N - violations) * log(q)
        log_like_h1 = violations * log(p_observed) + (N - violations) * log(1 - p_observed)
        lr_stat = -2 * (log_like_h0 - log_like_h1)
    end
    
    # p-value (distribuição qui-quadrado com 1 grau de liberdade)
    p_value = 1 - cdf(Chisq(1), lr_stat)
    
    return Dict(
        "violations" => violations,
        "N" => N,
        "expected_rate" => p_expected,
        "observed_rate" => p_observed,
        "lr_statistic" => lr_stat,
        "p_value" => p_value,
        "reject_h0" => p_value < 0.05
    )
end

"""
    coverage_backtest(r::Vector{Float64}, h::Int, VaR_hat::Float64, q::Float64) -> Dict

Executa backtest de cobertura para horizonte específico usando blocos não sobrepostos.

# Argumentos
- `r`: Vetor de retornos base (horizonte 1)
- `h`: Horizonte para teste
- `VaR_hat`: VaR estimado para horizonte h
- `q`: Nível de confiança

# Retorna
Dict com resultados do backtest
"""
function coverage_backtest(r::Vector{Float64}, h::Int, VaR_hat::Float64, q::Float64)
    if h <= 0
        throw(ArgumentError("Horizonte deve ser positivo"))
    end
    
    if VaR_hat <= 0
        throw(ArgumentError("VaR deve ser positivo"))
    end
    
    # Agregar retornos para horizonte h (blocos não sobrepostos)
    Rh = aggregate_horizon(r, h; overlap=false)
    N_blocks = length(Rh)
    
    if N_blocks < 10
        @warn "Poucos blocos para backtest ($N_blocks < 10)"
    end
    
    # Contar violações: Rh < -VaR_hat
    # (retornos negativos são perdas, VaR é reportado como positivo)
    violations = sum(Rh .< -VaR_hat)
    
    # Taxa de violação observada
    obs_rate = violations / N_blocks
    target_rate = 1 - q
    error = obs_rate - target_rate
    
    # Teste de Kupiec
    kupiec_result = kupiec_pof(violations, N_blocks, q)
    
    result = Dict(
        "h" => h,
        "VaR_hat" => VaR_hat,
        "q" => q,
        "violations" => violations,
        "N_blocks" => N_blocks,
        "observed_rate" => obs_rate,
        "target_rate" => target_rate,
        "error" => error,
        "kupiec_stat" => kupiec_result["lr_statistic"],
        "kupiec_pvalue" => kupiec_result["p_value"],
        "kupiec_reject" => kupiec_result["reject_h0"],
        "violation_dates" => findall(Rh .< -VaR_hat)  # Índices das violações
    )
    
    @debug "Backtest h=$h: $violations/$N_blocks violações ($(round(obs_rate*100,digits=2))%)"
    
    return result
end

# Sobrecarga para DataFrame
function coverage_backtest(df::DataFrame, h::Int, VaR_hat::Float64, q::Float64;
                          return_col::String="return")
    validate_input(df, require_cols=("timestamp", return_col))
    
    # Extrair retornos ordenados
    df_sorted = sort(df, :timestamp)
    r = df_sorted[!, return_col]
    
    return coverage_backtest(r, h, VaR_hat, q)
end

"""
    compare_scalings(r::Vector{Float64}, horizons::Vector{Int}, q::Float64, alpha_star::Float64) -> DataFrame

Compara cobertura empírica entre escala √h e h^α*.

# Argumentos
- `r`: Vetor de retornos
- `horizons`: Horizontes para comparação
- `q`: Nível de confiança
- `alpha_star`: Expoente de escala calibrado

# Retorna
DataFrame comparativo por horizonte
"""
function compare_scalings(r::Vector{Float64}, horizons::Vector{Int}, q::Float64, alpha_star::Float64)
    # Construir curva VaR empírica
    curve_empirical = build_var_es_curve(r, horizons, q; overlap=true)
    
    # VaR base (h=1) para escalas teóricas
    h1_row = findfirst(curve_empirical.h .== 1)
    if h1_row === nothing
        # Se não há h=1, extrapolar do menor horizonte assumindo sqrt
        min_h = minimum(curve_empirical.h)
        VaR1_empirical = curve_empirical.VaR_hat[1] / sqrt(min_h)
        @warn "h=1 não encontrado, extrapolando de h=$min_h"
    else
        VaR1_empirical = curve_empirical.VaR_hat[h1_row]
    end
    
    results = DataFrame()
    
    for h in sort(horizons)
        try
            # VaR empírico para este horizonte
            h_row = findfirst(curve_empirical.h .== h)
            if h_row === nothing
                @warn "Horizonte h=$h não encontrado na curva empírica"
                continue
            end
            VaR_empirical = curve_empirical.VaR_hat[h_row]
            
            # VaR teórico √h
            VaR_sqrt = theoretical_var_sqrt(VaR1_empirical, h)
            
            # VaR teórico h^α*
            VaR_alpha = theoretical_var_power(VaR1_empirical, h, alpha_star)
            
            # Backtests
            backtest_empirical = coverage_backtest(r, h, VaR_empirical, q)
            backtest_sqrt = coverage_backtest(r, h, VaR_sqrt, q)
            backtest_alpha = coverage_backtest(r, h, VaR_alpha, q)
            
            # Compilar resultados
            push!(results, (
                h = h,
                VaR_empirical = VaR_empirical,
                VaR_sqrt = VaR_sqrt,
                VaR_alpha = VaR_alpha,
                violations_empirical = backtest_empirical["violations"],
                violations_sqrt = backtest_sqrt["violations"],
                violations_alpha = backtest_alpha["violations"],
                rate_empirical = backtest_empirical["observed_rate"],
                rate_sqrt = backtest_sqrt["observed_rate"],
                rate_alpha = backtest_alpha["observed_rate"],
                error_empirical = backtest_empirical["error"],
                error_sqrt = backtest_sqrt["error"],
                error_alpha = backtest_alpha["error"],
                kupiec_pvalue_empirical = backtest_empirical["kupiec_pvalue"],
                kupiec_pvalue_sqrt = backtest_sqrt["kupiec_pvalue"],
                kupiec_pvalue_alpha = backtest_alpha["kupiec_pvalue"],
                N_blocks = backtest_empirical["N_blocks"]
            ), cols=:subset)
            
        catch e
            @warn "Erro no horizonte h=$h: $e"
            continue
        end
    end
    
    if isempty(results)
        throw(ArgumentError("Nenhuma comparação pôde ser realizada"))
    end
    
    @info "Comparação de escalas: $(nrow(results)) horizontes"
    return results
end

# Sobrecarga para DataFrame
function compare_scalings(df::DataFrame, horizons::Vector{Int}, q::Float64, alpha_star::Float64;
                         return_col::String="return")
    validate_input(df, require_cols=("timestamp", return_col))
    
    df_sorted = sort(df, :timestamp)
    r = df_sorted[!, return_col]
    
    return compare_scalings(r, horizons, q, alpha_star)
end

"""
    christoffersen_independence(violations::BitVector) -> Dict

Teste de independência de Christoffersen (1998) para violações consecutivas.
H0: violações são independentes
H1: violações apresentam clustering

# Argumentos
- `violations`: BitVector indicando violações (true = violação)

# Retorna
Dict com estatística e p-value
"""
function christoffersen_independence(violations::BitVector)
    n = length(violations)
    
    if n < 2
        throw(ArgumentError("Precisa de pelo menos 2 observações"))
    end
    
    # Contar transições
    n00 = n01 = n10 = n11 = 0
    
    for i in 2:n
        if !violations[i-1] && !violations[i]
            n00 += 1
        elseif !violations[i-1] && violations[i]
            n01 += 1
        elseif violations[i-1] && !violations[i]
            n10 += 1
        else  # violations[i-1] && violations[i]
            n11 += 1
        end
    end
    
    # Probabilidades de transição
    n0 = n00 + n01  # Total de não-violações no período t-1
    n1 = n10 + n11  # Total de violações no período t-1
    
    if n0 == 0 || n1 == 0
        # Casos extremos
        return Dict(
            "lr_independence" => 0.0,
            "p_value_independence" => 1.0,
            "reject_independence" => false,
            "transitions" => Dict("n00" => n00, "n01" => n01, "n10" => n10, "n11" => n11)
        )
    end
    
    # Probabilidades condicionais
    p01 = n01 / n0  # P(violação em t | não-violação em t-1)
    p11 = n11 / n1  # P(violação em t | violação em t-1)
    
    # Probabilidade incondicional
    p = sum(violations) / n
    
    # Log-likelihood ratio para independência
    if p01 == 0 || p01 == 1 || p11 == 0 || p11 == 1 || p == 0 || p == 1
        lr_indep = 0.0
    else
        log_like_h0 = n01 * log(p) + n00 * log(1-p) + n11 * log(p) + n10 * log(1-p)
        log_like_h1 = n01 * log(p01) + n00 * log(1-p01) + n11 * log(p11) + n10 * log(1-p11)
        lr_indep = -2 * (log_like_h0 - log_like_h1)
    end
    
    # p-value
    p_value_indep = 1 - cdf(Chisq(1), lr_indep)
    
    return Dict(
        "lr_independence" => lr_indep,
        "p_value_independence" => p_value_indep, 
        "reject_independence" => p_value_indep < 0.05,
        "p01" => p01,
        "p11" => p11,
        "transitions" => Dict("n00" => n00, "n01" => n01, "n10" => n10, "n11" => n11)
    )
end

"""
    christoffersen_combined(violations::Int, N::Int, q::Float64, violations_sequence::BitVector) -> Dict

Teste combinado de Christoffersen: cobertura incondicional + independência.

# Argumentos
- `violations`: Total de violações
- `N`: Total de observações  
- `q`: Nível de confiança
- `violations_sequence`: Sequência de violações para teste de independência

# Retorna
Dict com testes individuais e combinado
"""
function christoffersen_combined(violations::Int, N::Int, q::Float64, violations_sequence::BitVector)
    # Teste de cobertura incondicional (Kupiec)
    kupiec = kupiec_pof(violations, N, q)
    
    # Teste de independência
    indep = christoffersen_independence(violations_sequence)
    
    # Teste combinado
    lr_combined = kupiec["lr_statistic"] + indep["lr_independence"]
    p_value_combined = 1 - cdf(Chisq(2), lr_combined)  # 2 graus de liberdade
    
    return Dict(
        "kupiec" => kupiec,
        "independence" => indep,
        "lr_combined" => lr_combined,
        "p_value_combined" => p_value_combined,
        "reject_combined" => p_value_combined < 0.05
    )
end

"""
    backtest_summary_table(comparison_df::DataFrame; methods::Vector{String}=["empirical", "sqrt", "alpha"]) -> DataFrame

Cria tabela resumo dos backtests por método e horizonte.

# Argumentos
- `comparison_df`: Resultado de compare_scalings
- `methods`: Métodos para incluir na tabela

# Retorna
DataFrame com resumo dos backtests
"""
function backtest_summary_table(comparison_df::DataFrame; methods::Vector{String}=["empirical", "sqrt", "alpha"])
    results = DataFrame()
    
    for method in methods
        for row in eachrow(comparison_df)
            h = row.h
            
            # Extrair métricas do método
            if method == "empirical"
                violations = row.violations_empirical
                rate = row.rate_empirical
                error = row.error_empirical
                pvalue = row.kupiec_pvalue_empirical
                var_val = row.VaR_empirical
            elseif method == "sqrt"
                violations = row.violations_sqrt
                rate = row.rate_sqrt
                error = row.error_sqrt
                pvalue = row.kupiec_pvalue_sqrt
                var_val = row.VaR_sqrt
            elseif method == "alpha"
                violations = row.violations_alpha
                rate = row.rate_alpha
                error = row.error_alpha
                pvalue = row.kupiec_pvalue_alpha
                var_val = row.VaR_alpha
            else
                continue
            end
            
            push!(results, (
                method = method,
                h = h,
                VaR = var_val,
                violations = violations,
                N_blocks = row.N_blocks,
                observed_rate = rate,
                target_rate = 1 - 0.99,  # Assumindo q=0.99
                error = error,
                abs_error = abs(error),
                kupiec_pvalue = pvalue,
                significant = pvalue < 0.05
            ), cols=:subset)
        end
    end
    
    return results
end