"""
Módulo para geração de gráficos e tabelas para o artigo de escala fractal de risco.
Implementa os 5 gráficos especificados na documentação.
"""

using Printf

"""
    plot_var_vs_horizon(curve_df::DataFrame, alpha_fit::Dict, VaR1::Float64; 
                       output_path::String="g1_var_vs_h.png", 
                       title::String="VaR vs Horizonte") -> String

[GRÁFICO 1] log(h) vs log(VaR_h): pontos empíricos + curva √h + reta h^α com IC.

# Argumentos
- `curve_df`: DataFrame com curva empírica (h, VaR_hat)
- `alpha_fit`: Resultado do ajuste α (de fit_alpha_loglog)
- `VaR1`: VaR base para horizonte 1
- `output_path`: Caminho para salvar o gráfico
- `title`: Título do gráfico

# Retorna
String com caminho do arquivo salvo
"""
function plot_var_vs_horizon(curve_df::DataFrame, alpha_fit::Dict, VaR1::Float64; 
                            output_path::String="g1_var_vs_h.png", 
                            title::String="VaR vs Horizonte")
    
    # Dados empíricos
    h_emp = curve_df.h
    var_emp = curve_df.VaR_hat
    
    # Horizonte para curvas teóricas (mais pontos para suavidade)
    h_smooth = range(minimum(h_emp), maximum(h_emp), length=100)
    
    # Curva √h (ancorada em h=1)
    var_sqrt = [theoretical_var_sqrt(VaR1, h) for h in h_smooth]
    
    # Curva h^α
    alpha_est = alpha_fit["alpha"]
    var_alpha = [theoretical_var_power(VaR1, h, alpha_est) for h in h_smooth]
    
    # Bandas de confiança para h^α (se disponíveis)
    alpha_ci = alpha_fit["alpha_ci"]
    var_alpha_lower = [theoretical_var_power(VaR1, h, alpha_ci[1]) for h in h_smooth]
    var_alpha_upper = [theoretical_var_power(VaR1, h, alpha_ci[2]) for h in h_smooth]
    
    # Criar gráfico em escala log-log
    p = plot(log.(h_emp), log.(var_emp), 
             seriestype=:scatter, 
             label="VaR Empírico",
             markersize=4,
             markercolor=:blue,
             markerstrokewidth=0,
             xlabel="log(h)",
             ylabel="log(VaR)",
             title=title,
             legend=:bottomright,
             grid=true,
             gridwidth=1,
             gridcolor=:gray,
             gridalpha=0.3)
    
    # Curva √h
    plot!(p, log.(h_smooth), log.(var_sqrt),
          label="√h",
          linewidth=2,
          linecolor=:red,
          linestyle=:dash)
    
    # Curva h^α
    plot!(p, log.(h_smooth), log.(var_alpha),
          label="h^$(round(alpha_est, digits=3))",
          linewidth=2,
          linecolor=:green)
    
    # Banda de confiança h^α
    plot!(p, log.(h_smooth), log.(var_alpha_lower),
          fillto=log.(var_alpha_upper),
          fillalpha=0.2,
          fillcolor=:green,
          linewidth=0,
          label="IC 95%")
    
    # Estatísticas no gráfico
    r2_text = "R² = $(round(alpha_fit["r2"], digits=3))"
    alpha_text = "α = $(round(alpha_est, digits=3)) ± $(round(alpha_fit["alpha_se"], digits=3))"
    
    annotate!(p, [(log(maximum(h_emp))*0.7, log(maximum(var_emp))*0.9, text(r2_text, 10)),
                  (log(maximum(h_emp))*0.7, log(maximum(var_emp))*0.85, text(alpha_text, 10))])
    
    # Salvar
    savefig(p, output_path)
    @info "Gráfico 1 salvo: $output_path"
    
    return output_path
end

