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
    hydrogen::Bool = false,
    industry::Bool = false,
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
)
    hydrogen && !natural_gas && throw(ArgumentError(
        "hydrogen=true requires natural_gas=true",
    ))
    hydrogen && gas_scenarios != 1 && throw(ArgumentError(
        "Deterministic Hydrogen requires number_of_gas_scenarios=1",
    ))
    industry && !natural_gas && throw(ArgumentError(
        "industry=true requires natural_gas=true",
    ))
    industry && gas_scenarios != 1 && throw(ArgumentError(
        "Deterministic Industry requires number_of_gas_scenarios=1",
    ))
    actual_format = format === :auto ? _detect_input_format(input) : format
    if actual_format === :csv
        return read_data_csv(
            input;
            natural_gas,
            hydrogen,
            industry,
            weather_scenarios,
            gas_scenarios,
        )
    elseif actual_format === :xlsx
        (natural_gas || hydrogen || industry) && throw(ArgumentError(
            "The natural-gas, Hydrogen, and Industry modules require the validated CSV dataset layout",
        ))
        return read_data_xlsx(input)
    end
    throw(ArgumentError("Unsupported input format: $format. Expected :auto, :csv, or :xlsx."))
end

function read_data(
    dataset::CsvDataset;
    format::Symbol = :csv,
    natural_gas::Bool = false,
    hydrogen::Bool = false,
    industry::Bool = false,
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
)
    format in (:auto, :csv) ||
        throw(ArgumentError("CsvDataset can only be read with format :auto or :csv, got: $format"))
    return read_data_csv(
        dataset_path(dataset);
        natural_gas,
        hydrogen,
        industry,
        weather_scenarios,
        gas_scenarios,
    )
end

function read_data(
    dataset::XlsxDataset;
    format::Symbol = :xlsx,
    natural_gas::Bool = false,
    hydrogen::Bool = false,
    industry::Bool = false,
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
)
    format in (:auto, :xlsx) ||
        throw(ArgumentError("XlsxDataset can only be read with format :auto or :xlsx, got: $format"))
    (natural_gas || hydrogen || industry) && throw(ArgumentError(
        "The natural-gas, Hydrogen, and Industry modules require the validated CSV dataset layout",
    ))
    return read_data_xlsx(dataset_path(dataset))
end

function _validated_sector_rows(
    path::AbstractString,
    expected_headers::Tuple,
    sector::AbstractString,
)
    try
        rows = collect(CSV.File(path; normalizenames = false, strict = true))
        isempty(rows) && throw(ArgumentError("$sector CSV is empty: $path"))
        headers = Tuple(String.(propertynames(first(rows))))
        headers == expected_headers || throw(ArgumentError(
            "$sector CSV $path has headers $(collect(headers)); expected " *
            "$(collect(expected_headers))",
        ))
        return rows
    catch err
        err isa ArgumentError && rethrow()
        throw(ArgumentError("Failed to parse $sector CSV $path: $(sprint(showerror, err))"))
    end
end

function _sector_string(path, row::Int, column::AbstractString, value, sector::AbstractString)
    _is_blank(value) && throw(ArgumentError(
        "Malformed $sector CSV $path data row $row column $column: empty value",
    ))
    return _string_cell(value)
end

function _sector_float(path, row::Int, column::AbstractString, value, sector::AbstractString)
    _is_blank(value) && throw(ArgumentError(
        "Malformed $sector CSV $path data row $row column $column: empty value",
    ))
    parsed = try
        value isa Real ? Float64(value) : parse(Float64, strip(string(value)))
    catch
        throw(ArgumentError(
            "Malformed $sector CSV $path data row $row column $column: " *
            "expected a number, got $(repr(value))",
        ))
    end
    isfinite(parsed) || throw(ArgumentError(
        "Malformed $sector CSV $path data row $row column $column: value must be finite",
    ))
    return parsed
end

function _sector_nonnegative(path, row, column, value, sector)
    parsed = _sector_float(path, row, column, value, sector)
    parsed >= 0 || throw(ArgumentError(
        "Malformed $sector CSV $path data row $row column $column: " *
        "value must be non-negative, got $parsed",
    ))
    return parsed
end

function _sector_period(path, row, column, value, sector)
    parsed = _sector_float(path, row, column, value, sector)
    isinteger(parsed) || throw(ArgumentError(
        "Malformed $sector CSV $path data row $row column $column: expected an integer",
    ))
    period = try
        Int(parsed)
    catch
        throw(ArgumentError(
            "Malformed $sector CSV $path data row $row column $column: integer is out of range",
        ))
    end
    period > 0 || throw(ArgumentError(
        "Malformed $sector CSV $path data row $row column $column: value must be positive",
    ))
    return period
end

function _insert_unique_sector!(values, key, value, path, row, sector)
    haskey(values, key) && throw(ArgumentError(
        "Duplicate $sector key $key in $path at data row $row",
    ))
    values[key] = value
    return values
end

