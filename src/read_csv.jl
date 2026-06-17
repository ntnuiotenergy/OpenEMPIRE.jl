abstract type AbstractEmpireDataset end

"""
    CsvDataset(root, name)

Reference a CSV EMPIRE dataset stored as `root/name`, with component
subdirectories such as `Sets`, `Generator`, `Transmission`, and `ScenarioData`.
"""
struct CsvDataset{P <: AbstractString, N <: AbstractString} <: AbstractEmpireDataset
    root::P
    name::N
end

"""
    XlsxDataset(path)

Reference an Excel EMPIRE dataset folder containing files such as `Sets.xlsx`,
`Generator.xlsx`, and `Transmission.xlsx`.
"""
struct XlsxDataset{P <: AbstractString} <: AbstractEmpireDataset
    path::P
end

const CSV_DATASET_COMPONENTS = (
    "Sets",
    "Generator",
    "Transmission",
    "Storage",
    "Node",
    "General",
    "ScenarioData",
)

dataset_path(dataset::CsvDataset) = joinpath(dataset.root, dataset.name)
dataset_path(dataset::XlsxDataset) = dataset.path
dataset_path(name::AbstractString; root::AbstractString = default_input_data_root()) = joinpath(root, name)
input_path(dataset::AbstractEmpireDataset) = dataset_path(dataset)
input_path(path::AbstractString) = path
default_input_data_root() = joinpath(pkgdir(OpenEMPIRE), "data")

"""
    available_datasets(; root=joinpath(pkgdir(OpenEMPIRE), "data"))

Return dataset names under `root` that look like CSV EMPIRE datasets.
"""
function available_datasets(; root::AbstractString = default_input_data_root())
    isdir(root) || return String[]
    names = String[]
    for name in readdir(root)
        path = joinpath(root, name)
        _is_csv_dataset(path) && push!(names, name)
    end
    return sort(names)
end

"""
    read_data(input; format=:auto)

Read EMPIRE input data from either a CSV dataset folder or an Excel dataset
folder. `format` can be `:auto`, `:csv`, or `:xlsx`.
"""
function read_data(input::AbstractString; format::Symbol = :auto)
    actual_format = format === :auto ? _detect_input_format(input) : format
    if actual_format === :csv
        return read_data_csv(input)
    elseif actual_format === :xlsx
        return read_data_xlsx(input)
    end
    throw(ArgumentError("Unsupported input format: $format. Expected :auto, :csv, or :xlsx."))
end

function read_data(dataset::CsvDataset; format::Symbol = :csv)
    format in (:auto, :csv) ||
        throw(ArgumentError("CsvDataset can only be read with format :auto or :csv, got: $format"))
    return read_data_csv(dataset_path(dataset))
end

function read_data(dataset::XlsxDataset; format::Symbol = :xlsx)
    format in (:auto, :xlsx) ||
        throw(ArgumentError("XlsxDataset can only be read with format :auto or :xlsx, got: $format"))
    return read_data_xlsx(dataset_path(dataset))
end

function _is_csv_dataset(path::AbstractString)
    return isdir(path) && all(component -> isdir(joinpath(path, component)), CSV_DATASET_COMPONENTS)
end

function _detect_input_format(path::AbstractString)
    _is_csv_dataset(path) && return :csv
    isfile(joinpath(path, "Sets.xlsx")) && return :xlsx
    throw(ArgumentError("Could not detect EMPIRE input format for: $path"))
end

function _required_csv(dir::AbstractString, component::AbstractString, filename::AbstractString)
    path = joinpath(dir, component, filename)
    isfile(path) || throw(ArgumentError("Required CSV input file not found: $path"))
    return path
end

_csv_rows(path::AbstractString) = CSV.File(path; normalizenames = false)
_is_blank(x) = ismissing(x) || isempty(strip(string(x)))
_string_cell(x) = strip(string(x))
_float_cell(x) = x isa Real ? Float64(x) : parse(Float64, strip(string(x)))
_int_cell(x) = x isa Integer ? Int(x) : parse(Int, strip(string(x)))

function _read_vector_csv(path::AbstractString; col::Int = 1)
    values = String[]
    for row in _csv_rows(path)
        _is_blank(row[col]) && continue
        push!(values, _string_cell(row[col]))
    end
    return values
end

