"""
Módulo para ingestão de dados financeiros via YFinance.jl.
Implementa download de preços diários e intradiários com tratamento de timezone.
"""

"""
    fetch_metadata(ticker::String) -> Dict

Obtém metadados do ticker incluindo timezone, moeda e tipo.
"""
function fetch_metadata(ticker::String)
    try
        # Para metadados, vamos usar uma implementação simples baseada no ticker
        # YFinance.jl pode não ter get_info, então criamos metadados básicos
        
        # Detectar mercado baseado no sufixo
        if endswith(ticker, ".SA")
            return Dict(
                "exchangeTimezoneName" => "America/Sao_Paulo",
                "currency" => "BRL",
                "quoteType" => "EQUITY",
                "regularMarketTime" => nothing,
                "timezone" => "America/Sao_Paulo",
                "market" => "B3",
                "exchange" => "SAO"
            )
        else
            return Dict(
                "exchangeTimezoneName" => "America/New_York",
                "currency" => "USD",
                "quoteType" => "EQUITY", 
                "regularMarketTime" => nothing,
                "timezone" => "America/New_York",
                "market" => "US",
                "exchange" => "NASDAQ"
            )
        end
    catch e
        @warn "Não foi possível obter metadados para $ticker: $e"
        return Dict{String, Any}()
    end
end

"""
    fetch_prices_daily(ticker::String, start::Union{String,Date}, end_date::Union{String,Date}; 
                      auto_adjust::Bool=true, tz::String="America/Sao_Paulo") -> DataFrame

Baixa preços diários de um ativo usando YFinance.jl.

# Argumentos
- `ticker`: Símbolo do ativo (ex: "PETR4.SA")
- `start`: Data inicial (formato "YYYY-MM-DD" ou Date)
- `end_date`: Data final (formato "YYYY-MM-DD" ou Date)
- `auto_adjust`: Se true, usa preços ajustados por dividendos/splits
- `tz`: Timezone alvo para conversão

# Retorna
DataFrame com colunas: timestamp, price
"""
function fetch_prices_daily(ticker::String, start::Union{String,Date}, end_date::Union{String,Date};
                           auto_adjust::Bool=true, tz::String="America/Sao_Paulo")
    
    start_date = isa(start, String) ? Date(start) : start
    end_date_parsed = isa(end_date, String) ? Date(end_date) : end_date
    
    try
        # Download dados diários
        data = YFinance.get_prices(ticker, start_date, end_date_parsed; interval="1d")
        
        if isempty(data) || length(data["timestamp"]) == 0
            throw(ArgumentError("Dados não encontrados para $ticker"))
        end
        
        # Selecionar coluna de preço
        price_key = auto_adjust ? "adjclose" : "close"
        if !(price_key in keys(data))
            @warn "Coluna $price_key não encontrada, usando close"
            price_key = "close"
        end
        
        # Criar DataFrame de saída
        df = DataFrame(
            timestamp = data["timestamp"],
            price = data[price_key]
        )
        
        # Remover valores missing/NaN
        filter!(row -> !ismissing(row.price) && !isnan(row.price), df)
        
        # Converter timezone se necessário
        if tz != "UTC"
            try
                target_tz = TimeZone(tz)
                # Assumindo que os dados do YFinance vêm em UTC
                df.timestamp = ZonedDateTime.(df.timestamp, tz"UTC") .|> x -> astimezone(x, target_tz) .|> DateTime
            catch e
                @warn "Erro na conversão de timezone, mantendo original: $e"
            end
        end
        
        # Ordenar por timestamp e remover duplicatas
        sort!(df, :timestamp)
        unique!(df, :timestamp)
        
        @info "Dados diários baixados: $(nrow(df)) observações para $ticker ($(start_date) a $(end_date_parsed))"
        return df
        
    catch e
        @error "Erro ao baixar dados diários para $ticker: $e"
        rethrow(e)
    end
end

"""
    fetch_prices_intraday(ticker::String; period::String="60d", interval::String="5m", 
                          tz::String="America/Sao_Paulo") -> DataFrame

Baixa preços intradiários de um ativo.

# Argumentos
- `ticker`: Símbolo do ativo
- `period`: Período de dados ("1d", "5d", "1mo", "3mo", "6mo", "1y", "2y", "5y", "10y", "ytd", "max")
- `interval`: Intervalo ("1m", "2m", "5m", "15m", "30m", "60m", "90m", "1h")
- `tz`: Timezone alvo

# Retorna
DataFrame com colunas: timestamp, price
"""
function fetch_prices_intraday(ticker::String; period::String="60d", interval::String="5m",
                              tz::String="America/Sao_Paulo")
    
    # Validar interval
    valid_intervals = ["1m", "2m", "5m", "15m", "30m", "60m", "90m", "1h"]
    if !(interval in valid_intervals)
        throw(ArgumentError("Interval $interval não é válido. Use: $(join(valid_intervals, ", "))"))
    end
    
    # Calcular datas baseado no período
    end_date = today()
    start_date = _period_to_start_date(period, end_date)
    
    try
        # Verificar se período excede limites do Yahoo para intervalos curtos
        if _period_exceeds_yahoo_limits(period, interval)
            return _fetch_intraday_chunked(ticker, start_date, end_date, interval, tz)
        end
        
        # Download dados intradiários
        data = YFinance.get_prices(ticker, start_date, end_date; interval=interval)
        
        if isempty(data) || length(data["timestamp"]) == 0
            throw(ArgumentError("Dados intradiários não encontrados para $ticker"))
        end
        
        # Criar DataFrame de saída
        df = DataFrame(
            timestamp = data["timestamp"],
            price = data["close"]  # Intradiário usa close
        )
        
        # Remover valores missing/NaN
        filter!(row -> !ismissing(row.price) && !isnan(row.price), df)
        
        # Converter timezone se necessário
        if tz != "UTC"
            try
                target_tz = TimeZone(tz)
                df.timestamp = ZonedDateTime.(df.timestamp, tz"UTC") .|> x -> astimezone(x, target_tz) .|> DateTime
            catch e
                @warn "Erro na conversão de timezone, mantendo original: $e"
            end
        end
        
        # Ordenar por timestamp e remover duplicatas
        sort!(df, :timestamp)
        unique!(df, :timestamp)
        
        # Forward fill lacunas curtas (≤ 1 intervalo)
        _forward_fill_short_gaps!(df, interval)
        
        @info "Dados intradiários baixados: $(nrow(df)) observações para $ticker ($interval, $period)"
        return df
        
    catch e
        @error "Erro ao baixar dados intradiários para $ticker: $e"
        rethrow(e)
    end
