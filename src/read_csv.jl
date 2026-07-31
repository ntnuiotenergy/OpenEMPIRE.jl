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
    read_data(input; format=:auto, natural_gas=false,
              weather_scenarios=1, gas_scenarios=1)

Read EMPIRE input data from either a CSV dataset folder or an Excel dataset
folder. `format` can be `:auto`, `:csv`, or `:xlsx`.
"""
function read_data(
    input::AbstractString;
    format::Symbol = :auto,
    natural_gas::Bool = false,
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
)
    actual_format = format === :auto ? _detect_input_format(input) : format
    if actual_format === :csv
        return read_data_csv(
            input;
            natural_gas,
            weather_scenarios,
            gas_scenarios,
        )
    elseif actual_format === :xlsx
        natural_gas && throw(ArgumentError(
            "The natural-gas module requires the validated CSV dataset layout",
        ))
        return read_data_xlsx(input)
    end
    throw(ArgumentError("Unsupported input format: $format. Expected :auto, :csv, or :xlsx."))
end

function read_data(
    dataset::CsvDataset;
    format::Symbol = :csv,
    natural_gas::Bool = false,
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
)
    format in (:auto, :csv) ||
        throw(ArgumentError("CsvDataset can only be read with format :auto or :csv, got: $format"))
    return read_data_csv(
        dataset_path(dataset);
        natural_gas,
        weather_scenarios,
        gas_scenarios,
    )
end

function read_data(
    dataset::XlsxDataset;
    format::Symbol = :xlsx,
    natural_gas::Bool = false,
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
)
    format in (:auto, :xlsx) ||
        throw(ArgumentError("XlsxDataset can only be read with format :auto or :xlsx, got: $format"))
    natural_gas && throw(ArgumentError(
        "The natural-gas module requires the validated CSV dataset layout",
    ))
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
# Dispatch rather than `isempty(strip(string(x)))`: the generic form formats every
# cell into a String just to test emptiness, including every Float64 in the multi-
# million-cell scenario CSVs. A number is never blank, and a string needs no copy.
_is_blank(::Missing) = true
_is_blank(x::AbstractString) = isempty(strip(x))
_is_blank(::Real) = false
_is_blank(x) = isempty(strip(string(x)))
_string_cell(x) = strip(string(x))
_float_cell(x) = x isa Real ? Float64(x) : parse(Float64, strip(string(x)))
_int_cell(x) = x isa Integer ? Int(x) : parse(Int, strip(string(x)))

function _validated_module_rows(
    path::AbstractString,
    expected_headers::Tuple;
    alternate_headers::Tuple = (),
)
    try
        rows = collect(CSV.File(path; normalizenames = false, strict = true))
        isempty(rows) && throw(ArgumentError("Natural-gas CSV is empty: $path"))
        headers = Tuple(String.(propertynames(first(rows))))
        valid_headers = headers == expected_headers ||
            (!isempty(alternate_headers) && headers == alternate_headers)
        valid_headers || throw(ArgumentError(
            "Natural-gas CSV $path has headers $(collect(headers)); expected " *
            "$(collect(expected_headers))",
        ))
        return rows
    catch err
        err isa ArgumentError && rethrow()
        throw(ArgumentError("Failed to parse natural-gas CSV $path: $(sprint(showerror, err))"))
    end
end

function _module_string(path, row::Int, column::AbstractString, value)
    _is_blank(value) && throw(ArgumentError(
        "Malformed natural-gas CSV $path data row $row column $column: empty value",
    ))
    return _string_cell(value)
end

function _module_float(path, row::Int, column::AbstractString, value)
    _is_blank(value) && throw(ArgumentError(
        "Malformed natural-gas CSV $path data row $row column $column: empty value",
    ))
    parsed = try
        value isa Real ? Float64(value) : parse(Float64, strip(string(value)))
    catch
        throw(ArgumentError(
            "Malformed natural-gas CSV $path data row $row column $column: " *
            "expected a number, got $(repr(value))",
        ))
    end
    isfinite(parsed) || throw(ArgumentError(
        "Malformed natural-gas CSV $path data row $row column $column: " *
        "value must be finite, got $(repr(value))",
    ))
    return parsed
end

function _module_int(path, row::Int, column::AbstractString, value)
    parsed = _module_float(path, row, column, value)
    isinteger(parsed) || throw(ArgumentError(
        "Malformed natural-gas CSV $path data row $row column $column: " *
        "expected an integer, got $(repr(value))",
    ))
    try
        return Int(parsed)
    catch
        throw(ArgumentError(
            "Malformed natural-gas CSV $path data row $row column $column: " *
            "integer is out of range, got $(repr(value))",
        ))
    end
end

function _insert_unique_module_value!(values, key, value, path, row)
    haskey(values, key) && throw(ArgumentError(
        "Duplicate natural-gas key $key in $path at data row $row",
    ))
    values[key] = value
    return values
end

function _read_module_vector(path, header::AbstractString)
    rows = _validated_module_rows(path, (String(header),))
    values = String[]
    for (index, row) in enumerate(rows)
        push!(values, _module_string(path, index + 1, header, row[1]))
    end
    allunique(values) || throw(ArgumentError("Duplicate natural-gas value in $path"))
    return values
end

function _read_module_pairs(path, headers::Tuple{<:AbstractString, <:AbstractString})
    expected = (String(headers[1]), String(headers[2]))
    rows = _validated_module_rows(path, expected)
    values = Tuple{String, String}[]
    for (index, row) in enumerate(rows)
        push!(
            values,
            (
                _module_string(path, index + 1, headers[1], row[1]),
                _module_string(path, index + 1, headers[2], row[2]),
            ),
        )
    end
    allunique(values) || throw(ArgumentError("Duplicate natural-gas key in $path"))
    return values
end

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

"""
    _read_scalar_csv(path)

