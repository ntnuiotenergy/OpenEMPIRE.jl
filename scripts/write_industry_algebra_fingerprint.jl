#!/usr/bin/env julia

"""Build OpenEMPIRE.jl without an optimizer and fingerprint its Industry algebra."""

using JuMP
using OpenEMPIRE
using Printf
using SHA
using TimeStruct

const MOI = JuMP.MOI
const PRECISIONS = (9, 12)
const BUCKETS = 256

const DEDICATED_FAMILIES = (
    :steel_capacity => :industry_steel_capacity,
    :steel_material => :industry_steel_raw_material,
    :cement_capacity => :industry_cement_capacity,
    :ammonia_capacity => :industry_ammonia_capacity,
    :steel_demand => :industry_steel_demand,
    :cement_demand => :industry_cement_demand,
    :ammonia_demand => :industry_ammonia_demand,
    :refinery_demand => :industry_refinery_demand,
    :steel_ramp => :industry_steel_ramp,
    :cement_ramp => :industry_cement_ramp,
    :ammonia_ramp => :industry_ammonia_ramp,
    :steel_installed => :industry_steel_installed,
    :cement_installed => :industry_cement_installed,
    :ammonia_installed => :industry_ammonia_installed,
    :scrap_limit => :industry_max_scrap_capacity,
)

const SHARED_FAMILIES = (
    :electricity_balance => :flow_balance,
    :natural_gas_balance => :natural_gas_flow_balance,
    :hydrogen_balance => :hydrogen_flow_balance,
    :captured_co2_balance => :co2_flow_balance,
    :biomass_availability => :industry_biomass_limit,
)

const VARIABLES = Dict(
    "steelProduced" => ("steel_production", true),
    "steelLoadShed" => ("steel_shed", true),
    "steelPlantBuiltCapacity" => ("steel_built", false),
    "steelPlantInstalledCapacity" => ("steel_installed", false),
    "cementProduced" => ("cement_production", true),
    "cementLoadShed" => ("cement_shed", true),
    "cementPlantBuiltCapacity" => ("cement_built", false),
    "cementPlantInstalledCapacity" => ("cement_installed", false),
    "ammoniaProduced" => ("ammonia_production", true),
    "ammoniaLoadShed" => ("ammonia_shed", true),
    "ammoniaPlantBuiltCapacity" => ("ammonia_built", false),
    "ammoniaPlantInstalledCapacity" => ("ammonia_installed", false),
    "oilRefined" => ("refinery_output", true),
    "oilLoadShed" => ("refinery_shed", true),
)

const OBJECTIVE_GROUPS = Dict(
    "steelProduced" => "steel_operation",
    "cementProduced" => "cement_operation",
    "ammoniaProduced" => "ammonia_operation",
    "steelLoadShed" => "steel_shedding",
    "cementLoadShed" => "cement_shedding",
    "ammoniaLoadShed" => "ammonia_shedding",
    "oilLoadShed" => "refinery_shedding",
    "steelPlantBuiltCapacity" => "steel_investment",
    "cementPlantBuiltCapacity" => "cement_investment",
    "ammoniaPlantBuiltCapacity" => "ammonia_investment",
)

mutable struct Accumulator
    count::Int
    terms::Int
    xor::NTuple{4, UInt64}
    total::NTuple{4, UInt64}
end

Accumulator() = Accumulator(0, 0, ntuple(_ -> UInt64(0), 4), ntuple(_ -> UInt64(0), 4))

function sha_limbs(payload::AbstractString)
    digest = SHA.sha256(codeunits(payload))
    return ntuple(4) do limb
        offset = 8 * (limb - 1)
        value = UInt64(0)
        for index in 1:8
            value = (value << 8) | UInt64(digest[offset + index])
        end
        value
    end
end

function add!(accumulator::Accumulator, payload::AbstractString, terms::Int = 0)
    accumulator.count += 1
    accumulator.terms += terms
    limbs = sha_limbs(payload)
    accumulator.xor = ntuple(i -> accumulator.xor[i] ⊻ limbs[i], 4)
    accumulator.total = ntuple(i -> accumulator.total[i] + limbs[i], 4)
    return nothing
end