function _read_sector_vector(path, header, sector)
    rows = _validated_sector_rows(path, (String(header),), sector)
    values = String[
        _sector_string(path, index + 1, header, row[1], sector)
        for (index, row) in enumerate(rows)
    ]
    allunique(values) || throw(ArgumentError("Duplicate $sector value in $path"))
    return values
end

function _read_hydrogen_sets_csv(dir, generators, links, gas_sets)
    component = "Hydrogen"
    production_nodes = _read_sector_vector(
        _required_csv(dir, component, "ProductionNodes.csv"), "ProductionNodes", component,
    )
    generator_path = _required_csv(dir, component, "HydrogenGenerators.csv")
    hydrogen_generators = _read_sector_vector(generator_path, "HydrogenGenerator", component)
    derived_generators = sort([g for g in generators if occursin("hydrogen", lowercase(g))])
    sort(hydrogen_generators) == derived_generators || throw(ArgumentError(
        "Hydrogen generator CSV $generator_path does not match the case-insensitive " *
        "generator-name rule; file=$(sort(hydrogen_generators)), derived=$derived_generators",
    ))
    terminal_pairs_path = _required_csv(dir, component, "H2TerminalsOfNode.csv")
    terminal_pair_rows = _validated_sector_rows(
        terminal_pairs_path, ("H2TerminalNodes", "H2Terminals"), component,
    )
    terminal_pairs = Tuple{String, String}[]
    for (index, row) in enumerate(terminal_pair_rows)
        push!(terminal_pairs, (
            _sector_string(terminal_pairs_path, index + 1, "H2TerminalNodes", row[1], component),
            _sector_string(terminal_pairs_path, index + 1, "H2Terminals", row[2], component),
        ))
    end
    allunique(terminal_pairs) || throw(ArgumentError("Duplicate Hydrogen key in $terminal_pairs_path"))
    production_set = Set(production_nodes)
    hydrogen_links = Arc[(from, to) for (from, to) in links
                         if from in production_set && to in production_set]
    hydrogen_corridors = Set(Arc[minmax(from, to) for (from, to) in hydrogen_links])
    repurposable_links = Arc[
        (from, to) for (from, to) in gas_sets.DirectionalLink
        if minmax(from, to) in hydrogen_corridors
    ]
    onshore = gas_sets.OnshoreNode
    co2_links = Arc[(from, to) for (from, to) in links if from in onshore && to in onshore]
    storage_capacity_path = _required_csv(dir, component, "StorageMaxCapacity.csv")
    storage_capacity = _read_sector_pair_values(
        storage_capacity_path,
        ("Node", "H2Storage", "Max_capacity_[ton]"),
        component,
    )
    return HydrogenSets(
        ProductionNode = production_nodes,
        Generator = hydrogen_generators,
        ReformerLocation = _read_sector_vector(
            _required_csv(dir, component, "ReformerLocations.csv"), "ReformerLocations", component,
        ),
        ReformerPlant = _read_sector_vector(
            _required_csv(dir, component, "ReformerPlants.csv"), "ReformerPlants", component,
        ),
        Storage = _read_sector_vector(
            _required_csv(dir, component, "H2Storages.csv"), "H2Storages", component,
        ),
        StoragesOfNode = collect(keys(storage_capacity)),
        TerminalNode = _read_sector_vector(
            _required_csv(dir, component, "H2TerminalNodes.csv"), "H2TerminalNodes", component,
        ),
        Terminal = _read_sector_vector(
            _required_csv(dir, component, "H2Terminals.csv"), "H2Terminals", component,
        ),
        TerminalsOfNode = terminal_pairs,
        CO2SequestrationNode = _read_sector_vector(
            _required_csv(dir, "CO2", "CO2SequestrationNodes.csv"),
            "CO2SequestrationNodes", "CO2",
        ),
        DirectionalLink = hydrogen_links,
        CO2DirectionalLink = co2_links,
        RepurposableGasCorridor = repurposable_links,
    )
end

function _read_industry_sets_csv(dir; hydrogen::Bool)
    component = "Industry"
    sets_component = "Sets"
    return IndustrySets(
        SteelProducer = _read_sector_vector(
            _required_csv(dir, sets_component, "SteelProducers.csv"),
            "SteelProducers", component,
        ),
        CementProducer = _read_sector_vector(
            _required_csv(dir, sets_component, "CementProducers.csv"),
            "CementProducers", component,
        ),
        AmmoniaProducer = _read_sector_vector(
            _required_csv(dir, sets_component, "AmmoniaProducers.csv"),
            "AmmoniaProducers", component,
        ),
        OilProducer = _read_sector_vector(
            _required_csv(dir, sets_component, "OilProducers.csv"),
            "OilProducers", component,
        ),
        SteelPlant = _read_sector_vector(
            _required_csv(dir, component, "SteelPlants.csv"), "SteelPlants", component,
        ),
        CementPlant = _read_sector_vector(
            _required_csv(dir, component, "CementPlants.csv"), "CementPlants", component,
        ),
        AmmoniaPlant = _read_sector_vector(
            _required_csv(dir, component, "AmmoniaPlants.csv"), "AmmoniaPlants", component,
        ),
        hydrogen = hydrogen,
    )
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

