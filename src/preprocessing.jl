"""
Módulo para pré-processamento de dados financeiros.
Implementa validação, cálculo de retornos e agregação por horizonte.
"""

"""
    validate_input(df::DataFrame; require_cols=("timestamp", "price")) -> Nothing

Valida se o DataFrame de entrada possui as colunas necessárias e está bem formatado.

# Argumentos
- `df`: DataFrame para validação
- `require_cols`: Tupla com nomes das colunas obrigatórias

# Lança
- `ArgumentError` se validação falhar
"""
function validate_input(df::DataFrame; require_cols=("timestamp", "price"))
    if isempty(df)
        throw(ArgumentError("DataFrame está vazio"))
    end
    
    # Verificar se colunas obrigatórias existem
    missing_cols = [col for col in require_cols if !(col in names(df))]
    if !isempty(missing_cols)
        throw(ArgumentError("Colunas faltando: $(join(missing_cols, ", "))"))
    end
    
    # Verificar tipos das colunas
    if "timestamp" in require_cols
        if !(eltype(df.timestamp) <: Union{DateTime, Missing})
            throw(ArgumentError("Coluna 'timestamp' deve ser DateTime"))
        end
    end
    
    if "price" in require_cols
        if !(eltype(df.price) <: Union{Real, Missing})
            throw(ArgumentError("Coluna 'price' deve ser numérica"))
        end
        
        # Verificar se há valores missing em price
        if any(ismissing.(df.price))
            throw(ArgumentError("Coluna 'price' contém valores missing"))
        end
        
        # Verificar se há NaN em price
        if any(isnan.(df.price))
            throw(ArgumentError("Coluna 'price' contém valores NaN"))
        end
        
        # Verificar se há preços negativos ou zero
        if any(df.price .<= 0)
            throw(ArgumentError("Coluna 'price' contém valores não-positivos"))
        end
    end
    
    # Verificar monotonicidade do timestamp
    if "timestamp" in require_cols && nrow(df) > 1
        if !issorted(df.timestamp)
            @warn "Timestamps não estão ordenados, será necessário ordenar"
        end
        
        # Verificar duplicatas de timestamp
        if length(unique(df.timestamp)) != nrow(df)
            @warn "Timestamps duplicados detectados, será necessário remover"
        end
    end
    
    @debug "Validação concluída com sucesso: $(nrow(df)) observações"
end

"""
    to_returns(df::DataFrame; method::String="log", price_col::String="price") -> DataFrame

Converte série de preços em retornos.

# Argumentos
- `df`: DataFrame com preços
- `method`: Método de cálculo ("log" para logarítmico, "simple" para aritmético)
- `price_col`: Nome da coluna de preços

# Retorna
DataFrame com colunas: timestamp, return
"""
function to_returns(df::DataFrame; method::String="log", price_col::String="price")
    validate_input(df, require_cols=("timestamp", price_col))
    
    if !(method in ["log", "simple"])
        throw(ArgumentError("Método deve ser 'log' ou 'simple'"))
    end
    
    # Ordenar por timestamp
    df_sorted = sort(df, :timestamp)
    
    # Calcular retornos
    prices = df_sorted[!, price_col]
    
    if method == "log"
        # Retornos logarítmicos: r_t = ln(P_t) - ln(P_{t-1})
        returns = diff(log.(prices))
    else
        # Retornos simples: r_t = (P_t - P_{t-1}) / P_{t-1}
        returns = diff(prices) ./ prices[1:end-1]
    end
    
    # Criar DataFrame de saída (remove primeira observação devido à diferença)
    df_returns = DataFrame(
        timestamp = df_sorted.timestamp[2:end],
        returns = returns
    )
    
    @debug "Retornos $(method) calculados: $(nrow(df_returns)) observações"
    return df_returns
end

"""
    aggregate_horizon(r::Union{Vector{Float64}, DataFrame}, h::Int; 
                     overlap::Bool=false, timestamp_col::String="timestamp", 
                     return_col::String="return") -> Union{Vector{Float64}, DataFrame}

Agrega retornos para horizonte h.

# Argumentos
- `r`: Vetor de retornos ou DataFrame com retornos
- `h`: Horizonte de agregação (número de períodos)
- `overlap`: Se true, usa janelas sobrepostas; se false, usa blocos não sobrepostos
- `timestamp_col`: Nome da coluna de timestamp (se DataFrame)
- `return_col`: Nome da coluna de retornos (se DataFrame)

# Retorna
- Se input for Vector: Vector com retornos agregados
- Se input for DataFrame: DataFrame com timestamp e retornos agregados
"""
function aggregate_horizon(r::Vector{Float64}, h::Int; overlap::Bool=false)
    if h <= 0
        throw(ArgumentError("Horizonte h deve ser positivo"))
    end
    
    if h == 1
        return r  # Sem agregação necessária
    end
    
    n = length(r)
    if n < h
        throw(ArgumentError("Série muito curta para horizonte $h (precisa de pelo menos $h observações)"))
    end
    
    if overlap
        # Janelas sobrepostas (deslizantes)
        n_windows = n - h + 1
        r_agg = zeros(n_windows)
        
        for i in 1:n_windows
            r_agg[i] = sum(r[i:i+h-1])
        end
    else
        # Blocos não sobrepostos
        n_blocks = div(n, h)  # Número de blocos completos
        r_agg = zeros(n_blocks)
        
        for i in 1:n_blocks
            start_idx = (i-1) * h + 1
            end_idx = i * h
            r_agg[i] = sum(r[start_idx:end_idx])
        end
    end
    
    return r_agg