mutable struct Fingerprints
    overall::Dict{Tuple{String, String, Int}, Accumulator}
    buckets::Dict{Tuple{String, String, Int, Int}, Accumulator}
    excluded::Dict{Tuple{String, String}, Int}
end

Fingerprints() = Fingerprints(Dict(), Dict(), Dict())

function ensure!(fingerprints::Fingerprints, kind, group)
    for precision in PRECISIONS
        get!(Accumulator, fingerprints.overall, (kind, group, precision))
    end
    return nothing
end

function add!(fingerprints::Fingerprints, kind, group, key, records, terms::Int = 0)
    bucket = Int(first(SHA.sha256(codeunits(key))))
    for (precision, payload) in pairs(records)
        overall = get!(Accumulator, fingerprints.overall, (kind, group, precision))
        per_bucket = get!(Accumulator, fingerprints.buckets, (kind, group, precision, bucket))
        add!(overall, payload, terms)
        add!(per_bucket, payload, terms)
    end
    return nothing
end

canonical_component(value) = replace(string(value), r"[^A-Za-z0-9]" => "")
entity_key(values) = join(canonical_component.(values), '~')

function canonical_time(label::AbstractString)
    strategic = match(r"sp(\d+)", label)
    representative = match(r"rp(\d+)", label)
    scenario = match(r"sc(\d+)", label)
    hour = match(r"t(\d+)", label)
    parts = String[]
    strategic === nothing || push!(parts, "sp$(strategic.captures[1])")
    representative === nothing || push!(parts, "rp$(representative.captures[1])")
    if scenario === nothing
        # TimeStruct omits `sc1` from operational labels when there is exactly one
        # scenario; Pyomo retains `scenario1` in every operational index.
        representative === nothing || push!(parts, "sc1")
    else
        push!(parts, "sc$(scenario.captures[1])")
    end
    hour === nothing || push!(parts, "t$(hour.captures[1])")
    return join(parts, '_')
end

function _inside(name::AbstractString)
    opening = findfirst('[', name)
    closing = findlast(']', name)
    opening === nothing && error("missing [ in model name: $name")
    closing === nothing && error("missing ] in model name: $name")
    return name[nextind(name, opening):prevind(name, closing)]
end

_fields(name::AbstractString) = strip.(split(_inside(name), ','))

function row_key(family::String, constraint::JuMP.ConstraintRef)
    fields = _fields(JuMP.name(constraint))
    time_index = findfirst(field -> occursin(r"sp\d+", field), fields)
    time_index === nothing && error("missing strategic period in row: $(JuMP.name(constraint))")
    entities = fields[begin:(time_index - 1)]
    time_text = join(fields[time_index:end], '_')
    time = canonical_time(time_text)
    return "$family|$(entity_key(entities))|$time"
end

function emissions_key(constraint::JuMP.ConstraintRef)
    fields = _fields(JuMP.name(constraint))
    strategic = only(filter(field -> occursin(r"sp\d+", field), fields))
    scenario = canonical_component(last(fields))
    return "emissions||$(canonical_time(strategic))_sc$scenario"
end

function variable_base(variable::JuMP.VariableRef)
    name = JuMP.name(variable)
    opening = findfirst('[', name)
    opening === nothing && return name
    return name[begin:prevind(name, opening)]
end

function variable_parts(variable::JuMP.VariableRef)
    name = JuMP.name(variable)
    fields = _fields(name)
    base = variable_base(variable)
    info = get(VARIABLES, base, nothing)
    info === nothing && error("unknown Industry variable: $name")
    canonical, _ = info
    time_index = findfirst(field -> occursin(r"sp\d+", field), fields)
    time_index === nothing && error("missing period in Industry variable: $name")
    entity = fields[begin:(time_index - 1)]
    time = canonical_time(join(fields[time_index:end], '_'))
    key = "$canonical|$(entity_key(entity))|$time"
    return (; base, canonical, entity, time, key)
end

function float_text(value::Float64, precision::Int)
    value == 0.0 && (value = 0.0)
    isinf(value) && return value > 0 ? "+inf" : "-inf"
    return Printf.format(Printf.Format("%.$(precision)e"), value)
end

