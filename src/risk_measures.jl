"""
Módulo para cálculo de medidas de risco (VaR e ES) e construção de curvas por horizonte.
"""

"""
    var_es_empirical(Rh::Vector{Float64}, q::Float64; 
                    tail::String="left", quantile_method::String="linear") -> Dict

Calcula VaR e ES empíricos para uma série de retornos agregados.

# Argumentos
- `Rh`: Vetor de retornos agregados para horizonte h
- `q`: Nível de confiança (ex: 0.99 para 99%)
- `tail`: "left" para cauda esquerda (perdas), "right" para cauda direita
- `quantile_method`: Método de interpolação de quantis

# Retorna
Dict com VaR, ES e número de observações
"""
function var_es_empirical(Rh::Vector{Float64}, q::Float64; 
                         tail::String="left", quantile_method::String="linear")
    if !(0 < q < 1)
        throw(ArgumentError("Nível de confiança q deve estar entre 0 e 1"))
    end
    
    if !(tail in ["left", "right"])
        throw(ArgumentError("tail deve ser 'left' ou 'right'"))
    end
    
    if isempty(Rh)
        throw(ArgumentError("Vetor de retornos está vazio"))
    end
    
    n = length(Rh)
    
    if tail == "left"
        # VaR para cauda esquerda (perdas): quantil (1-q)
        var_level = 1 - q
        var_value = quantile(Rh, var_level)
        
        # ES: média dos retornos ≤ -VaR
        # Como trabalhamos com retornos negativos = perdas, 
        # violações são Rh ≤ var_value
        violations = Rh[Rh .<= var_value]
        
        if isempty(violations)
            # Se não há violações, usar o mínimo
            es_value = minimum(Rh)
            @warn "Nenhuma violação encontrada para VaR, usando mínimo para ES"
        else
            es_value = mean(violations)
        end
        
        # Converter VaR para valor positivo (convenção de reporte)
        var_positive = -var_value
        es_positive = -es_value
        
    else  # tail == "right"
        # VaR para cauda direita: quantil q
        var_value = quantile(Rh, q)
        violations = Rh[Rh .>= var_value]
        
        if isempty(violations)
            es_value = maximum(Rh)
            @warn "Nenhuma violação encontrada para VaR, usando máximo para ES"
        else
            es_value = mean(violations)
        end
        
        var_positive = var_value
        es_positive = es_value
    end
    
    return Dict(
        "VaR" => var_positive,
        "ES" => es_positive,
        "Nh" => n,
        "n_violations" => length(violations)
    )
end

"""
    build_var_es_curve(r::Vector{Float64}, horizons::Vector{Int}, q::Float64; 
                      overlap::Bool=true, min_obs_per_h::Int=50) -> DataFrame

Constrói curva de VaR e ES por horizonte.

# Argumentos
- `r`: Vetor de retornos base (horizonte 1)
- `horizons`: Vetor com horizontes para análise
- `q`: Nível de confiança
- `overlap`: Se true, usa agregação sobreposta; se false, não sobreposta
- `min_obs_per_h`: Número mínimo de observações por horizonte

# Retorna
DataFrame com colunas: h, VaR_hat, ES_hat, Nh
"""
function build_var_es_curve(r::Vector{Float64}, horizons::Vector{Int}, q::Float64; 
                           overlap::Bool=true, min_obs_per_h::Int=50)
    if isempty(r)
        throw(ArgumentError("Vetor de retornos está vazio"))
    end
    
    if isempty(horizons)
        throw(ArgumentError("Lista de horizontes está vazia"))
    end
    
    if any(horizons .<= 0)
        throw(ArgumentError("Todos os horizontes devem ser positivos"))
    end
    
    n_results = length(horizons)
    results = DataFrame(
        h = Int[],
        VaR_hat = Float64[],
        ES_hat = Float64[],
        Nh = Int[]
    )
    
    for h in sort(horizons)
        try
            # Agregar retornos para horizonte h
            Rh = aggregate_horizon(r, h; overlap=overlap)
            
            # Verificar se há observações suficientes
            if length(Rh) < min_obs_per_h
                @warn "Horizonte h=$h tem apenas $(length(Rh)) observações (< $min_obs_per_h), pulando"
                continue
            end
            
            # Calcular VaR e ES
            risk_measures = var_es_empirical(Rh, q)
            
            # Adicionar aos resultados
            push!(results, (
                h = h,
                VaR_hat = risk_measures["VaR"],
                ES_hat = risk_measures["ES"],
                Nh = risk_measures["Nh"]
            ))
            
        catch e
            @warn "Erro ao processar horizonte h=$h: $e"
            continue
        end
    end
    
    if isempty(results)
        throw(ArgumentError("Nenhum horizonte pôde ser processado"))
    end
    
    @info "Curva VaR/ES construída para $(nrow(results)) horizontes"
    return results
end

# Sobrecarga para DataFrame como entrada
function build_var_es_curve(df::DataFrame, horizons::Vector{Int}, q::Float64; 
                           overlap::Bool=true, min_obs_per_h::Int=50,
                           return_col::String="return")
    validate_input(df, require_cols=("timestamp", return_col))
    
    # Extrair vetor de retornos ordenado por timestamp
    df_sorted = sort(df, :timestamp)
    r = df_sorted[!, return_col]
    
    return build_var_es_curve(r, horizons, q; overlap=overlap, min_obs_per_h=min_obs_per_h)
end

