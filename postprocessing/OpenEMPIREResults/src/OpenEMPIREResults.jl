module OpenEMPIREResults

using CSV

export write_result_plots

include("constants.jl")
include("data_utils.jl")
include("plotly.jl")
include("maps.jl")
include("specs.jl")

"""
    write_result_plots(result_dir; output_dir=joinpath(result_dir, "Output"), plot_dir=joinpath(result_dir, "Plots"))

Create a small HTML dashboard from the result CSV files
"""
function write_result_plots(
        result_dir::AbstractString;
        output_dir::AbstractString = joinpath(result_dir, "Output"),
        plot_dir::AbstractString = joinpath(result_dir, "Plots"),
        input_dir::Union{Nothing, AbstractString} = nothing,
    )
    mkpath(plot_dir)

    result_specs = _available_result_plot_specs(output_dir, input_dir)
    input_specs = NamedTuple[]
    if input_dir !== nothing
        input_specs = _available_input_plot_specs(input_dir)
    end
    plot_specs = vcat(result_specs, input_specs)
    isempty(plot_specs) && throw(ArgumentError("No supported result CSV files found in $output_dir"))

    html_plots = NamedTuple[]
    for spec in plot_specs
        path = joinpath(plot_dir, spec.filename)
        _write_plotly_html(path, spec.title, spec.traces, spec.layout)
        push!(html_plots, spec)
    end

    dashboard_path = joinpath(plot_dir, "dashboard.html")
    n_result_specs = length(result_specs)
    result_html_plots = html_plots[1:n_result_specs]
    input_html_plots = n_result_specs < length(html_plots) ? html_plots[(n_result_specs + 1):end] : NamedTuple[]
    _write_dashboard_html(dashboard_path, result_html_plots, input_html_plots)
    return dashboard_path
end

end # module OpenEMPIREResults