"""
    plot_violations_by_horizon(comparison_df::DataFrame; 
                              output_path::String="g2_violations.png",
                              title::String="Taxa de Violações por Horizonte",
                              target_rate::Float64=0.01) -> String

[GRÁFICO 2] Violações por horizonte com linha alvo (1-q).

# Argumentos
- `comparison_df`: Resultado de compare_scalings
- `output_path`: Caminho para salvar
- `title`: Título do gráfico
- `target_rate`: Taxa alvo de violações

# Retorna
String com caminho do arquivo salvo
"""
function plot_violations_by_horizon(comparison_df::DataFrame; 
                                   output_path::String="g2_violations.png",
                                   title::String="Taxa de Violações por Horizonte",
                                   target_rate::Float64=0.01)
    
    h_vals = comparison_df.h
    
    # Criar gráfico
    p = plot(xlabel="Horizonte (h)",
             ylabel="Taxa de Violações",
             title=title,
             legend=:topright,
             grid=true)
    
    # Taxa alvo
    hline!(p, [target_rate], 
           label="Taxa Alvo ($(round(target_rate*100,digits=1))%)",
           linecolor=:black,
           linestyle=:dash,
           linewidth=2)
    
    # Empirical
    plot!(p, h_vals, comparison_df.rate_empirical,
          label="VaR Empírico",
          marker=:circle,
          markersize=4,
          linewidth=2,
          color=:blue)
    
    # √h
    plot!(p, h_vals, comparison_df.rate_sqrt,
          label="√h",
          marker=:square,
          markersize=4,
          linewidth=2,
          color=:red)
    
    # h^α
    plot!(p, h_vals, comparison_df.rate_alpha,
          label="h^α*",
          marker=:diamond,
          markersize=4,
          linewidth=2,
          color=:green)
    
    # Formatar eixo y como percentual
    yticks!(p, 0:0.005:maximum([maximum(comparison_df.rate_empirical), 
                               maximum(comparison_df.rate_sqrt),
                               maximum(comparison_df.rate_alpha)]) + 0.005)
    
    savefig(p, output_path)
    @info "Gráfico 2 salvo: $output_path"
    
    return output_path
end

"""
    plot_loglog_regression(curve_df::DataFrame, alpha_fit::Dict;
                          output_path::String="g3_regression.png",
                          title::String="Regressão Log-Log") -> String

[GRÁFICO 3] Regressão log-log com pontos, reta ajustada e estatísticas.

# Argumentos  
- `curve_df`: Curva empírica
- `alpha_fit`: Resultado do ajuste
- `output_path`: Caminho para salvar
- `title`: Título

# Retorna
String com caminho do arquivo
"""
function plot_loglog_regression(curve_df::DataFrame, alpha_fit::Dict;
                               output_path::String="g3_regression.png",
                               title::String="Regressão Log-Log")
    
    # Filtrar dados usados na regressão
    h_used = alpha_fit["horizons_used"]
    var_used = curve_df[in.(curve_df.h, Ref(h_used)), :VaR_hat]
    
    # Transformação log
    log_h = log.(h_used)
    log_var = log.(var_used)
    
    # Linha de regressão
    alpha_est = alpha_fit["alpha"]
    intercept = alpha_fit["intercept"]
    
    log_h_smooth = range(minimum(log_h), maximum(log_h), length=100)
    log_var_pred = intercept .+ alpha_est .* log_h_smooth
    
    # Criar gráfico
    p = plot(log_h, log_var,
             seriestype=:scatter,
             label="Dados",
             markersize=5,
             markercolor=:blue,
             xlabel="log(h)",
             ylabel="log(VaR)",
             title=title,
             legend=:bottomright,
             grid=true)
    
    # Linha de regressão
    plot!(p, log_h_smooth, log_var_pred,
          label="Regressão",
          linewidth=2,
          linecolor=:red)
    
    # Estatísticas
    alpha_text = @sprintf("α = %.4f ± %.4f", alpha_est, alpha_fit["alpha_se"])
    r2_text = @sprintf("R² = %.3f", alpha_fit["r2"])
    n_text = @sprintf("N = %d", alpha_fit["npoints"])
    
    # Posicionar textos
    x_pos = minimum(log_h) + 0.1 * (maximum(log_h) - minimum(log_h))
    y_max = maximum(log_var)
    y_range = maximum(log_var) - minimum(log_var)
    
    annotate!(p, [(x_pos, y_max - 0.05*y_range, text(alpha_text, 11, :left)),
                  (x_pos, y_max - 0.10*y_range, text(r2_text, 11, :left)),
                  (x_pos, y_max - 0.15*y_range, text(n_text, 11, :left))])
    
    savefig(p, output_path)
    @info "Gráfico 3 salvo: $output_path"
    
    return output_path
end

