using SHA
using YAML

function _read_command(command::Cmd)
    try
        return String(strip(read(command, String)))
    catch
        return nothing
    end
end

function _git_info()
    status = _read_command(`git status --short`)
    return Dict{String, Any}(
        "branch" => _read_command(`git rev-parse --abbrev-ref HEAD`),
        "commit" => _read_command(`git rev-parse HEAD`),
        "dirty" => status === nothing ? nothing : !isempty(status),
    )
end

function _sha256_file(path::AbstractString)
    isfile(path) || return nothing
    open(path, "r") do io
        return bytes2hex(sha256(io))
    end
end

function _optimizer_attributes_manifest(attributes)
    return Dict{String, Any}(
        string(name) => value for (name, value) in attributes
    )
end

function _sampling_key_info(data_folder::AbstractString)
    path = joinpath(data_folder, "ScenarioData", "sampling_key.csv")
    return Dict{String, Any}(
        "path" => path,
        "exists" => isfile(path),
        "sha256" => _sha256_file(path),
    )
end

function _write_run_manifest(path::AbstractString, manifest)
    mkpath(dirname(path))
    YAML.write_file(path, manifest)
    return path
end