Read a single numeric value from a one-column CSV (header plus one data row).

Used for parameters the reference declares as a scalar `Param(initialize=...)` rather
than a per-period profile, such as the CCS fixed transport-and-storage cost.
"""
function _read_scalar_csv(path::AbstractString; value_col::Int = 1)
    for row in _csv_rows(path)
        _is_blank(row[value_col]) && continue
        return _float_cell(row[value_col])
    end
    throw(ArgumentError("No numeric value found in $path"))
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

function _read_natural_gas_sets_csv(
    dir::AbstractString,
    generators::AbstractVector{<:AbstractString},
)
    sets_dir = "Sets"
    gas_nodes = _read_module_vector(
        _required_csv(dir, sets_dir, "NaturalGasNodes.csv"),
        "NaturalGasNodes",
    )
    gas_links = _read_module_pairs(
        _required_csv(dir, sets_dir, "NaturalGasDirectionalLines.csv"),
        ("NodeFrom", "NodeTo"),
    )
    terminals = _read_module_vector(
        _required_csv(dir, sets_dir, "NaturalGasTerminals.csv"),
        "NaturalGasTerminals",
    )
    terminal_nodes = _read_module_pairs(
        _required_csv(dir, sets_dir, "NaturalGasTerminalsOfNode.csv"),
        ("Node", "NG_Terminal_Type"),
    )
    onshore_nodes = _read_module_vector(
        _required_csv(dir, sets_dir, "OnshoreNode.csv"),
        "OnshoreNode",
    )
    gas_generators = [generator for generator in generators
                      if occursin("gas", lowercase(generator))]
    return NaturalGasSets(
        Node = gas_nodes,
        DirectionalLink = gas_links,
        Terminal = terminals,
        TerminalsOfNode = terminal_nodes,
        OnshoreNode = onshore_nodes,
        Generator = gas_generators,
    )
end

"""
    read_sets_csv(dir)