function raw_records(key, values)
    return Dict(
        precision => join((key, (float_text(Float64(value), precision) for value in values)...), '\t')
        for precision in PRECISIONS
    )
end

function normalized_records(key, sense, rhs, terms)
    filter!(pair -> last(pair) != 0.0, terms)
    scale = maximum(abs, Iterators.flatten((values(terms), (rhs,))); init = 0.0)
    if scale != 0.0
        for name in keys(terms)
            terms[name] /= scale
        end
        rhs /= scale
    end
    first_value = rhs
    for name in sort!(collect(keys(terms)))
        if terms[name] != 0.0
            first_value = terms[name]
            break
        end
    end
    if first_value < 0.0
        for name in keys(terms)
            terms[name] = -terms[name]
        end
        rhs = -rhs
        sense = sense == "<=" ? ">=" : sense == ">=" ? "<=" : sense
    end
    names = sort!(collect(keys(terms)))
    return Dict(
        precision => join(
            (
                key,
                sense,
                float_text(rhs, precision),
                join(("$name=$(float_text(terms[name], precision))" for name in names), ';'),
            ),
            '\t',
        )
        for precision in PRECISIONS
    )
end

function industry_row_algebra(constraint::JuMP.ConstraintRef; shared::Bool = false)
    object = JuMP.constraint_object(constraint)
    function_ = object.func
    terms = Dict{String, Float64}()
    constant = 0.0
    if function_ isa JuMP.VariableRef
        base = variable_base(function_)
        if haskey(VARIABLES, base)
            key = variable_parts(function_).key
            terms[key] = 1.0
        elseif !shared
            error("unknown variable in dedicated Industry row: $(JuMP.name(function_))")
        end
    elseif function_ isa JuMP.GenericAffExpr
        constant = Float64(function_.constant)
        for (variable, coefficient) in function_.terms
            base = variable_base(variable)
            if haskey(VARIABLES, base)
                key = variable_parts(variable).key
                terms[key] = get(terms, key, 0.0) + Float64(coefficient)
            elseif !shared
                error("unknown variable in dedicated Industry row: $(JuMP.name(variable))")
            end
        end
    else
        error("unsupported Industry constraint function $(typeof(function_))")
    end
    shared && return terms, "==", 0.0
    set = object.set
    if set isa MOI.EqualTo
        return terms, "==", Float64(set.value) - constant
    elseif set isa MOI.LessThan
        return terms, "<=", Float64(set.upper) - constant
    elseif set isa MOI.GreaterThan
        return terms, ">=", Float64(set.lower) - constant
    end
    error("unsupported Industry constraint set $(typeof(set))")
end

function accumulator_fields(accumulator)
    return (
        string(accumulator.count),
        string(accumulator.terms),
        (Printf.format(Printf.Format("%016x"), value) for value in accumulator.xor)...,
        (Printf.format(Printf.Format("%016x"), value) for value in accumulator.total)...,
    )
end

function write_fingerprints(path, fingerprints, metadata)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        for (key, value) in sort!(collect(metadata); by = first)
            println(io, "META\t$key\t$value")
        end
        for ((kind, group), count) in sort!(collect(fingerprints.excluded); by = first)
            println(io, "EXCLUDED\t$kind\t$group\t$count")
        end
        for ((kind, group, precision), accumulator) in sort!(collect(fingerprints.overall); by = first)
            println(io, join(("SUMMARY", kind, group, precision, accumulator_fields(accumulator)...), '\t'))
        end
        for ((kind, group, precision, bucket), accumulator) in sort!(collect(fingerprints.buckets); by = first)
            println(io, join(("BUCKET", kind, group, precision, bucket, accumulator_fields(accumulator)...), '\t'))
        end
    end
    return path
end

