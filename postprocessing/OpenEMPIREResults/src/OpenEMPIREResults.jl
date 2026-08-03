module OpenEMPIREResults

using CSV

export write_result_plots

include("constants.jl")
include("data_utils.jl")
include("plotly.jl")
include("maps.jl")
include("specs.jl")

"""
    _resolve_output_dir(result_dir)

Locate a run's result-CSV directory, accepting either capitalisation.

`scripts/run_julia_empire.jl` writes `<run>/output` while the Python reference and
this package's default both say `Output`. That difference is invisible on Windows
and macOS but fatal on Solstorm, where the runs are actually produced.
"""
function _resolve_output_dir(result_dir::AbstractString)
    for candidate in ("Output", "output")
        path = joinpath(result_dir, candidate)
        isdir(path) && return path
    end
    return joinpath(result_dir, "Output")
end

"""
    write_result_plots(result_dir; output_dir, plot_dir, input_dir, plotly_js)

Create a small HTML dashboard from the result CSV files.

`output_dir` defaults to whichever of `<result_dir>/Output` or `<result_dir>/output`
exists. Pass `plotly_js` a path to a `plotly.min.js` to vendor the library next to
the generated pages so they render without network access; otherwise pages load it
from the CDN and show an explanatory banner if that fails.
"""
function write_result_plots(
        result_dir::AbstractString;
        output_dir::AbstractString = _resolve_output_dir(result_dir),
        plot_dir::AbstractString = joinpath(result_dir, "Plots"),
        input_dir::Union{Nothing, AbstractString} = nothing,
        plotly_js::Union{Nothing, AbstractString} = nothing,
    )
    isdir(output_dir) || throw(ArgumentError("No result output directory found at $output_dir"))
    mkpath(plot_dir)

    if plotly_js !== nothing
        isfile(plotly_js) || throw(ArgumentError("plotly_js is not a file: $plotly_js"))
        cp(plotly_js, joinpath(plot_dir, PLOTLY_VENDOR_FILENAME); force = true)
    end

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
