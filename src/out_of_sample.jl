"""
    fix_investments_from_results!(model, sets, periods, output_dir; fix_installed_capacities=true)

Read strategic capacity results from a previous run and fix the matching JuMP
variables in `model`.

`output_dir` may point either to a run directory or directly to its `Output`
subdirectory.
"""
function fix_investments_from_results!(
    model::JuMP.Model,
    sets,
    periods::TimeStructure,
    output_dir::AbstractString;
    fix_installed_capacities::Bool = true,
)
    output_dir = _oos_output_dir(output_dir)
    strategic_periods = collect(enumerate(strat_periods(periods)))

    # Fix investment decisions to values from the previous run.
    _fix_generator_capacity!(
        model[:genInvCap],
        sets,
        strategic_periods,
        _read_generator_capacity(output_dir, "genInvCap.csv", "genInvCap"),
        "genInvCap",
    )

    # Accept the old misspelled file/column name for compatibility with
    # previous Julia result folders.
    _fix_transmission_capacity!(
        model[:transmissionInvCap],
        sets,
        strategic_periods,
        _read_transmission_capacity(
            output_dir,
            ("transmissionInvCap.csv", "transmisionInvCap.csv"),
            ("transmissionInvCap", "transmisionInvCap"),
        ),
        "transmissionInvCap",
    )

    _fix_storage_capacity!(
        model[:storPWInvCap],
        sets,
        strategic_periods,
        _read_storage_capacity(output_dir, "storPWInvCap.csv", "storPWInvCap"),
        "storPWInvCap",
    )

    _fix_storage_capacity!(
        model[:storENInvCap],
        sets,
        strategic_periods,
        _read_storage_capacity(output_dir, "storENInvCap.csv", "storENInvCap"),
        "storENInvCap",
    )

    if fix_installed_capacities
        # Fix installed capacities to the same previous-run capacity trajectory.
        _fix_generator_capacity!(
            model[:genInstalledCap],
            sets,
            strategic_periods,
            _read_generator_capacity(output_dir, "genInstalledCap.csv", "genInstalledCap"),
            "genInstalledCap",
        )

        _fix_transmission_capacity!(
            model[:transmissionInstalledCap],
            sets,
            strategic_periods,
            _read_transmission_capacity(
                output_dir,
                ("transmissionInstalledCap.csv",),
                ("transmissionInstalledCap",),
            ),
            "transmissionInstalledCap",
        )

        _fix_storage_capacity!(
            model[:storPWInstalledCap],
            sets,
            strategic_periods,
            _read_storage_capacity(output_dir, "storPWInstalledCap.csv", "storPWInstalledCap"),
            "storPWInstalledCap",
        )

        _fix_storage_capacity!(
            model[:storENInstalledCap],
            sets,
            strategic_periods,
            _read_storage_capacity(output_dir, "storENInstalledCap.csv", "storENInstalledCap"),
            "storENInstalledCap",
        )
    end

    return model
end

function _oos_output_dir(path::AbstractString)
    isdir(path) || throw(ArgumentError("Fixed-investment directory does not exist: $path"))

    for output_folder in ("Output", "output")
        output_path = joinpath(path, output_folder)
        isdir(output_path) && return output_path
    end

    return path
end

function _first_existing_file(output_dir::AbstractString, filenames)
    for filename in filenames
        path = joinpath(output_dir, filename)
        isfile(path) && return path
    end

    throw(ArgumentError(
        "Could not find any of these files in $output_dir: $(join(filenames, ", "))"
    ))
end

_oos_float_value(x) = x isa Real ? Float64(x) : parse(Float64, strip(string(x)))
_oos_int_value(x) = x isa Integer ? Int(x) : parse(Int, strip(string(x)))
_oos_string_value(x) = strip(string(x))

function _oos_row_value(row, columns)
    available = Set(string.(propertynames(row)))

    for column in columns
        if column in available
            return getproperty(row, Symbol(column))
        end
    end

    throw(ArgumentError("Missing value column. Tried: $(join(columns, ", "))"))
end

function _read_generator_capacity(output_dir, filename, value_column)
    path = _first_existing_file(output_dir, (filename,))
    values = Dict{Tuple{String, String, Int}, Float64}()

    for row in CSV.File(path; normalizenames = false)
        key = (
            _oos_string_value(row.Node),
            _oos_string_value(row.Generator),
            _oos_int_value(row.Period),
        )
        values[key] = _oos_float_value(getproperty(row, Symbol(value_column)))
    end

    return values
end

function _read_transmission_capacity(output_dir, filenames, value_columns)
    path = _first_existing_file(output_dir, filenames)
    values = Dict{Tuple{String, String, Int}, Float64}()

    for row in CSV.File(path; normalizenames = false)
        key = (
            _oos_string_value(row.FromNode),
            _oos_string_value(row.ToNode),
            _oos_int_value(row.Period),
        )
        values[key] = _oos_float_value(_oos_row_value(row, value_columns))
    end

    return values
end

function _read_storage_capacity(output_dir, filename, value_column)
    path = _first_existing_file(output_dir, (filename,))
    values = Dict{Tuple{String, String, Int}, Float64}()

    for row in CSV.File(path; normalizenames = false)
        key = (
            _oos_string_value(row.Node),
            _oos_string_value(row.Storage),
            _oos_int_value(row.Period),
        )
        values[key] = _oos_float_value(getproperty(row, Symbol(value_column)))
    end

    return values
end

function _fixed_value(values, key, table_name)
    # Missing keys usually mean the OOS run is using different structural data
    # than the in-sample run that produced the fixed investment results.
    value = get(values, key, nothing)

    value === nothing && throw(ArgumentError(
        "Missing fixed OOS value for $table_name at key $key"
    ))

    return value
end

function _fix_generator_capacity!(variable, sets, strategic_periods, values, table_name)
    used = Set{Tuple{String, String, Int}}()

    for (period_index, sp) in strategic_periods
        for (node, generator) in node_generators(sets)
            key = (node, generator, period_index)
            JuMP.fix(variable[node, generator, sp], _fixed_value(values, key, table_name); force = true)
            push!(used, key)
        end
    end

    _check_no_extra_oos_keys(values, used, table_name)
    return nothing
end

function _fix_transmission_capacity!(variable, sets, strategic_periods, values, table_name)
    used = Set{Tuple{String, String, Int}}()

    for (period_index, sp) in strategic_periods
        for (from_node, to_node) in bidir_arcs(sets)
            key = (from_node, to_node, period_index)
            JuMP.fix(variable[from_node, to_node, sp], _fixed_value(values, key, table_name); force = true)
            push!(used, key)
        end
    end

    _check_no_extra_oos_keys(values, used, table_name)
    return nothing
end

function _fix_storage_capacity!(variable, sets, strategic_periods, values, table_name)
    used = Set{Tuple{String, String, Int}}()

    for (period_index, sp) in strategic_periods
        for (node, storage) in node_storages(sets)
            key = (node, storage, period_index)
            JuMP.fix(variable[node, storage, sp], _fixed_value(values, key, table_name); force = true)
            push!(used, key)
        end
    end

    _check_no_extra_oos_keys(values, used, table_name)
    return nothing
end

function _check_no_extra_oos_keys(values, used, table_name)
    # Extra keys catch the opposite mismatch: the result file has assets that
    # are not part of the current model's sets.
    extra = setdiff(Set(keys(values)), used)

    if !isempty(extra)
        preview = collect(extra)[1:min(end, 10)]
        throw(ArgumentError(
            "Fixed OOS file for $table_name contains keys not present in current model. " *
            "First extra keys: $preview"
        ))
    end

    return nothing
end