function _read_tuple2_csv(path::AbstractString; cols::Tuple{Int, Int} = (1, 2))
    values = Tuple{String, String}[]
    for row in _csv_rows(path)
        (_is_blank(row[cols[1]]) || _is_blank(row[cols[2]])) && continue
        push!(values, (_string_cell(row[cols[1]]), _string_cell(row[cols[2]])))
    end
    return values
end

function _read_tuple3_csv(path::AbstractString; cols::Tuple{Int, Int, Int} = (1, 2, 3))
    values = Tuple{String, String, String}[]
    for row in _csv_rows(path)
        if _is_blank(row[cols[1]]) || _is_blank(row[cols[2]]) || _is_blank(row[cols[3]])
            continue
        end
        push!(
            values,
            (_string_cell(row[cols[1]]), _string_cell(row[cols[2]]), _string_cell(row[cols[3]])),
        )
    end
    return values
end

function _read_float_by_string_csv(path::AbstractString; key_col::Int = 1, value_col::Int = 2)
    values = Dict{String, Float64}()
    for row in _csv_rows(path)
        _is_blank(row[key_col]) && continue
        values[_string_cell(row[key_col])] = _float_cell(row[value_col])
    end
    return values
end

function _read_float_by_pair_csv(
        path::AbstractString;
        key_cols::Tuple{Int, Int} = (1, 2),
        value_col::Int = 3,
    )
    values = Dict{Tuple{String, String}, Float64}()
    for row in _csv_rows(path)
        (_is_blank(row[key_cols[1]]) || _is_blank(row[key_cols[2]])) && continue
        key = (_string_cell(row[key_cols[1]]), _string_cell(row[key_cols[2]]))
        values[key] = _float_cell(row[value_col])
    end
    return values
end

function _read_strategic_profiles_csv(
        path::AbstractString;
        key_col::Int = 1,
        period_col::Int = 2,
        value_col::Int = 3,
        default_value::Float64 = 0.0,
    )
    by_key = Dict{String, Dict{Int, Float64}}()
    max_period = 0
    for row in _csv_rows(path)
        _is_blank(row[key_col]) && continue
        key = _string_cell(row[key_col])
        period = _int_cell(row[period_col])
        max_period = max(max_period, period)
        get!(by_key, key, Dict{Int, Float64}())[period] = _float_cell(row[value_col])
    end

    profiles = Dict{String, TimeProfile}()
    for (key, values) in by_key
        fixed = FixedProfile[]
        for period in 1:max_period
            push!(fixed, FixedProfile(get(values, period, default_value)))
        end
        profiles[key] = StrategicProfile(fixed)
    end
    return profiles
end

function _read_strategic_profiles_pair_csv(
        path::AbstractString;
        key_cols::Tuple{Int, Int} = (1, 2),
        period_col::Int = 3,
        value_col::Int = 4,
        default_value::Float64 = 0.0,
    )
    by_key = Dict{Tuple{String, String}, Dict{Int, Float64}}()
    max_period = 0
    for row in _csv_rows(path)
        (_is_blank(row[key_cols[1]]) || _is_blank(row[key_cols[2]])) && continue
        key = (_string_cell(row[key_cols[1]]), _string_cell(row[key_cols[2]]))
        period = _int_cell(row[period_col])
        max_period = max(max_period, period)
        get!(by_key, key, Dict{Int, Float64}())[period] = _float_cell(row[value_col])
    end

    profiles = Dict{Tuple{String, String}, TimeProfile}()
    for (key, values) in by_key
        fixed = FixedProfile[]
        for period in 1:max_period
            push!(fixed, FixedProfile(get(values, period, default_value)))
        end
        profiles[key] = StrategicProfile(fixed)
    end
    return profiles
end

function _read_strategic_profile_csv(
        path::AbstractString;
        period_col::Int = 1,
        value_col::Int = 2,
        default_value::Float64 = 0.0,
    )
    values = Dict{Int, Float64}()
    max_period = 0
    for row in _csv_rows(path)
        _is_blank(row[period_col]) && continue
        period = _int_cell(row[period_col])
        max_period = max(max_period, period)
        values[period] = _float_cell(row[value_col])
    end

    fixed = FixedProfile[]
    for period in 1:max_period
        push!(fixed, FixedProfile(get(values, period, default_value)))
    end
    return StrategicProfile(fixed)
end