end

function aggregate_horizon(df::DataFrame, h::Int; overlap::Bool=false, 
                          timestamp_col::String="timestamp", return_col::String="return")
    validate_input(df, require_cols=(timestamp_col, return_col))
    
    if h <= 0
        throw(ArgumentError("Horizonte h deve ser positivo"))
    end
    
    if h == 1
        return df  # Sem agregação necessária
    end
    
    # Ordenar por timestamp
    df_sorted = sort(df, timestamp_col)
    returns = df_sorted[!, return_col]
    timestamps = df_sorted[!, timestamp_col]
    
    n = length(returns)
    if n < h
        throw(ArgumentError("Série muito curta para horizonte $h"))
    end
    
    if overlap
        # Janelas sobrepostas
        n_windows = n - h + 1
        r_agg = zeros(n_windows)
        ts_agg = Vector{DateTime}(undef, n_windows)
        
        for i in 1:n_windows
            r_agg[i] = sum(returns[i:i+h-1])
            ts_agg[i] = timestamps[i+h-1]  # Timestamp do final da janela
        end
    else
        # Blocos não sobrepostos
        n_blocks = div(n, h)
        r_agg = zeros(n_blocks)
        ts_agg = Vector{DateTime}(undef, n_blocks)
        
        for i in 1:n_blocks
            start_idx = (i-1) * h + 1
            end_idx = i * h
            r_agg[i] = sum(returns[start_idx:end_idx])
            ts_agg[i] = timestamps[end_idx]  # Timestamp do final do bloco
        end
    end
    
    result = DataFrame()
    result[!, Symbol(timestamp_col)] = ts_agg
    result[!, Symbol(return_col)] = r_agg
    
    @debug "Agregação h=$h concluída: $(nrow(result)) observações (overlap=$overlap)"
    return result
end

"""
    clean_returns(df::DataFrame; zscore_threshold::Float64=5.0, 
                 return_col::String="return") -> DataFrame

Remove outliers extremos dos retornos baseado em Z-score.

# Argumentos
- `df`: DataFrame com retornos
- `zscore_threshold`: Limiar de Z-score para considerar outlier
- `return_col`: Nome da coluna de retornos

# Retorna
DataFrame com outliers removidos
"""
function clean_returns(df::DataFrame; zscore_threshold::Float64=5.0, 
                      return_col::String="return")
    validate_input(df, require_cols=("timestamp", return_col))
    
    returns = df[!, return_col]
    
    # Calcular Z-scores
    μ = mean(returns)
    σ = std(returns)
    
    if σ == 0
        @warn "Desvio padrão zero, não há outliers para remover"
        return df
    end
    
    zscores = abs.((returns .- μ) ./ σ)
    
    # Filtrar outliers
    outlier_mask = zscores .> zscore_threshold
    n_outliers = sum(outlier_mask)
    
    if n_outliers > 0
        @info "Removendo $n_outliers outliers (Z-score > $zscore_threshold)"
        df_clean = df[.!outlier_mask, :]
    else
        @info "Nenhum outlier detectado"
        df_clean = df
    end
    
    return df_clean
end

"""
    summary_stats(df::DataFrame; return_col::String="return") -> Dict

Calcula estatísticas descritivas dos retornos.

# Argumentos
- `df`: DataFrame com retornos
- `return_col`: Nome da coluna de retornos

# Retorna
Dictionary com estatísticas descritivas
"""
function summary_stats(df::DataFrame; return_col::String="return")
    validate_input(df, require_cols=(return_col,))
    
    returns = df[!, return_col]
    n = length(returns)
    
    # Estatísticas básicas
    μ = mean(returns)
    σ = std(returns)
    skew_val = skewness(returns)
    kurt_val = kurtosis(returns)
    
    # Quantis
    quantiles = quantile(returns, [0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99])
    
    # Teste de normalidade (Jarque-Bera aproximado)
    jb_stat = n * (skew_val^2 / 6 + kurt_val^2 / 24)
    jb_pvalue = 1 - cdf(Chisq(2), jb_stat)
    
    return Dict(
        "n_obs" => n,
        "mean" => μ,
        "std" => σ,
        "skewness" => skew_val,
        "kurtosis" => kurt_val,
        "min" => minimum(returns),
        "max" => maximum(returns),
        "q01" => quantiles[1],
        "q05" => quantiles[2], 
        "q25" => quantiles[3],
        "median" => quantiles[4],
        "q75" => quantiles[5],
        "q95" => quantiles[6],
        "q99" => quantiles[7],
        "jarque_bera_stat" => jb_stat,
        "jarque_bera_pvalue" => jb_pvalue
    )
end