"""
    plot_rolling_alpha(rolling_df::DataFrame;
                      output_path::String="g4_rolling_alpha.png",
                      title::String="α Temporal com Bandas de Confiança") -> String

[GRÁFICO 4] Série temporal α_t (rolling) com bandas IC (bootstrap).

# Argumentos
- `rolling_df`: Resultado de rolling_alpha
- `output_path`: Caminho para salvar
- `title`: Título

# Retorna
String com caminho do arquivo
"""
function plot_rolling_alpha(rolling_df::DataFrame;
                           output_path::String="g4_rolling_alpha.png",
                           title::String="α Temporal com Bandas de Confiança")
    
    # Verificar se há dados de bootstrap
    has_bootstrap = "alpha_ci_lower_boot" in names(rolling_df) && 
                   !all(ismissing.(rolling_df.alpha_ci_lower_boot))
    
    # Usar center_date se disponível, senão usar window_id
    if "center_date" in names(rolling_df)
        x_vals = rolling_df.center_date
        xlabel = "Data"
    else
        x_vals = rolling_df.window_id
        xlabel = "Janela"
    end
    
    # Criar gráfico
    p = plot(x_vals, rolling_df.alpha,
             label="α estimado",
             linewidth=2,
             linecolor=:blue,
             xlabel=xlabel,
             ylabel="α",
             title=title,
             legend=:topright,
             grid=true)
    
    # Bandas de confiança paramétricas
    plot!(p, x_vals, rolling_df.alpha_ci_lower_param,
          fillto=rolling_df.alpha_ci_upper_param,
          fillalpha=0.2,
          fillcolor=:blue,
          linewidth=0,
          label="IC Paramétrico")
    
    # Bandas bootstrap se disponíveis
    if has_bootstrap
        valid_boot = .!ismissing.(rolling_df.alpha_ci_lower_boot)
        if sum(valid_boot) > 0
            x_boot = x_vals[valid_boot]
            lower_boot = rolling_df.alpha_ci_lower_boot[valid_boot]
            upper_boot = rolling_df.alpha_ci_upper_boot[valid_boot]
            
            plot!(p, x_boot, lower_boot,
                  fillto=upper_boot,
                  fillalpha=0.15,
                  fillcolor=:green,
                  linewidth=0,
                  label="IC Bootstrap")
        end
    end
    
    # Linha de referência α = 0.5
    hline!(p, [0.5], 
           label="α = 0.5 (√h)",
           linecolor=:red,
           linestyle=:dash,
           linewidth=1)
    
    savefig(p, output_path)
    @info "Gráfico 4 salvo: $output_path"
    
    return output_path
end

"""
    plot_scaling_comparison(curve_df::DataFrame, comparison_df::DataFrame, alpha_est::Float64, VaR1::Float64;
                           output_path::String="g5_scaling_compare.png",
                           title::String="Comparação de Métodos de Escala") -> String

[GRÁFICO 5] Curvas VaR empírico (pontos), √h e h^α* (linhas).

# Argumentos
- `curve_df`: Curva empírica
- `comparison_df`: Comparação de escalas  
- `alpha_est`: Expoente α estimado
- `VaR1`: VaR base
- `output_path`: Caminho para salvar
- `title`: Título

# Retorna
String com caminho do arquivo
"""
function plot_scaling_comparison(curve_df::DataFrame, comparison_df::DataFrame, alpha_est::Float64, VaR1::Float64;
                                output_path::String="g5_scaling_compare.png",
                                title::String="Comparação de Métodos de Escala")
    
    # Dados empíricos
    h_emp = curve_df.h
    var_emp = curve_df.VaR_hat
    
    # Horizonte suave para curvas teóricas
    h_smooth = range(minimum(h_emp), maximum(h_emp), length=100)
    
    # Curvas teóricas
    var_sqrt_smooth = [theoretical_var_sqrt(VaR1, h) for h in h_smooth]
    var_alpha_smooth = [theoretical_var_power(VaR1, h, alpha_est) for h in h_smooth]
    
    # Criar gráfico
    p = plot(h_emp, var_emp,
             seriestype=:scatter,
             label="VaR Empírico",
             markersize=5,
             markercolor=:blue,
             xlabel="Horizonte (h)",
             ylabel="VaR",
             title=title,
             legend=:topleft,
             grid=true)
    
    # Curva √h
    plot!(p, h_smooth, var_sqrt_smooth,
          label="√h",
          linewidth=2,
          linecolor=:red,
          linestyle=:dash)
    
    # Curva h^α*
    plot!(p, h_smooth, var_alpha_smooth,
          label="h^$(round(alpha_est, digits=3))",
          linewidth=2,
          linecolor=:green)
    
    # Adicionar pontos das comparações se disponíveis
    if "VaR_sqrt" in names(comparison_df)
        plot!(p, comparison_df.h, comparison_df.VaR_sqrt,
              seriestype=:scatter,
              markersize=3,
              markercolor=:red,
              markershape=:square,
              label="")
        
        plot!(p, comparison_df.h, comparison_df.VaR_alpha,
              seriestype=:scatter,
              markersize=3,
              markercolor=:green,
              markershape=:diamond,
              label="")
    end
    
    savefig(p, output_path)
    @info "Gráfico 5 salvo: $output_path"
    
    return output_path
