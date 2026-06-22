using OpenEMPIRE

function main(args)
    result_dir = isempty(args) ? joinpath("results", "julia_runs", "repl_test") : first(args)
    input_dir = length(args) >= 2 ? args[2] : nothing
    dashboard_path = OpenEMPIRE.write_result_plots(result_dir; input_dir)
    println("Wrote result dashboard to: $dashboard_path")
end

main(ARGS)
