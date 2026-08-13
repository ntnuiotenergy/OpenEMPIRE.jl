function _dataset_folder(dataset::AbstractString)
    return isabspath(dataset) ? dataset : joinpath("data", dataset)
end

function _run_label(dataset::AbstractString)
    label = basename(normpath(dataset))
    return isempty(label) ? "dataset" : label
end

function _stage_run_inputs(
    result_dir::AbstractString,
    data_folder::AbstractString,
    config_file::AbstractString,
)
    input_dir = joinpath(result_dir, "Input")
    staged_data = joinpath(input_dir, "csv")
    staged_config = joinpath(input_dir, "config.yaml")

    mkpath(input_dir)
    cp(data_folder, staged_data)
    cp(config_file, staged_config; force = true)

    return staged_data, staged_config
end