"""
    read_sets_csv(dir)

Read EMPIRE sets from a CSV dataset folder using the Python/CSV dataset layout.
"""
function read_sets_csv(dir::AbstractString)
    @info "Reading CSV sets from $dir"

    sets_dir = "Sets"
    return OpenEMPIRE.EmpireSets(
        Generator = _read_vector_csv(_required_csv(dir, sets_dir, "Generator.csv")),
        ThermalGenerators = _read_vector_csv(_required_csv(dir, sets_dir, "ThermalGenerators.csv")),
        HydroGenerator = _read_vector_csv(_required_csv(dir, sets_dir, "HydroGenerator.csv")),
        RegHydroGenerator = _read_vector_csv(_required_csv(dir, sets_dir, "RegHydroGenerator.csv")),
        Storage = _read_vector_csv(_required_csv(dir, sets_dir, "Storage.csv")),
        DependentStorage = _read_vector_csv(_required_csv(dir, sets_dir, "DependentStorage.csv")),
        Technology = _read_vector_csv(_required_csv(dir, sets_dir, "Technology.csv")),
        Node = _read_vector_csv(_required_csv(dir, sets_dir, "Node.csv")),
        DirectionalLink = _read_tuple2_csv(_required_csv(dir, sets_dir, "DirectionalLink.csv")),
        TransmissionType = _read_vector_csv(_required_csv(dir, sets_dir, "TransmissionType.csv")),
        TransmissionTypeOfDirectionalLink =
            _read_tuple3_csv(_required_csv(dir, sets_dir, "TransmissionTypeOfDirectionalLink.csv")),
        GeneratorsOfTechnology = _read_tuple2_csv(_required_csv(dir, sets_dir, "GeneratorsOfTechnology.csv")),
        GeneratorsOfNode = _read_tuple2_csv(_required_csv(dir, sets_dir, "GeneratorsOfNode.csv")),
        StoragesOfNode = _read_tuple2_csv(_required_csv(dir, sets_dir, "StoragesOfNode.csv")),
    )
end