function _optional_csv(dir::AbstractString, component::AbstractString, filename::AbstractString)
    path = joinpath(dir, component, filename)
    return isfile(path) ? path : nothing
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

# `default_value` fills periods a key does not provide. It must equal the Pyomo
# parameter's own `default=` for the table being read: Pyomo falls back to that
# default for every missing (key, period) cell, whereas this reader materializes
# one profile per key. Padding with a blanket 0.0 silently turned "no row" into
# "capacity 0" for build-cap tables whose Pyomo default is 500,000 — forbidding
# investment the reference allows (root cause of the full_model_int North Sea
# infeasibility at HelgolaenderBucht).
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
function read_sets_csv(
    dir::AbstractString;
    natural_gas::Bool = false,
    hydrogen::Bool = false,
    industry::Bool = false,
)
    @info "Reading CSV sets from $dir"

    sets_dir = "Sets"
    generators = _read_vector_csv(_required_csv(dir, sets_dir, "Generator.csv"))
    gas_sets = natural_gas ? _read_natural_gas_sets_csv(dir, generators) : NaturalGasSets()
    base_links = _read_tuple2_csv(_required_csv(dir, sets_dir, "DirectionalLink.csv"))
    hydrogen_sets = hydrogen ?
                    _read_hydrogen_sets_csv(dir, generators, base_links, gas_sets) :
                    HydrogenSets()
    industry_sets_value = industry ? _read_industry_sets_csv(dir; hydrogen) : IndustrySets()

    return OpenEMPIRE.EmpireSets(
        Generator = generators,
        ThermalGenerators = _read_vector_csv(_required_csv(dir, sets_dir, "ThermalGenerators.csv")),
        HydroGenerator = _read_vector_csv(_required_csv(dir, sets_dir, "HydroGenerator.csv")),
        RegHydroGenerator = _read_vector_csv(_required_csv(dir, sets_dir, "RegHydroGenerator.csv")),
        Storage = _read_vector_csv(_required_csv(dir, sets_dir, "Storage.csv")),
        DependentStorage = _read_vector_csv(_required_csv(dir, sets_dir, "DependentStorage.csv")),
        Technology = _read_vector_csv(_required_csv(dir, sets_dir, "Technology.csv")),
        Node = _read_vector_csv(_required_csv(dir, sets_dir, "Node.csv")),
        DirectionalLink = base_links,
        TransmissionType = _read_vector_csv(_required_csv(dir, sets_dir, "TransmissionType.csv")),
        TransmissionTypeOfDirectionalLink =
            _read_tuple3_csv(_required_csv(dir, sets_dir, "TransmissionTypeOfDirectionalLink.csv")),
        GeneratorsOfTechnology = _read_tuple2_csv(_required_csv(dir, sets_dir, "GeneratorsOfTechnology.csv")),
        GeneratorsOfNode = _read_tuple2_csv(_required_csv(dir, sets_dir, "GeneratorsOfNode.csv")),
        StoragesOfNode = _read_tuple2_csv(_required_csv(dir, sets_dir, "StoragesOfNode.csv")),
        NaturalGas = gas_sets,
        Hydrogen = hydrogen_sets,
        Industry = industry_sets_value,
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

function _read_sector_scalar(path, header, sector; positive::Bool = false)
    rows = _validated_sector_rows(path, (String(header),), sector)
    length(rows) == 1 || throw(ArgumentError(
        "$sector scalar CSV $path must contain exactly one data row",
    ))
    value = _sector_nonnegative(path, 2, header, only(rows)[1], sector)
    positive && value <= 0 && throw(ArgumentError(
        "$sector scalar CSV $path column $header must be positive",
    ))
    return value
end

function _read_sector_period_values(path, headers, sector)
    rows = _validated_sector_rows(path, headers, sector)
    values = Dict{Int, Float64}()
    for (index, row) in enumerate(rows)
        row_number = index + 1
        period = _sector_period(path, row_number, headers[1], row[1], sector)
        value = _sector_nonnegative(path, row_number, headers[2], row[2], sector)
        _insert_unique_sector!(values, period, value, path, row_number, sector)
    end
    return values
end

function _read_sector_plant_period_values(path, headers, sector; signed::Bool = false)
    rows = _validated_sector_rows(path, headers, sector)
    values = Dict{HydrogenPlantPeriod, Float64}()
    for (index, row) in enumerate(rows)
        row_number = index + 1
        key = (
            _sector_string(path, row_number, headers[1], row[1], sector),
            _sector_period(path, row_number, headers[2], row[2], sector),
        )
        value = signed ?
                _sector_float(path, row_number, headers[3], row[3], sector) :
                _sector_nonnegative(path, row_number, headers[3], row[3], sector)
        _insert_unique_sector!(values, key, value, path, row_number, sector)
    end
    return values
end

function _read_sector_node_period_values(path, headers, sector)
    rows = _validated_sector_rows(path, headers, sector)
    values = Dict{HydrogenNodePeriod, Float64}()
    for (index, row) in enumerate(rows)
        row_number = index + 1
        key = (
            _sector_string(path, row_number, headers[1], row[1], sector),
            _sector_period(path, row_number, headers[2], row[2], sector),
        )
        value = _sector_nonnegative(path, row_number, headers[3], row[3], sector)
        _insert_unique_sector!(values, key, value, path, row_number, sector)
    end
    return values
end

function _read_sector_pair_values(path, headers, sector)
    rows = _validated_sector_rows(path, headers, sector)
    values = Dict{Tuple{String, String}, Float64}()
    for (index, row) in enumerate(rows)
        row_number = index + 1
        key = (
            _sector_string(path, row_number, headers[1], row[1], sector),
            _sector_string(path, row_number, headers[2], row[2], sector),
        )
        value = _sector_nonnegative(path, row_number, headers[3], row[3], sector)
        _insert_unique_sector!(values, key, value, path, row_number, sector)
    end
    return values
end

function _read_sector_string_values(path, headers, sector; positive::Bool = false)
    rows = _validated_sector_rows(path, headers, sector)
    values = Dict{String, Float64}()
    for (index, row) in enumerate(rows)
        row_number = index + 1
        key = _sector_string(path, row_number, headers[1], row[1], sector)
        value = _sector_nonnegative(path, row_number, headers[2], row[2], sector)
        positive && value <= 0 && throw(ArgumentError(
            "Malformed $sector CSV $path data row $row_number column $(headers[2]): " *
            "value must be positive",
        ))
        _insert_unique_sector!(values, key, value, path, row_number, sector)
    end
    return values
end

function _read_hydrogen_terminal_period_values(path, headers, sector; multiplier = 1.0)
    rows = _validated_sector_rows(path, headers, sector)
    values = Dict{HydrogenNodeTerminalPeriod, Float64}()
    for (index, row) in enumerate(rows)
        row_number = index + 1
        key = (
            _sector_string(path, row_number, headers[1], row[1], sector),
            _sector_string(path, row_number, headers[2], row[2], sector),
            _sector_period(path, row_number, headers[3], row[3], sector),
        )
        value = multiplier * _sector_nonnegative(
            path, row_number, headers[4], row[4], sector,
        )
        _insert_unique_sector!(values, key, value, path, row_number, sector)
    end
    return values
end

function _read_hydrogen_constants(path)
    sector = "Hydrogen"
    headers = ("Parameter", "Value", "Unit", "Source")
    rows = _validated_sector_rows(path, headers, sector)
    values = Dict{String, Float64}()
    for (index, row) in enumerate(rows)
        row_number = index + 1
        key = _sector_string(path, row_number, "Parameter", row[1], sector)
        value = _sector_nonnegative(path, row_number, "Value", row[2], sector)
        _sector_string(path, row_number, "Unit", row[3], sector)
        _sector_string(path, row_number, "Source", row[4], sector)
        _insert_unique_sector!(values, key, value, path, row_number, sector)
    end
    expected = Set((
        "hydrogen_mwh_per_ton",
        "storage_initial_fraction",
        "storage_compression_mwh_per_ton",
        "pipeline_compressor_static_mwh_per_ton",
        "hydrogen_pipeline_lifetime_years",
        "pipeline_leakage_fraction_per_km",
        "reformer_ramp_fraction_per_hour",
        "repurpose_cost_factor",
        "repurpose_energy_flow_factor",
        "terminal_eur_per_kg_to_eur_per_ton",
        "hours_per_year",
    ))
    Set(keys(values)) == expected || throw(ArgumentError(
        "Hydrogen constants inventory mismatch in $path; expected $(sort!(collect(expected))), " *
        "got $(sort!(collect(keys(values))))",
    ))
    return values
end

function _read_hydrogen_params_csv(dir::AbstractString)
    component = "Hydrogen"
    h2path(filename) = _required_csv(dir, component, filename)
    co2path(filename) = _required_csv(dir, "CO2", filename)
    constants = _read_hydrogen_constants(h2path("Constants.csv"))
    hydrogen = HydrogenParams(
        electrolyzerCapitalCost = _read_sector_period_values(
            h2path("ElectrolyzerPlantCapitalCost.csv"),
            ("Period", "elyzerCapCost_(€/MWe)"), component,
        ),
        electrolyzerFixedOMCost = _read_sector_period_values(
            h2path("ElectrolyzerFixedOMCost.csv"), ("Period", "eLyzerOMCost"), component,
        ),
        electrolyzerPowerUse = _read_sector_period_values(
            h2path("ElectrolyzerPowerUse.csv"),
            ("Period", "El_consumption_(MWh/ton)"), component,
        ),
        electrolyzerLifetime = _read_sector_scalar(
            h2path("ElectrolyzerLifetime.csv"), "elyzerLifetime", component; positive = true,
        ),
        reformerCapitalCost = _read_sector_plant_period_values(
            h2path("ReformerCapitalCost.csv"),
            ("Plant_type", "Period", "Capital_cost_[EUR/MW_H2]"), component,
        ),
        reformerFixedOMCost = _read_sector_plant_period_values(
            h2path("ReformerFixedOMCost.csv"),
            ("Plant_type", "Period", "Fixed_O&M_cost_[EUR/MW_H2]"), component,
        ),
        reformerVariableOMCost = _read_sector_plant_period_values(
            h2path("ReformerVariableOMCost.csv"),
            ("Plant_type", "Period", "Variable_O&M_cost_[EUR/ton_H2]"), component,
        ),
        reformerEfficiency = _read_sector_plant_period_values(
            h2path("ReformerEfficiency.csv"),
            ("Plant_type", "Period", "LHV_Efficiency"), component,
        ),
        reformerElectricityUse = _read_sector_plant_period_values(
            h2path("ReformerElectricityUse.csv"),
            ("Plant_type", "Period", "Electricity_demand_[MWh_/_ton]"), component;
            signed = true,
        ),
        reformerEmissionFactor = _read_sector_plant_period_values(
            h2path("ReformerEmissionFactor.csv"),
            ("Plant_type", "Period", "Ton_CO2_emissions_per_ton_H2"), component,
        ),
        reformerCO2CaptureFactor = _read_sector_plant_period_values(
            h2path("ReformerCO2CaptureFactor.csv"),
            ("Plant_type", "Period", "Ton_CO2_emissions_captured_per_ton_H2"), component,
        ),
        pipelineCapitalCost = _read_sector_period_values(
            h2path("PipelineCapitalCost.csv"), ("Period", "Capital_cost"), component,
        ),
        pipelineOMCostPerKM = _read_sector_period_values(
            h2path("PipelineOMCostPerKM.csv"), ("Period", "O&M_Cost"), component,
        ),
        pipelineCompressorPowerUsage = _read_sector_scalar(
            h2path("PipelineCompressorPowerUsage.csv"), "Electricity_usage", component,
        ),
        storageCapitalCost = _read_sector_plant_period_values(
            h2path("StorageCapitalCost.csv"),
            ("H2Storage", "Period", "Capital_cost_(EUR/ton)"), component,
        ),
        storageFixedOMCost = _read_sector_plant_period_values(
            h2path("StorageFixedOMCost.csv"),
            ("H2Storage", "Period", "O&M_cost_per_kg_H2"), component,
        ),
        storageLifetime = _read_sector_string_values(
            h2path("StorageLifetime.csv"), ("H2Storage", "Lifetime"), component; positive = true,
        ),
        storageMaxCapacity = _read_sector_pair_values(
            h2path("StorageMaxCapacity.csv"),
            ("Node", "H2Storage", "Max_capacity_[ton]"), component,
        ),
        terminalInitialCapacity = _read_hydrogen_terminal_period_values(
            h2path("H2TerminalCapacity.csv"),
            ("H2TerminalNodes", "H2Terminals", "Period", "Capacity_(ton/hr)"), component,
        ),
        terminalCapitalCost = _read_hydrogen_terminal_period_values(
            h2path("H2TerminalCapitalCost.csv"),
            ("H2TerminalNodes", "H2Terminals", "Period", "CapitalCost_(EUR/ton/h)"), component,
        ),
        terminalFixedOMCost = _read_hydrogen_terminal_period_values(
            h2path("H2TerminalFixedOM.csv"),
            ("H2TerminalNodes", "H2Terminals", "Period", "FixedOM_(EUR/ton/h)"), component,
        ),
        terminalPrice = _read_hydrogen_terminal_period_values(
            h2path("H2TerminalPrice.csv"),
            ("H2TerminalNodes", "H2Terminals", "Period", "Cost_(EUR/kg)"), component;
            multiplier = constants["terminal_eur_per_kg_to_eur_per_ton"],
        ),
        terminalLifetime = _read_sector_string_values(
            h2path("H2TerminalLifetime.csv"), ("H2Terminals", "importLifetime"), component;
            positive = true,
        ),
        electricityTransportDemand = _read_sector_node_period_values(
            _required_csv(dir, "Transport", "ElectricityDemand.csv"),
            ("Node", "Period", "Electricity_demand_[MWh/yr]"), "Hydrogen transport",
        ),
        hydrogenTransportDemand = _read_sector_node_period_values(
            _required_csv(dir, "Transport", "HydrogenDemand.csv"),
            ("Node", "Period", "Hydrogen_demand_[MWh/yr]"), "Hydrogen transport",
        ),
        generatorCO2Captured = _read_sector_string_values(
            _required_csv(dir, "Generator", "genCO2Captured.csv"),
            ("GeneratorTechnology", "CO2Capctured_in_tCO2/GJ"), "Hydrogen CO2",
        ),
        co2StorageMaxCapacity = _read_sector_node_period_values(
            co2path("StorageMaxCapacity.csv"),
            ("Node", "Period", "Storage_max_injection_capacity_(ton/hour)"), "CO2",
        ),
        co2MaxSequestrationCapacity = _read_sector_string_values(
            co2path("MaxSequestrationCapacity.csv"),
            ("Node", "Max_sequestration_capacity_[tons]"), "CO2",
        ),
        co2StorageSiteCapitalCost = _read_sector_string_values(
            co2path("StorageSiteCapitalCost.csv"),
            ("Node", "Site_Development_Cost_euro/(t/hr)"), "CO2",
        ),
        co2StorageSiteFixedOMCost = _read_sector_string_values(
            co2path("StorageSiteFixedOMCost.csv"),
            ("Node", "Field_Fixed_OM_Cost_euro/(t/hr)"), "CO2",
        ),
        co2PipelineCapitalCost = _read_sector_scalar(
            co2path("PipelineCapitalCost.csv"), "Capital_cost_(euro/(km_*_tons/hr)", "CO2",
        ),
        co2PipelineFixedOMCost = _read_sector_scalar(
            co2path("PipelineFixedOM.csv"), "O&M_Cost_(euro/km)", "CO2",
        ),
        co2PipelineElectricityUsage = _read_sector_scalar(
            co2path("PipelineElectricityUsage.csv"), "Power_usage_[MWh/ton]", "CO2",
        ),
        co2PipelineLifetime = _read_sector_scalar(
            co2path("PipelineLifetime.csv"), "Lifetime_(years)", "CO2"; positive = true,
        ),
        hydrogenMWhPerTon = constants["hydrogen_mwh_per_ton"],
        storageInitialFraction = constants["storage_initial_fraction"],
        storageCompressionMWhPerTon = constants["storage_compression_mwh_per_ton"],
        pipelineCompressorStaticMWhPerTon = constants["pipeline_compressor_static_mwh_per_ton"],
        pipelineLifetime = constants["hydrogen_pipeline_lifetime_years"],
        pipelineLeakageFractionPerKM = constants["pipeline_leakage_fraction_per_km"],
        reformerRampFractionPerHour = constants["reformer_ramp_fraction_per_hour"],
        repurposeCostFactor = constants["repurpose_cost_factor"],
        repurposeEnergyFlowFactor = constants["repurpose_energy_flow_factor"],
        terminalEURPerKgToEURPerTon = constants["terminal_eur_per_kg_to_eur_per_ton"],
        hoursPerYear = constants["hours_per_year"],
    )
    lifetime_path = h2path("ReformerLifetime.csv")
    lifetime_rows = _validated_sector_rows(
        lifetime_path, ("elyzerLifetime", "SMRLifetime"), component,
    )
    for (index, row) in enumerate(lifetime_rows)
        row_number = index + 1
        plant = _sector_string(lifetime_path, row_number, "elyzerLifetime", row[1], component)
        value = _sector_nonnegative(lifetime_path, row_number, "SMRLifetime", row[2], component)
        value > 0 || throw(ArgumentError("Hydrogen reformer lifetime must be positive for $plant"))
        _insert_unique_sector!(
            hydrogen.reformerLifetime, plant, value, lifetime_path, row_number, component,
        )
    end
    return hydrogen
end

function _read_industry_constants(path)
    sector = "Industry"
    rows = _validated_sector_rows(path, ("Parameter", "Value", "Unit", "Source"), sector)
    values = Dict{String, Float64}()
    for (index, row) in enumerate(rows)
        row_number = index + 1
        key = _sector_string(path, row_number, "Parameter", row[1], sector)
        value = _sector_nonnegative(path, row_number, "Value", row[2], sector)
        _sector_string(path, row_number, "Unit", row[3], sector)
        _sector_string(path, row_number, "Source", row[4], sector)
        _insert_unique_sector!(values, key, value, path, row_number, sector)
    end
    expected = Set((
        "ramp_fraction_per_hour", "maximum_scrap_share", "hours_per_year",
        "oil_shed_cost",
    ))
    Set(keys(values)) == expected || throw(ArgumentError(
        "Industry constants inventory mismatch in $path",
    ))
    return values
end

function _read_industry_params_csv(dir::AbstractString)
    component = "Industry"
    path(filename) = _required_csv(dir, component, filename)
    constants = _read_industry_constants(path("Constants.csv"))
    return IndustryParams(
        steelLifetime = _read_sector_string_values(
            path("SteelPlantLifetime.csv"), ("PlantType", "Lifetime"), component;
            positive = true,
        ),
        steelInitialCapacity = _read_sector_pair_values(
            path("SteelInitialCapacity.csv"),
            ("Node", "PlantType", "Initial_capacity_(ton/hr)"), component,
        ),
        steelRetirementFactor = _read_sector_plant_period_values(
            path("SteelScaleFactorInitialCap.csv"),
            ("PlantType", "Period", "RetirementFactor"), component,
        ),
        steelCapitalCost = _read_sector_plant_period_values(
            path("SteelInvCost.csv"),
            ("PlantType", "Period", "InvCost_(eur/(t/h)_crude_steel)"), component,
        ),
        steelFixedOMCost = _read_sector_plant_period_values(
            path("SteelFixedOM.csv"),
            ("PlantType", "Period", "InvCost_(eur/(t/h)_crude_steel)"), component,
        ),
        steelVariableOMCost = _read_sector_plant_period_values(
            path("SteelVarOpex.csv"),
            ("PlantType", "Period", "VarOpex_(eur/(t/h)_crude_steel)"), component,
        ),
        steelCoalConsumption = _read_sector_plant_period_values(
            path("SteelCoalConsumption.csv"),
            ("SteelPlant", "Period", "Coal_Consumption"), component,
        ),
        steelHydrogenConsumption = _read_sector_plant_period_values(
            path("SteelHydrogenConsumption.csv"),
            ("SteelPlant", "Period", "Hydrogen_Consumption"), component,
        ),
        steelBiomassConsumption = _read_sector_plant_period_values(
            path("SteelBioConsumption.csv"),
            ("SteelPlant", "Period", "FuelConsumption"), component,
        ),
        steelOilConsumption = _read_sector_plant_period_values(
            path("SteelOilConsumption.csv"),
            ("SteelPlant", "Period", "FuelConsumption"), component,
        ),
        steelElectricityConsumption = _read_sector_plant_period_values(
            path("SteelElConsumption.csv"),
            ("SteelPlant", "Period", "ElectricityConsumption"), component,
        ),
        steelCO2Emissions = _read_sector_string_values(
            path("SteelCO2Emissions.csv"),
            ("SteelPlant", "CO2_emissions_(ton_CO2/ton_crude_steel)"), component,
        ),
        steelCO2Captured = _read_sector_string_values(
            path("SteelCO2Captured.csv"),
            ("SteelPlant", "CO2_captured_(ton_CO2/ton_crude_steel)"), component,
        ),
        steelYearlyProduction = _read_sector_node_period_values(
            path("SteelYearlyProduction.csv"),
            ("Node", "Period", "Production_(ton/yr)"), component,
        ),
        cementLifetime = _read_sector_string_values(
            path("CementPlantLifetime.csv"), ("PlantType", "Lifetime"), component;
            positive = true,
        ),
        cementInitialCapacity = _read_sector_pair_values(
            path("CementInitialCapacity.csv"),
            ("Node", "CementPlant", "Capacity_(ton/hr)"), component,
        ),
        cementRetirementFactor = _read_sector_plant_period_values(
            path("CementScaleFactorInitialCap.csv"),
            ("PlantType", "Period", "RetirementFactor"), component,
        ),
        cementCapitalCost = _read_sector_plant_period_values(
            path("CementInvCost.csv"),
            ("PlantType", "Period", "InvCost_(EUR/(ton/hr))"), component,
        ),
        cementFixedOMCost = _read_sector_plant_period_values(
            path("CementFixedOM.csv"),
            ("PlantType", "Period", "Fixed_O&M_(EUR/(ton/hr))"), component,
        ),
        cementFuelConsumption = _read_sector_plant_period_values(
            path("CementFuelConsumption.csv"),
            ("CementPlant", "Period", "FuelConsumption"), component,
        ),
        cementCO2CaptureRate = _read_sector_string_values(
            path("CementCO2CaptureRate.csv"), ("CementPlant", "CaptureRate"), component,
        ),
        cementElectricityConsumption = _read_sector_plant_period_values(
            path("CementElConsumption.csv"),
            ("CementPlant", "Period", "ElectricityConsumption"), component,
        ),
        cementYearlyProduction = _read_sector_string_values(
            path("CementYearlyProduction.csv"), ("Node", "Production"), component,
        ),
        ammoniaLifetime = _read_sector_string_values(
            path("AmmoniaPlantLifetime.csv"), ("PlantType", "Lifetime"), component;
            positive = true,
        ),
        ammoniaInitialCapacity = _read_sector_pair_values(
            path("AmmoniaInitialCapacity.csv"),
            ("Node", "AmmoniaPlant", "Capacity_(ton/hr)"), component,
        ),
        ammoniaRetirementFactor = _read_sector_plant_period_values(
            path("AmmoniaScaleFactorInitialCap.csv"),
            ("PlantType", "Period", "RetirementFactor"), component,
        ),
        ammoniaCapitalCost = _read_sector_plant_period_values(
            path("AmmoniaInvCost.csv"),
            ("PlantType", "Period", "InvCost_(EUR/(ton/hr))"), component,
        ),
        ammoniaFixedOMCost = _read_sector_plant_period_values(
            path("AmmoniaFixedOM.csv"),
            ("PlantType", "Period", "Fixed_O&M_(EUR/(ton/hr))"), component,
        ),
        ammoniaFeedstockConsumption = _read_sector_string_values(
            path("AmmoniaFeedstockConsumption.csv"),
            ("Ammonia_Plant", "Feedstock_Consumption_(kg_feedstock_/_t_ammonia)"), component,
        ),
        ammoniaElectricityConsumption = _read_sector_string_values(
            path("AmmoniaElConsumption.csv"),
            ("Ammonia_plant", "Electricity_consumption_(MWh_/_t_ammonia)"), component,
        ),
        ammoniaYearlyProduction = _read_sector_node_period_values(
            path("AmmoniaYearlyProduction.csv"),
            ("Node", "Period", "Yearly_production_(tons/yr)"), component,
        ),
        refineryYearlyProduction = _read_sector_node_period_values(
            path("RefineryYearlyProduction.csv"),
            ("Node", "Period", "Yearly_production_of_oil_(k_bbl/yr)"), component,
        ),
        availableBioEnergy = _read_sector_period_values(
            _required_csv(dir, "General", "availableBioEnergy.csv"),
            ("Period", "Available_bioenergy_(GJ)"), component,
        ),
        industryShedCost = _read_sector_scalar(
            path("ShedCost.csv"), "ShedCost_(€/ton)", component,
        ),
        refineryHydrogenConsumption = _read_sector_scalar(
            path("RefineryHydrogenConsumption.csv"),
            "Hydrogen_consumption_(ton/k_bbl)", component,
        ),
        refineryHeatConsumption = _read_sector_scalar(
            path("RefineryHeatConsumption.csv"), "Heat_Consumption_(MWh/k_bbl)", component,
        ),
        rampFractionPerHour = constants["ramp_fraction_per_hour"],
        maximumScrapShare = constants["maximum_scrap_share"],
        hoursPerYear = constants["hours_per_year"],
        oilShedCost = constants["oil_shed_cost"],
    )
end

"""
    read_params_csv(dir)

Read EMPIRE parameters from a CSV dataset folder using the Python/CSV dataset
layout. Extra source/unit columns are ignored; files are parsed by position.
"""
function read_params_csv(
    dir::AbstractString;
    natural_gas::Bool = false,
    hydrogen::Bool = false,
    industry::Bool = false,
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
    par.genMaxBuiltCap = _read_strategic_profiles_pair_csv(
        _required_csv(dir, generator, "genMaxBuiltCap.csv");
        default_value = DEFAULT_GEN_MAX_BUILD_CAP,
    )
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
        _read_strategic_profiles_pair_csv(
        _required_csv(dir, transmission, "transmissionMaxBuiltCap.csv");
        default_value = PYOMO_DEFAULT_TRANS_MAX_BUILD_CAP,
    )
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
    par.storENMaxBuiltCap = _read_strategic_profiles_pair_csv(
        _required_csv(dir, storage, "storENMaxBuiltCap.csv");
        default_value = DEFAULT_MAX_BUILD_CAP,
    )
    par.storENMaxInstalledCap =
        _read_float_by_pair_csv(_required_csv(dir, storage, "storENMaxInstalledCapRaw.csv"))
    par.storOperationalInit =
        _read_float_by_string_csv(_required_csv(dir, storage, "storOperationalInit.csv"))
    par.storPWCapitalCost = _read_strategic_profiles_csv(_required_csv(dir, storage, "storPWCapitalCost.csv"))
    par.storPWFixedOMCost = _read_strategic_profiles_csv(_required_csv(dir, storage, "storPWFixedOMCost.csv"))
    par.storPWInitCap = _read_strategic_profiles_pair_csv(_required_csv(dir, storage, "storPWInitCap.csv"))
    par.storPWMaxBuiltCap = _read_strategic_profiles_pair_csv(
        _required_csv(dir, storage, "storPWMaxBuiltCap.csv");
        default_value = DEFAULT_MAX_BUILD_CAP,
    )
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
    hydrogen && (par.Hydrogen = _read_hydrogen_params_csv(dir))
    industry && (par.Industry = _read_industry_params_csv(dir))

    return par
end

"""
    read_data_csv(dir)

Read sets and parameters from a CSV EMPIRE dataset folder.
"""
function read_data_csv(
    dir::AbstractString;
    natural_gas::Bool = false,
    hydrogen::Bool = false,
    industry::Bool = false,
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
)
    hydrogen && !natural_gas && throw(ArgumentError("hydrogen=true requires natural_gas=true"))
    hydrogen && gas_scenarios != 1 && throw(ArgumentError(
        "Deterministic Hydrogen requires number_of_gas_scenarios=1",
    ))
    industry && !natural_gas && throw(ArgumentError("industry=true requires natural_gas=true"))
    industry && gas_scenarios != 1 && throw(ArgumentError(
        "Deterministic Industry requires number_of_gas_scenarios=1",
    ))
    sets = read_sets_csv(dir; natural_gas, hydrogen, industry)
    par = read_params_csv(
        dir; natural_gas, hydrogen, industry, weather_scenarios, gas_scenarios,
    )
    return (sets, par)
end
