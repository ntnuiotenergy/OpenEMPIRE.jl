function _dataset_folder(dataset::AbstractString)
    return isabspath(dataset) ? dataset : joinpath("data", dataset)
end

function _run_label(dataset::AbstractString)
    label = basename(normpath(dataset))
    return isempty(label) ? "dataset" : label
end

const _OOS_SCENARIO_FILENAMES = (
    "sloadRaw.csv",
    "maxRegHydroGenRaw.csv",
    "genCapAvailStochRaw.csv",
)

const _OOS_FIXED_INVESTMENT_FILENAMES = (
    ("genInvCap.csv",),
    ("transmissionInvCap.csv", "transmisionInvCap.csv"),
    ("storPWInvCap.csv",),
    ("storENInvCap.csv",),
    ("genInstalledCap.csv",),
    ("transmissionInstalledCap.csv",),
    ("storPWInstalledCap.csv",),
    ("storENInstalledCap.csv",),
)

function _scenario_data_dir(root::AbstractString)
    scenario_dir = joinpath(root, "ScenarioData")
    isdir(scenario_dir) || throw(ArgumentError(
        "--scenario-data-root must contain a ScenarioData directory: $root",
    ))

    missing = filter(_OOS_SCENARIO_FILENAMES) do filename
        !isfile(joinpath(scenario_dir, filename))
    end
    isempty(missing) || throw(ArgumentError(
        "ScenarioData is missing required OOS files: $(join(missing, ", "))",
    ))
    return scenario_dir
end

function _fixed_investment_output_dir(path::AbstractString)
    isdir(path) || throw(ArgumentError(
        "Fixed-investment directory does not exist: $path",
    ))
    for output_folder in ("Output", "output")
        output_dir = joinpath(path, output_folder)
        isdir(output_dir) && return output_dir
    end
    return path
end

function _fixed_investment_source_files(path::AbstractString)
    output_dir = _fixed_investment_output_dir(path)
    return map(_OOS_FIXED_INVESTMENT_FILENAMES) do aliases
        source_index = findfirst(
            filename -> isfile(joinpath(output_dir, filename)),
            aliases,
        )
        source_index === nothing && throw(ArgumentError(
            "Fixed-investment directory is missing one of: $(join(aliases, ", "))",
        ))
        joinpath(output_dir, aliases[source_index])
    end
end

function _stage_run_inputs(
    result_dir::AbstractString,
    data_folder::AbstractString,
    config_file::AbstractString;
    scenario_data_root::AbstractString = "",
    fixed_investment_dir::AbstractString = "",
)
    input_dir = joinpath(result_dir, "Input")
    staged_data = joinpath(input_dir, "csv")
    staged_config = joinpath(input_dir, "config.yaml")

    mkpath(input_dir)
    cp(data_folder, staged_data)
    cp(config_file, staged_config; force = true)

    if !isempty(scenario_data_root)
        source_scenario_dir = _scenario_data_dir(scenario_data_root)
        staged_scenario_dir = joinpath(staged_data, "ScenarioData")
        cp(source_scenario_dir, staged_scenario_dir; force = true)
    end

    staged_fixed_investment_dir = ""
    if !isempty(fixed_investment_dir)
        staged_fixed_investment_dir = joinpath(input_dir, "fixed_investments")
        mkpath(staged_fixed_investment_dir)
        for source in _fixed_investment_source_files(fixed_investment_dir)
            cp(
                source,
                joinpath(staged_fixed_investment_dir, basename(source));
                force = true,
            )
        end
    end

    return staged_data, staged_config, staged_fixed_investment_dir
end