Read EMPIRE sets from a CSV dataset folder using the Python/CSV dataset layout.
"""
function read_sets_csv(dir::AbstractString; natural_gas::Bool = false)
    @info "Reading CSV sets from $dir"

    sets_dir = "Sets"
    generators = _read_vector_csv(_required_csv(dir, sets_dir, "Generator.csv"))
    gas_sets = natural_gas ? _read_natural_gas_sets_csv(dir, generators) : NaturalGasSets()
    return OpenEMPIRE.EmpireSets(
        Generator = generators,
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
        NaturalGas = gas_sets,
    )
end

function _module_nonnegative(path, row, column, value)
    parsed = _module_float(path, row, column, value)
    parsed >= 0 || throw(ArgumentError(
        "Malformed natural-gas CSV $path data row $row column $column: " *
        "value must be non-negative, got $parsed",
    ))
    return parsed
end

function _read_natural_gas_params_csv(
    dir::AbstractString;
    weather_scenarios::Int,
    gas_scenarios::Int,
)
    weather_scenarios > 0 ||
        throw(ArgumentError("number_of_scenarios must be positive"))
    gas_scenarios > 0 ||
        throw(ArgumentError("number_of_gas_scenarios must be positive"))
    component = "NaturalGas"
    gas = NaturalGasParams(
        weatherScenarioCount = weather_scenarios,
        gasScenarioCount = gas_scenarios,
    )

    pipeline_path = _required_csv(dir, component, "PipelineCapacity.csv")
    for (index, row) in enumerate(_validated_module_rows(
        pipeline_path,
        ("FromNode", "ToNode", "Capacity_(ton/h)"),
    ))
        row_number = index + 1
        key = (
            _module_string(pipeline_path, row_number, "FromNode", row[1]),
            _module_string(pipeline_path, row_number, "ToNode", row[2]),
        )
        value = _module_nonnegative(
            pipeline_path,
            row_number,
            "Capacity_(ton/h)",
            row[3],
        )
        _insert_unique_module_value!(
            gas.pipelineCapacity,
            key,
            value,
            pipeline_path,
            row_number,
        )
    end

    power_path = _required_csv(dir, component, "PipelineElectricityUse.csv")
    power_rows = _validated_module_rows(power_path, ("Power_usage_[MWh/ton]",))
    length(power_rows) == 1 || throw(ArgumentError(
        "Natural-gas scalar CSV $power_path must contain exactly one data row",
    ))
    gas.pipelinePowerDemandPerTon = _module_nonnegative(
        power_path,
        2,
        "Power_usage_[MWh/ton]",
        only(power_rows)[1],
    )

    for (filename, header, target) in (
        ("StorageCapacity.csv", "Storage_(ton)", gas.storageCapacity),
        ("Reserves.csv", "Reserves_(tons)", gas.reserves),
    )
        path = _required_csv(dir, component, filename)
        for (index, row) in enumerate(_validated_module_rows(path, ("Node", header)))
            row_number = index + 1
            key = _module_string(path, row_number, "Node", row[1])
            value = _module_nonnegative(path, row_number, header, row[2])
            _insert_unique_module_value!(target, key, value, path, row_number)
        end
    end

    capacity_path = _required_csv(dir, component, "TerminalCapacity.csv")
    for (index, row) in enumerate(_validated_module_rows(
        capacity_path,
        ("Node", "Terminal", "Period", "Capacity_(ton/hr)"),
    ))
        row_number = index + 1
        period = _module_int(capacity_path, row_number, "Period", row[3])
        period > 0 || throw(ArgumentError(
            "Malformed natural-gas CSV $capacity_path data row $row_number " *
            "column Period: value must be positive",
        ))
        key = (
            _module_string(capacity_path, row_number, "Node", row[1]),
            _module_string(capacity_path, row_number, "Terminal", row[2]),
            period,
        )
        value = _module_nonnegative(
            capacity_path,
            row_number,
            "Capacity_(ton/hr)",
            row[4],
        )
        _insert_unique_module_value!(
            gas.terminalCapacity,
            key,
            value,
            capacity_path,
            row_number,
        )
    end

    cost_filename = gas_scenarios == 1 ?
                    "TerminalCost.csv" : "TerminalCost_stochastic.csv"
    cost_path = _required_csv(dir, component, cost_filename)
    for (index, row) in enumerate(_validated_module_rows(
        cost_path,
        ("Node", "Terminal", "Period", "GasScenario", "Cost_(EUR/ton)");
        alternate_headers =
            ("Node", "Terminal", "Period", "Scenario", "Cost_(EUR/ton)"),
    ))
        row_number = index + 1
        period = _module_int(cost_path, row_number, "Period", row[3])
        gas_scenario = _module_int(cost_path, row_number, "GasScenario", row[4])
        period > 0 || throw(ArgumentError(
            "Malformed natural-gas CSV $cost_path data row $row_number " *
            "column Period: value must be positive",
        ))
        gas_scenario > 0 || throw(ArgumentError(
            "Malformed natural-gas CSV $cost_path data row $row_number " *
            "column GasScenario: value must be positive",
        ))
        key = (
            _module_string(cost_path, row_number, "Node", row[1]),
            _module_string(cost_path, row_number, "Terminal", row[2]),
            period,
            gas_scenario,
        )
        value = _module_nonnegative(
            cost_path,
            row_number,
            "Cost_(EUR/ton)",
            row[5],
        )
        _insert_unique_module_value!(
            gas.terminalCost,
            key,
            value,
            cost_path,
            row_number,
        )
    end

    demand_path = _required_csv(dir, "Transport", "NaturalGasDemand.csv")
    for (index, row) in enumerate(_validated_module_rows(
        demand_path,
        ("Node", "Period", "Natural_gas_demand_[MWh/yr]"),
    ))
        row_number = index + 1
        period = _module_int(demand_path, row_number, "Period", row[2])
        period > 0 || throw(ArgumentError(
            "Malformed natural-gas CSV $demand_path data row $row_number " *
            "column Period: value must be positive",
        ))
        key = (
            _module_string(demand_path, row_number, "Node", row[1]),
            period,
        )
        value = _module_nonnegative(
            demand_path,
            row_number,
            "Natural_gas_demand_[MWh/yr]",
            row[3],
        )
        _insert_unique_module_value!(
            gas.transportDemand,
            key,
            value,
            demand_path,
            row_number,
        )
    end

    curtail_path = _required_csv(dir, "Transport", "CurtailCost.csv")
    curtail_rows = _validated_module_rows(curtail_path, ("CurtailCost_(€/MWh)",))
    length(curtail_rows) == 1 || throw(ArgumentError(
        "Natural-gas scalar CSV $curtail_path must contain exactly one data row",
    ))
    gas.transportCurtailCost = _module_nonnegative(
        curtail_path,
        2,
        "CurtailCost_(€/MWh)",
        only(curtail_rows)[1],
    )
    return gas
end

"""
    read_params_csv(dir)