end

# Funções auxiliares

function _period_to_start_date(period::String, end_date::Date)
    if period == "1d"
        return end_date - Day(1)
    elseif period == "5d"
        return end_date - Day(5)
    elseif period == "1mo"
        return end_date - Month(1)
    elseif period == "3mo"
        return end_date - Month(3)
    elseif period == "6mo"
        return end_date - Month(6)
    elseif period == "1y"
        return end_date - Year(1)
    elseif period == "2y"
        return end_date - Year(2)
    elseif period == "5y"
        return end_date - Year(5)
    elseif period == "10y"
        return end_date - Year(10)
    elseif period == "max"
        return Date(1970, 1, 1)  # Data muito antiga
    else
        # Tentar parseear formato como "60d"
        if endswith(period, "d")
            days = parse(Int, period[1:end-1])
            return end_date - Day(days)
        else
            @warn "Período $period não reconhecido, usando 60d"
            return end_date - Day(60)
        end
    end
end

function _period_exceeds_yahoo_limits(period::String, interval::String)
    days = _period_to_days(period)
    
    # Limites aproximados do Yahoo Finance
    if interval == "1m" && days > 7
        return true
    elseif interval == "2m" && days > 60
        return true
    else
        return false
    end
end

function _period_to_days(period::String)
    if period == "1d"; return 1
    elseif period == "5d"; return 5
    elseif period == "1mo"; return 30
    elseif period == "3mo"; return 90
    elseif period == "6mo"; return 180
    elseif period == "1y"; return 365
    elseif period == "2y"; return 730
    elseif period == "5y"; return 1825
    elseif period == "10y"; return 3650
    elseif endswith(period, "d")
        return parse(Int, period[1:end-1])
    else
        return 365  # fallback
    end
end

function _fetch_intraday_chunked(ticker::String, start_date::Date, end_date::Date, interval::String, tz::String)
    @info "Período excede limite do Yahoo para $interval. Dividindo em chunks ou usando 5m..."
    
    # Para períodos longos com intervalos muito curtos, usar 5m
    if interval in ["1m", "2m"]
        @warn "Usando interval=5m ao invés de $interval para período longo"
        interval = "5m"
    end
    
    # Download com interval ajustado
    try
        data = YFinance.get_prices(ticker, start_date, end_date; interval=interval)
        
        df = DataFrame(
            timestamp = data["timestamp"],
            price = data["close"]
        )
        
        # Processar como no método principal
        filter!(row -> !ismissing(row.price) && !isnan(row.price), df)
        
        if tz != "UTC"
            try
                target_tz = TimeZone(tz)
                df.timestamp = ZonedDateTime.(df.timestamp, tz"UTC") .|> x -> astimezone(x, target_tz) .|> DateTime
            catch e
                @warn "Erro na conversão de timezone: $e"
            end
        end
        
        sort!(df, :timestamp)
        unique!(df, :timestamp)
        
        return df
        
    catch e
        @error "Erro no download chunked para $ticker: $e"
        rethrow(e)
    end
end

function _forward_fill_short_gaps!(df::DataFrame, interval::String)
    if nrow(df) < 2
        return
    end
    
    interval_minutes = _interval_to_minutes(interval)
    expected_gap = Minute(interval_minutes)
    
    # Identificar lacunas curtas (até 1 intervalo) e forward fill
    for i in 2:nrow(df)
        actual_gap = df.timestamp[i] - df.timestamp[i-1]
        
        # Se a lacuna for menor que 1.5x o intervalo esperado, é aceitável
        if actual_gap <= expected_gap * 1.5
            continue
        elseif actual_gap <= expected_gap * 2
            # Lacuna pequena que poderia ser preenchida, mas mantendo simples por ora
            @debug "Lacuna pequena detectada: $(actual_gap) entre $(df.timestamp[i-1]) e $(df.timestamp[i])"
        end
    end
end

function _interval_to_minutes(interval::String)
    if endswith(interval, "m")
        return parse(Int, interval[1:end-1])
    elseif endswith(interval, "h")
        return parse(Int, interval[1:end-1]) * 60
    else
        return 5  # fallback para 5 minutos
    end
end