function export_fingerprints(model, periods, params, output)
    fingerprints = Fingerprints()
    for (family, _) in DEDICATED_FAMILIES
        ensure!(fingerprints, "row", string(family))
    end
    for (family, _) in SHARED_FAMILIES
        ensure!(fingerprints, "row", string(family))
    end
    ensure!(fingerprints, "row", "emissions")
    for (canonical, _) in values(VARIABLES)
        ensure!(fingerprints, "variable", canonical)
    end
    for group in values(OBJECTIVE_GROUPS)
        ensure!(fingerprints, "objective", group)
    end

    for (family_symbol, component_symbol) in DEDICATED_FAMILIES
        family = string(family_symbol)
        for constraint in model[component_symbol]
            key = row_key(family, constraint)
            terms, sense, rhs = industry_row_algebra(constraint)
            isempty(terms) && error("empty dedicated Industry row: $(JuMP.name(constraint))")
            add!(fingerprints, "row", family, key, normalized_records(key, sense, rhs, terms), length(terms))
        end
    end

    for (family_symbol, component_symbol) in SHARED_FAMILIES
        family = string(family_symbol)
        for constraint in model[component_symbol]
            key = row_key(family, constraint)
            terms, sense, rhs = industry_row_algebra(constraint; shared = true)
            if isempty(terms)
                if family == "biomass_availability"
                    add!(fingerprints, "row", family, key, normalized_records(key, "==", 0.0, terms), 0)
                    continue
                end
                exclusion = ("row", "$family:no_industry_terms")
                fingerprints.excluded[exclusion] = get(fingerprints.excluded, exclusion, 0) + 1
                continue
            end
            add!(fingerprints, "row", family, key, normalized_records(key, sense, rhs, terms), length(terms))
        end
    end

    # InternalEMPIRE places Industry emissions directly in one cap row. Julia uses
    # per-node defining rows and an auxiliary. Eliminate only that audited auxiliary
    # by aggregating the Industry terms from every defining row by strategic scenario.
    emission_terms = Dict{String, Dict{String, Float64}}()
    for constraint in model[:node_emission]
        key = emissions_key(constraint)
        terms, _, _ = industry_row_algebra(constraint; shared = true)
        if isempty(terms)
            exclusion = ("row", "emissions:no_industry_terms")
            fingerprints.excluded[exclusion] = get(fingerprints.excluded, exclusion, 0) + 1
            continue
        end
        aggregate = get!(Dict{String, Float64}, emission_terms, key)
        for (column, coefficient) in terms
            aggregate[column] = get(aggregate, column, 0.0) + coefficient
        end
    end
    for (key, terms) in emission_terms
        add!(fingerprints, "row", "emissions", key, normalized_records(key, "==", 0.0, terms), length(terms))
    end

    for base in sort!(collect(keys(VARIABLES)))
        canonical = first(VARIABLES[base])
        for variable in model[Symbol(base)]
            parts = variable_parts(variable)
            lower = JuMP.has_lower_bound(variable) ? JuMP.lower_bound(variable) : -Inf
            upper = JuMP.has_upper_bound(variable) ? JuMP.upper_bound(variable) : Inf
            add!(fingerprints, "variable", canonical, parts.key, raw_records(parts.key, (lower, upper)))
        end
    end

    objective = JuMP.objective_function(model)
    for (variable, coefficient) in objective.terms
        base = variable_base(variable)
        group = get(OBJECTIVE_GROUPS, base, nothing)
        group === nothing && continue
        key = variable_parts(variable).key
        add!(fingerprints, "objective", group, key, raw_records(key, (coefficient,)))
    end

    write_fingerprints(
        output,
        fingerprints,
        Dict(
            "schema" => 1,
            "side" => "OpenEMPIRE.jl",
            "scope" => "industry",
            "periods" => length(collect(strat_periods(periods))),
            "weather_scenarios" => params.NaturalGas.weatherScenarioCount,
            "gas_scenarios" => params.NaturalGas.gasScenarioCount,
            "operational_periods" => length(periods),
            "precisions" => join(PRECISIONS, ','),
            "buckets" => BUCKETS,
        ),
    )
    println("industry_algebra_fingerprint=$output")
    return nothing
end

function main(args)
    length(args) == 3 || error(
        "usage: write_industry_algebra_fingerprint.jl CONFIG DATA_FOLDER OUTPUT",
    )
    config, data_folder, output = args
    model, periods, _, params = OpenEMPIRE.create_model(
        config,
        data_folder;
        input_format = :csv,
        include_string_names = true,
    )
    export_fingerprints(model, periods, params, output)
end

main(ARGS)