Read EMPIRE parameters from a CSV dataset folder using the Python/CSV dataset
layout. Extra source/unit columns are ignored; files are parsed by position.
"""
function read_params_csv(
    dir::AbstractString;
    natural_gas::Bool = false,
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
)
    @info "Reading CSV parameters from $dir"

    par = OpenEMPIRE.EmpireParams()

    generator = "Generator"
    par.genCapitalCost = _read_strategic_profiles_csv(_required_csv(dir, generator, "genCapitalCost.csv"))
    par.genFixedOMCost = _read_strategic_profiles_csv(_required_csv(dir, generator, "genFixedOMCost.csv"))
    par.genVariableOMCost = _read_float_by_string_csv(_required_csv(dir, generator, "genVariableOMCost.csv"))
    par.genFuelCost = _read_strategic_profiles_csv(_required_csv(dir, generator, "genFuelCost.csv"))
    par.CCSCostTSVariable = _read_strategic_profile_csv(_required_csv(dir, generator, "CCSCostTSVariable.csv"))
    ccs_fixed_path = _optional_csv(dir, generator, "CCSCostTSFixed.csv")
    if ccs_fixed_path !== nothing
        par.CCSCostTSFixed = _read_scalar_csv(ccs_fixed_path)
    end
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
    if natural_gas
        par.NaturalGas = _read_natural_gas_params_csv(
            dir;
            weather_scenarios,
            gas_scenarios,
        )
    end

    return par
end

"""
    read_data_csv(dir)

Read sets and parameters from a CSV EMPIRE dataset folder.
"""
function read_data_csv(
    dir::AbstractString;
    natural_gas::Bool = false,
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
)
    sets = read_sets_csv(dir; natural_gas)
    par = read_params_csv(dir; natural_gas, weather_scenarios, gas_scenarios)
    return (sets, par)
end