end

"""
    create_coverage_table(comparison_df::DataFrame;
                         output_path::String="tabela1_coverage.csv") -> String

[TABELA 1] Cobertura empírica por horizonte: alvo vs observado, erro, Kupiec.

# Argumentos
- `comparison_df`: Resultado de compare_scalings  
- `output_path`: Caminho para salvar CSV

# Retorna
String com caminho do arquivo
"""
function create_coverage_table(comparison_df::DataFrame;
                              output_path::String="tabela1_coverage.csv")
    
    # Criar tabela formatada
    table = DataFrame()
    
    for row in eachrow(comparison_df)
        # VaR Empírico
        push!(table, (
            Horizonte = row.h,
            Método = "Empírico",
            VaR = @sprintf("%.4f", row.VaR_empirical),
            Violações = row.violations_empirical,
            N_Blocos = row.N_blocks,
            Taxa_Observada = @sprintf("%.1f%%", row.rate_empirical * 100),
            Taxa_Alvo = @sprintf("%.1f%%", (1-0.99) * 100),
            Erro = @sprintf("%+.2f%%", row.error_empirical * 100),
            Kupiec_Stat = @sprintf("%.3f", row.kupiec_pvalue_empirical > 0 ? 
                                        -2*log(row.kupiec_pvalue_empirical) : 0.0),
            Kupiec_PValue = @sprintf("%.3f", row.kupiec_pvalue_empirical),
            Rejeita_H0 = row.kupiec_pvalue_empirical < 0.05 ? "Sim" : "Não"
        ), cols=:subset)
        
        # √h
        push!(table, (
            Horizonte = row.h,
            Método = "√h", 
            VaR = @sprintf("%.4f", row.VaR_sqrt),
            Violações = row.violations_sqrt,
            N_Blocos = row.N_blocks,
            Taxa_Observada = @sprintf("%.1f%%", row.rate_sqrt * 100),
            Taxa_Alvo = @sprintf("%.1f%%", (1-0.99) * 100),
            Erro = @sprintf("%+.2f%%", row.error_sqrt * 100),
            Kupiec_Stat = @sprintf("%.3f", row.kupiec_pvalue_sqrt > 0 ? 
                                        -2*log(row.kupiec_pvalue_sqrt) : 0.0),
            Kupiec_PValue = @sprintf("%.3f", row.kupiec_pvalue_sqrt),
            Rejeita_H0 = row.kupiec_pvalue_sqrt < 0.05 ? "Sim" : "Não"
        ), cols=:subset)
        
        # h^α*
        push!(table, (
            Horizonte = row.h,
            Método = "h^α*",
            VaR = @sprintf("%.4f", row.VaR_alpha),
            Violações = row.violations_alpha,
            N_Blocos = row.N_blocks,
            Taxa_Observada = @sprintf("%.1f%%", row.rate_alpha * 100),
            Taxa_Alvo = @sprintf("%.1f%%", (1-0.99) * 100),
            Erro = @sprintf("%+.2f%%", row.error_alpha * 100),
            Kupiec_Stat = @sprintf("%.3f", row.kupiec_pvalue_alpha > 0 ? 
                                        -2*log(row.kupiec_pvalue_alpha) : 0.0),
            Kupiec_PValue = @sprintf("%.3f", row.kupiec_pvalue_alpha),
            Rejeita_H0 = row.kupiec_pvalue_alpha < 0.05 ? "Sim" : "Não"
        ), cols=:subset)
    end
    
    # Salvar
    CSV.write(output_path, table)
    @info "Tabela 1 salva: $output_path"
    
    return output_path
end