"""
    theoretical_var_sqrt(VaR1::Float64, h::Int) -> Float64

Calcula VaR teórico assumindo escala √h.

# Argumentos
- `VaR1`: VaR para horizonte 1
- `h`: Horizonte desejado

# Retorna
VaR escalado por √h
"""
function theoretical_var_sqrt(VaR1::Float64, h::Union{Int,Float64})
    if h <= 0
        throw(ArgumentError("Horizonte deve ser positivo"))
    end
    
    if VaR1 <= 0
        throw(ArgumentError("VaR1 deve ser positivo"))
    end
    
    return VaR1 * sqrt(h)
end

"""
    theoretical_var_power(VaR1::Float64, h::Int, alpha::Float64) -> Float64

Calcula VaR teórico assumindo escala h^α.

# Argumentos
- `VaR1`: VaR para horizonte 1
- `h`: Horizonte desejado
- `alpha`: Expoente de escala

# Retorna
VaR escalado por h^α
"""
function theoretical_var_power(VaR1::Float64, h::Union{Int,Float64}, alpha::Float64)
    if h <= 0
        throw(ArgumentError("Horizonte deve ser positivo"))
    end
    
    if VaR1 <= 0
        throw(ArgumentError("VaR1 deve ser positivo"))
    end
    
    return VaR1 * (h ^ alpha)
end

"""
    compare_scaling_methods(curve_df::DataFrame, alpha::Float64) -> DataFrame

Compara diferentes métodos de escala (√h vs h^α) com VaR empírico.

# Argumentos
- `curve_df`: DataFrame com curva empírica (colunas: h, VaR_hat)
- `alpha`: Expoente de escala calibrado

# Retorna
DataFrame comparativo com VaR empírico, √h e h^α
"""
function compare_scaling_methods(curve_df::DataFrame, alpha::Float64)
    required_cols = ["h", "VaR_hat"]
    missing_cols = [col for col in required_cols if !(col in names(curve_df))]
    if !isempty(missing_cols)
        throw(ArgumentError("Colunas faltando: $(join(missing_cols, ", "))"))
    end
    
    if isempty(curve_df)
        throw(ArgumentError("DataFrame de curva está vazio"))
    end
    
    # Ordenar por horizonte
    df_sorted = sort(curve_df, :h)
    
    # VaR para h=1 (base para escala)
    h1_row = findfirst(df_sorted.h .== 1)
    if h1_row === nothing
        # Se não temos h=1, usar o menor horizonte disponível
        VaR1 = df_sorted.VaR_hat[1]
        h1 = df_sorted.h[1]
        @warn "Horizonte h=1 não encontrado, usando h=$h1 como base"
        
        # Ajustar VaR1 para horizonte 1 assumindo sqrt scaling
        VaR1 = VaR1 / sqrt(h1)
    else
        VaR1 = df_sorted.VaR_hat[h1_row]
    end
    
    # Calcular VaR teórico para cada horizonte
    result = DataFrame()
    result.h = df_sorted.h
    result.VaR_empirical = df_sorted.VaR_hat
    result.VaR_sqrt = [theoretical_var_sqrt(VaR1, h) for h in df_sorted.h]
    result.VaR_alpha = [theoretical_var_power(VaR1, h, alpha) for h in df_sorted.h]
    
    # Calcular erros relativos
    result.error_sqrt = abs.(result.VaR_sqrt - result.VaR_empirical) ./ result.VaR_empirical
    result.error_alpha = abs.(result.VaR_alpha - result.VaR_empirical) ./ result.VaR_empirical
    
    @info "Comparação de métodos de escala concluída para $(nrow(result)) horizontes"
    return result
end

"""
    rolling_var_curve(r::Vector{Float64}, horizons::Vector{Int}, q::Float64;
                     window::Int=750, step::Int=20, overlap::Bool=true, 
                     min_obs_per_h::Int=50) -> DataFrame

Calcula curvas VaR em janelas móveis.

# Argumentos
- `r`: Vetor de retornos
- `horizons`: Horizontes para análise
- `q`: Nível de confiança
- `window`: Tamanho da janela móvel
- `step`: Passo entre janelas
- `overlap`: Agregação sobreposta nos horizontes
- `min_obs_per_h`: Mínimo de observações por horizonte

# Retorna
DataFrame com curvas VaR por janela temporal
"""
function rolling_var_curve(r::Vector{Float64}, horizons::Vector{Int}, q::Float64;
                          window::Int=750, step::Int=20, overlap::Bool=true, 
                          min_obs_per_h::Int=50)
    n = length(r)
    
    if window > n
        throw(ArgumentError("Janela ($window) maior que série ($n)"))
    end
    
    if step <= 0
        throw(ArgumentError("Passo deve ser positivo"))
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
            # Construir curva para esta janela
            curve = build_var_es_curve(r_window, horizons, q; 
                                     overlap=overlap, min_obs_per_h=min_obs_per_h)
            
            # Adicionar identificador da janela
            curve.window = fill(i, nrow(curve))
            curve.window_start = fill(start_idx, nrow(curve))
            curve.window_end = fill(end_idx, nrow(curve))
            
            # Concatenar resultados
            if isempty(results)
                results = curve
            else
                results = vcat(results, curve)
            end
            
        catch e
            @warn "Erro na janela $i ($start_idx:$end_idx): $e"
            continue
        end
    end
    
    @info "Curvas VaR móveis calculadas: $n_windows janelas, $(nrow(results)) observações totais"
    return results
end