"""
    read_params_csv(dir)

Read EMPIRE parameters from a CSV dataset folder using the Python/CSV dataset
layout. Extra source/unit columns are ignored; files are parsed by position.
"""
function read_params_csv(dir::AbstractString)
    @info "Reading CSV parameters from $dir"

    par = OpenEMPIRE.EmpireParams()

    generator = "Generator"
    par.genCapitalCost = _read_strategic_profiles_csv(_required_csv(dir, generator, "genCapitalCost.csv"))
    par.genFixedOMCost = _read_strategic_profiles_csv(_required_csv(dir, generator, "genFixedOMCost.csv"))
    par.genVariableOMCost = _read_float_by_string_csv(_required_csv(dir, generator, "genVariableOMCost.csv"))
    par.genFuelCost = _read_strategic_profiles_csv(_required_csv(dir, generator, "genFuelCost.csv"))
    par.CCSCostTSVariable = _read_strategic_profile_csv(_required_csv(dir, generator, "CCSCostTSVariable.csv"))
    par.genEfficiency = _read_strategic_profiles_csv(_required_csv(dir, generator, "genEfficiency.csv"))
    par.genRefInitCap = _read_float_by_pair_csv(_required_csv(dir, generator, "genRefInitCap.csv"))
    par.genScaleInitCap = _read_strategic_profiles_csv(_required_csv(dir, generator, "genScaleInitCap.csv"))
    par.genInitCap = _read_strategic_profiles_pair_csv(_required_csv(dir, generator, "genInitCap.csv"))
    par.genMaxBuiltCap = _read_strategic_profiles_pair_csv(_required_csv(dir, generator, "genMaxBuiltCap.csv"))
    par.genMaxInstalledCapRaw =
        _read_float_by_pair_csv(_required_csv(dir, generator, "genMaxInstalledCapRaw.csv"))
    par.genRampUpCap = _read_float_by_string_csv(_required_csv(dir, generator, "genRampUpCap.csv"))
    par.genCapAvailType = _read_float_by_string_csv(_required_csv(dir, generator, "genCapAvailTypeRaw.csv"))
    par.genCO2Content = _read_float_by_string_csv(_required_csv(dir, generator, "genCO2TypeFactor.csv"))
    par.genLifetime = _read_float_by_string_csv(_required_csv(dir, generator, "genLifetime.csv"))

    transmission = "Transmission"
    par.transmissionInitCap =
        _read_strategic_profiles_pair_csv(_required_csv(dir, transmission, "transmissionInitCap.csv"))
    par.transmissionMaxBuiltCap =
        _read_strategic_profiles_pair_csv(_required_csv(dir, transmission, "transmissionMaxBuiltCap.csv"))
    par.transmissionMaxInstalledCap =
        _read_strategic_profiles_pair_csv(_required_csv(dir, transmission, "transmissionMaxInstalledCapRaw.csv"))
    par.transmissionLength =
        _read_float_by_pair_csv(_required_csv(dir, transmission, "transmissionLength.csv"))
    par.transmissionTypeCapitalCost =
        _read_strategic_profiles_csv(_required_csv(dir, transmission, "transmissionTypeCapitalCost.csv"))
    par.transmissionTypeFixedOMCost =
        _read_strategic_profiles_csv(_required_csv(dir, transmission, "transmissionTypeFixedOMCost.csv"))
    par.lineEfficiency = _read_float_by_pair_csv(_required_csv(dir, transmission, "lineEfficiency.csv"))
    par.transmissionLifetime =
        _read_float_by_pair_csv(_required_csv(dir, transmission, "transmissionLifetime.csv"))

    storage = "Storage"
    par.storageBleedEff = _read_float_by_string_csv(_required_csv(dir, storage, "storageBleedEff.csv"))
    par.storageChargeEff = _read_float_by_string_csv(_required_csv(dir, storage, "storageChargeEff.csv"))
    par.storageDischargeEff = _read_float_by_string_csv(_required_csv(dir, storage, "storageDischargeEff.csv"))
    par.storagePowToEnergy = _read_float_by_string_csv(_required_csv(dir, storage, "storagePowToEnergy.csv"))
    par.storENCapitalCost = _read_strategic_profiles_csv(_required_csv(dir, storage, "storENCapitalCost.csv"))
    par.storENFixedOMCost = _read_strategic_profiles_csv(_required_csv(dir, storage, "storENFixedOMCost.csv"))
    par.storENInitCap = _read_strategic_profiles_pair_csv(_required_csv(dir, storage, "storENInitCap.csv"))
    par.storENMaxBuiltCap = _read_strategic_profiles_pair_csv(_required_csv(dir, storage, "storENMaxBuiltCap.csv"))
    par.storENMaxInstalledCap =
        _read_float_by_pair_csv(_required_csv(dir, storage, "storENMaxInstalledCapRaw.csv"))
    par.storOperationalInit =
        _read_float_by_string_csv(_required_csv(dir, storage, "storOperationalInit.csv"))
    par.storPWCapitalCost = _read_strategic_profiles_csv(_required_csv(dir, storage, "storPWCapitalCost.csv"))
    par.storPWFixedOMCost = _read_strategic_profiles_csv(_required_csv(dir, storage, "storPWFixedOMCost.csv"))
    par.storPWInitCap = _read_strategic_profiles_pair_csv(_required_csv(dir, storage, "storPWInitCap.csv"))
    par.storPWMaxBuiltCap = _read_strategic_profiles_pair_csv(_required_csv(dir, storage, "storPWMaxBuiltCap.csv"))
    par.storPWMaxInstalledCap =
        _read_float_by_pair_csv(_required_csv(dir, storage, "storPWMaxInstalledCapRaw.csv"))
    par.storageLifetime = _read_float_by_string_csv(_required_csv(dir, storage, "storageLifetime.csv"))

    node = "Node"
    par.nodeLostLoadCost = _read_strategic_profiles_csv(_required_csv(dir, node, "nodeLostLoadCost.csv"))
    par.sloadAnnualDemand = _read_strategic_profiles_csv(_required_csv(dir, node, "sloadAnnualDemand.csv"))
    par.maxHydroNode = _read_float_by_string_csv(_required_csv(dir, node, "maxHydroNode.csv"))

    general = "General"
    par.CO2cap = _read_strategic_profile_csv(_required_csv(dir, general, "CO2cap.csv"))
    par.CO2price = _read_strategic_profile_csv(_required_csv(dir, general, "CO2price.csv"))
    par.seasScale = _read_float_by_string_csv(_required_csv(dir, general, "seasScale.csv"))

    return par
end

"""
    read_data_csv(dir)

Read sets and parameters from a CSV EMPIRE dataset folder.
"""
function read_data_csv(dir::AbstractString)
    sets = read_sets_csv(dir)
    par = read_params_csv(dir)
    return (sets, par)
end