"""
    create_comparison_table(comparison_df::DataFrame;
                           output_path::String="tabela2_compare.csv") -> String

[TABELA 2] Backtests comparativos (√h vs h^α*) por horizonte.

# Argumentos
- `comparison_df`: Resultado de compare_scalings
- `output_path`: Caminho para salvar

# Retorna  
String com caminho do arquivo
"""
function create_comparison_table(comparison_df::DataFrame;
                                output_path::String="tabela2_compare.csv")
    
    table = DataFrame()
    
    for row in eachrow(comparison_df)
        push!(table, (
            Horizonte = row.h,
            VaR_Empirical = @sprintf("%.4f", row.VaR_empirical),
            VaR_Sqrt = @sprintf("%.4f", row.VaR_sqrt),
            VaR_Alpha = @sprintf("%.4f", row.VaR_alpha),
            Erro_Abs_Sqrt = @sprintf("%.1f%%", abs(row.error_sqrt) * 100),
            Erro_Abs_Alpha = @sprintf("%.1f%%", abs(row.error_alpha) * 100),
            Melhor_Método = abs(row.error_sqrt) < abs(row.error_alpha) ? "√h" : "h^α*",
            PValue_Sqrt = @sprintf("%.3f", row.kupiec_pvalue_sqrt),
            PValue_Alpha = @sprintf("%.3f", row.kupiec_pvalue_alpha),
            Significativo_Sqrt = row.kupiec_pvalue_sqrt < 0.05 ? "Sim" : "Não",
            Significativo_Alpha = row.kupiec_pvalue_alpha < 0.05 ? "Sim" : "Não"
        ), cols=:subset)
    end
    
    CSV.write(output_path, table)
    @info "Tabela 2 salva: $output_path"
    
    return output_path
end

"""
    generate_all_plots(ticker::String, curve_df::DataFrame, alpha_fit::Dict, 
                      comparison_df::DataFrame, rolling_df::Union{DataFrame,Nothing}=nothing;
                      output_dir::String="outputs") -> Dict{String,String}

Gera todos os gráficos e tabelas para o artigo.

# Argumentos
- `ticker`: Símbolo do ativo
- `curve_df`: Curva empírica
- `alpha_fit`: Ajuste α
- `comparison_df`: Comparação de escalas
- `rolling_df`: α temporal (opcional)
- `output_dir`: Diretório de saída

# Retorna
Dict com caminhos dos arquivos gerados
"""
function generate_all_plots(ticker::String, curve_df::DataFrame, alpha_fit::Dict, 
                           comparison_df::DataFrame, rolling_df::Union{DataFrame,Nothing}=nothing;
                           output_dir::String="outputs")
    
    # Criar diretório de saída
    ticker_dir = joinpath(output_dir, ticker)
    mkpath(ticker_dir)
    
    # VaR base para escalas teóricas
    h1_row = findfirst(curve_df.h .== 1)
    VaR1 = h1_row !== nothing ? curve_df.VaR_hat[h1_row] : curve_df.VaR_hat[1] / sqrt(curve_df.h[1])
    
    paths = Dict{String,String}()
    
    # Gráfico 1: VaR vs Horizonte (log-log)
    paths["g1"] = plot_var_vs_horizon(
        curve_df, alpha_fit, VaR1;
        output_path = joinpath(ticker_dir, "g1_var_vs_h.png"),
        title = "VaR vs Horizonte - $ticker"
    )
    
    # Gráfico 2: Taxa de Violações
    paths["g2"] = plot_violations_by_horizon(
        comparison_df;
        output_path = joinpath(ticker_dir, "g2_violations.png"),
        title = "Taxa de Violações por Horizonte - $ticker"
    )
    
    # Gráfico 3: Regressão Log-Log  
    paths["g3"] = plot_loglog_regression(
        curve_df, alpha_fit;
        output_path = joinpath(ticker_dir, "g3_regression.png"),
        title = "Regressão Log-Log - $ticker"
    )
    
    # Gráfico 4: α Temporal (se disponível)
    if rolling_df !== nothing && nrow(rolling_df) > 0
        paths["g4"] = plot_rolling_alpha(
            rolling_df;
            output_path = joinpath(ticker_dir, "g4_rolling_alpha.png"),
            title = "α Temporal - $ticker"
        )
    end
    
    # Gráfico 5: Comparação de Escalas
    paths["g5"] = plot_scaling_comparison(
        curve_df, comparison_df, alpha_fit["alpha"], VaR1;
        output_path = joinpath(ticker_dir, "g5_scaling_compare.png"),
        title = "Comparação de Métodos de Escala - $ticker"
    )
    
    # Tabela 1: Cobertura
    paths["tabela1"] = create_coverage_table(
        comparison_df;
        output_path = joinpath(ticker_dir, "tabela1_coverage.csv")
    )
    
    # Tabela 2: Comparação
    paths["tabela2"] = create_comparison_table(
        comparison_df;
        output_path = joinpath(ticker_dir, "tabela2_compare.csv")
    )
    
    @info "Todos os artefatos gerados em: $ticker_dir"
    return paths
end