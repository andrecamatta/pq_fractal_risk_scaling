module FractalRiskScaling

using YFinance
using DataFrames
using CSV
using Statistics
using StatsBase
using LinearAlgebra
using Distributions
using GLM
using Bootstrap
using Plots
using TimeZones
using Dates
using Random

include("data_io.jl")
include("preprocessing.jl")
include("risk_measures.jl")
include("scaling.jl")
include("backtest.jl")
include("plotting.jl")
include("utils.jl")
include("workflow.jl")

export fetch_prices_daily, fetch_prices_intraday, fetch_metadata
export validate_input, to_returns, aggregate_horizon
export var_es_empirical, build_var_es_curve
export fit_alpha_loglog, scaled_risk, rolling_alpha, mbb_alpha_ci
export kupiec_pof, coverage_backtest, compare_scalings
export plot_var_vs_horizon, plot_violations_by_horizon, plot_loglog_regression, plot_rolling_alpha, plot_scaling_comparison
export run_workflow, run_workflow_simple, batch_analysis, analyze_fractal_risk
export auto_select_horizons, estimate_sample_size_needed, check_data_quality, theoretical_var_sqrt

end