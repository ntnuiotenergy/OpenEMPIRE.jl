#!/usr/bin/env julia

"""Build OpenEMPIRE.jl without optimizing and fingerprint its Hydrogen/CO₂ algebra."""

using JuMP
using OpenEMPIRE
using Printf
using SHA
using TimeStruct

const MOI = JuMP.MOI

const PRECISIONS = (9, 12)
const BUCKETS = 256

const FAMILIES = (
    :flow_balance => :hydrogen_flow_balance,
    :pipeline_capacity => :hydrogen_pipeline_capacity,
    :electrolyzer_conversion => :hydrogen_electrolyzer_conversion,
    :electrolyzer_capacity => :hydrogen_electrolyzer_capacity,
    :reformer_capacity => :hydrogen_reformer_capacity,
    :reformer_conversion => :hydrogen_reformer_ton_mwh,
    :reformer_natural_gas => :hydrogen_reformer_natural_gas,
    :reformer_ramp => :hydrogen_reformer_ramp,
    :storage_compression => :hydrogen_storage_compression,
    :storage_balance => :hydrogen_storage_balance,
    :storage_cyclic => :hydrogen_storage_cyclic,
    :storage_capacity => :hydrogen_storage_capacity,
    :import_capacity => :hydrogen_import_capacity,
    :import_conversion => :hydrogen_import_ton_mwh,
    :co2_pipeline_capacity => :co2_pipeline_capacity,
    :co2_flow_balance => :co2_flow_balance,
    :co2_hourly => :co2_sequestration_hourly_capacity,
    :co2_total => :co2_total_sequestration,
    :transport_electricity => :meet_transport_electricity_demand,
    :transport_hydrogen => :meet_transport_hydrogen_demand,
    :repurpose_capacity => :hydrogen_repurpose_capacity,
    :pipeline_installed => :hydrogen_pipeline_installed,
    :electrolyzer_installed => :hydrogen_electrolyzer_installed,
    :reformer_installed => :hydrogen_reformer_installed,
    :storage_max => :hydrogen_storage_max,
    :storage_installed => :hydrogen_storage_installed,
    :import_installed => :hydrogen_import_installed,
    :co2_pipeline_installed => :co2_pipeline_installed,
    :co2_site_max => :co2_sequestration_max_installed,
)

const VARIABLES = Dict(
    "hydrogenImportTon" => ("import_ton", true),
    "hydrogenImportMWh" => ("import_mwh", true),
    "electrolyzerHydrogen" => ("electrolyzer_h2", true),
    "electrolyzerElectricity" => ("electrolyzer_power", true),
    "reformerHydrogenTon" => ("reformer_ton", true),
    "reformerHydrogenMWh" => ("reformer_mwh", true),
    "reformerNaturalGas" => ("reformer_gas", true),
    "hydrogenPipelineFlow" => ("pipeline_flow", true),
    "hydrogenStorageLevel" => ("storage_level", true),
    "hydrogenStorageCharge" => ("storage_charge", true),
    "hydrogenStorageDischarge" => ("storage_discharge", true),
    "hydrogenStorageCompressionPower" => ("storage_power", true),
    "transportElectricityDemandMet" => ("transport_electricity_met", true),
    "transportElectricityDemandShed" => ("transport_electricity_shed", true),
    "transportHydrogenDemandMet" => ("transport_hydrogen_met", true),
    "transportHydrogenDemandShed" => ("transport_hydrogen_shed", true),
    "co2PipelineFlow" => ("co2_flow", true),
    "co2Sequestered" => ("co2_sequestered", true),
    "genOperational" => ("generation", true),
    "hydrogenForPower" => ("hydrogen_for_power", true),
    "hydrogenImportCapBuilt" => ("import_built", false),
    "hydrogenImportCapInstalled" => ("import_total", false),
    "electrolyzerCapBuilt" => ("electrolyzer_built", false),
    "electrolyzerCapInstalled" => ("electrolyzer_total", false),
    "reformerCapBuilt" => ("reformer_built", false),
    "reformerCapInstalled" => ("reformer_total", false),
    "hydrogenPipelineCapBuilt" => ("pipeline_built", false),
    "hydrogenRepurposedGasPipelineCapBuilt" => ("repurposed_built", false),
    "hydrogenPipelineCapInstalled" => ("pipeline_total", false),
    "hydrogenStorageCapBuilt" => ("storage_built", false),
    "hydrogenStorageCapInstalled" => ("storage_total", false),
    "co2PipelineCapBuilt" => ("co2_pipeline_built", false),
    "co2PipelineCapInstalled" => ("co2_pipeline_total", false),
    "co2SequestrationCapBuilt" => ("co2_site_built", false),
    "hydrogenRepurposedGasPipelineCapInstalled" => ("repurposed_installed", false),
    "co2SequestrationCapInstalled" => ("co2_site_installed", false),
)

const SHARED_VARIABLE_BASES = Set(
    key for (key, (canonical, _)) in VARIABLES if
    canonical ∉ ("repurposed_installed", "co2_site_installed")
)

const UNDIRECTED_VARIABLES = Set((
    "pipeline_built",
    "pipeline_total",
    "co2_pipeline_built",
    "co2_pipeline_total",
))

const OBJECTIVE_GROUPS = Dict(
    "hydrogenImportTon" => "terminal_import",
    "reformerHydrogenTon" => "reformer_operation",
    "transportElectricityDemandShed" => "transport_electricity_shed",
    "transportHydrogenDemandShed" => "transport_hydrogen_shed",
    "electrolyzerCapBuilt" => "electrolyzer_investment",
    "reformerCapBuilt" => "reformer_investment",
    "hydrogenPipelineCapBuilt" => "hydrogen_pipeline_investment",
    "hydrogenRepurposedGasPipelineCapBuilt" => "repurposed_pipeline_investment",
    "hydrogenStorageCapBuilt" => "storage_investment",
    "hydrogenImportCapBuilt" => "terminal_investment",
    "co2PipelineCapBuilt" => "co2_pipeline_investment",
    "co2SequestrationCapBuilt" => "co2_site_investment",
)

const HYDROGEN_GENERATORS = Set(("HydrogenCCGT", "HydrogenOCGT", "Hydrogenfuelcell"))

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
end

Fingerprints() = Fingerprints(Dict(), Dict())

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

function entity_key(values; undirected::Bool = false)
    parts = canonical_component.(values)
    if undirected && length(parts) >= 2 && parts[2] < parts[1]
        parts[1], parts[2] = parts[2], parts[1]
    end
    return join(parts, '~')
end

function canonical_time(label::AbstractString)
    strategic = match(r"sp(\d+)", label)
    representative = match(r"rp(\d+)", label)
    scenario = match(r"sc(\d+)", label)
    hour = match(r"t(\d+)", label)
    parts = String[]
    strategic === nothing || push!(parts, "sp$(strategic.captures[1])")
    representative === nothing || push!(parts, "rp$(representative.captures[1])")
    scenario === nothing || push!(parts, "sc$(scenario.captures[1])")
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

function _quoted_entities(text::AbstractString)
    return [matched.captures[1] for matched in eachmatch(r"\"([^\"]*)\"", text)]
end

function row_key(family::String, constraint::JuMP.ConstraintRef)
    text = _inside(JuMP.name(constraint))
    quoted = _quoted_entities(text)
    entity = if !isempty(quoted)
        quoted
    else
        [first(split(text, ','; limit = 2))]
    end
    undirected = family in ("pipeline_installed", "co2_pipeline_installed")
    time = if family == "co2_total"
        "sc$(last(split(text, ',')))"
    else
        labels = collect(eachmatch(r"sp\d+(?:-rp\d+)?(?:-sc\d+)?(?:-t\d+)?", text))
        isempty(labels) ? "" : canonical_time(last(labels).match)
    end
    return "$family|$(entity_key(entity; undirected))|$time"
end

function variable_parts(variable::JuMP.VariableRef)
    name = JuMP.name(variable)
    opening = findfirst('[', name)
    opening === nothing && error("unnamed/non-indexed Hydrogen variable: $name")
    base = name[begin:prevind(name, opening)]
    values = split(_inside(name), ',')
    info = get(VARIABLES, base, nothing)
    info === nothing && error("unknown Hydrogen row variable family: $base ($name)")
    canonical, operational = info
    time = canonical_time(last(values))
    entity = values[begin:(end - 1)]
    undirected = canonical in UNDIRECTED_VARIABLES
    key = "$canonical|$(entity_key(entity; undirected))|$time"
    return (; base, canonical, operational, entity, time, key)
end

function variable_base(variable::JuMP.VariableRef)
    name = JuMP.name(variable)
    opening = findfirst('[', name)
    opening === nothing && return name
    return name[begin:prevind(name, opening)]
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

function row_algebra(constraint::JuMP.ConstraintRef)
    object = JuMP.constraint_object(constraint)
    function_ = object.func
    terms = Dict{String, Float64}()
    constant = 0.0
    if function_ isa JuMP.VariableRef
        parts = variable_parts(function_)
        terms[parts.key] = 1.0
    elseif function_ isa JuMP.GenericAffExpr
        constant = Float64(function_.constant)
        for (variable, coefficient) in function_.terms
            parts = variable_parts(variable)
            terms[parts.key] = get(terms, parts.key, 0.0) + Float64(coefficient)
        end
    else
        error("unsupported Hydrogen constraint function $(typeof(function_))")
    end
    set = object.set
    if set isa MOI.EqualTo
        return terms, "==", Float64(set.value) - constant
    elseif set isa MOI.LessThan
        return terms, "<=", Float64(set.upper) - constant
    elseif set isa MOI.GreaterThan
        return terms, ">=", Float64(set.lower) - constant
    end
    error("unsupported Hydrogen constraint set $(typeof(set))")
end

function transformed_terms(family, key, terms)
    transformed = Dict{String, Float64}()
    for (column, coefficient) in terms
        canonical, entity, time = split(column, '|'; limit = 3)
        if family == "pipeline_installed" && canonical == "repurposed_installed"
            target = parse(Int, match(r"sp(\d+)", time).captures[1])
            for period in 1:target
                replacement = "repurposed_built|$entity|sp$period"
                transformed[replacement] = get(transformed, replacement, 0.0) + coefficient
            end
        else
            transformed[column] = get(transformed, column, 0.0) + coefficient
        end
    end
    return transformed
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
    open(path, "w") do io
        for (key, value) in sort!(collect(metadata); by = first)
            println(io, "META\t$key\t$value")
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
    for (family_symbol, component_symbol) in FAMILIES
        family = string(family_symbol)
        component = model[component_symbol]
        for constraint in component
            key = row_key(family, constraint)
            terms, sense, rhs = row_algebra(constraint)
            terms = transformed_terms(family, key, terms)
            add!(
                fingerprints,
                "row",
                family,
                key,
                normalized_records(key, sense, rhs, terms),
                length(terms),
            )
        end
    end

    for base in sort!(collect(SHARED_VARIABLE_BASES))
        canonical = first(VARIABLES[base])
        for variable in model[Symbol(base)]
            parts = variable_parts(variable)
            if canonical == "generation" && !(parts.entity[2] in HYDROGEN_GENERATORS)
                continue
            end
            lower = JuMP.has_lower_bound(variable) ? JuMP.lower_bound(variable) : -Inf
            upper = JuMP.has_upper_bound(variable) ? JuMP.upper_bound(variable) : Inf
            add!(
                fingerprints,
                "variable",
                canonical,
                parts.key,
                raw_records(parts.key, (lower, upper)),
            )
        end
    end

    objective = JuMP.objective_function(model)
    for (variable, coefficient) in objective.terms
        base = variable_base(variable)
        base == "genOperational" || haskey(OBJECTIVE_GROUPS, base) || continue
        parts = variable_parts(variable)
        group = get(OBJECTIVE_GROUPS, parts.base, nothing)
        if parts.base == "genOperational"
            generator = parts.entity[2]
            generator in HYDROGEN_GENERATORS && (group = "generation_$generator")
        end
        group === nothing && continue
        add!(
            fingerprints,
            "objective",
            group,
            parts.key,
            raw_records(parts.key, (coefficient,)),
        )
    end

    write_fingerprints(
        output,
        fingerprints,
        Dict(
            "schema" => 1,
            "side" => "OpenEMPIRE.jl",
            "periods" => length(collect(strat_periods(periods))),
            "weather_scenarios" => params.NaturalGas.weatherScenarioCount,
            "gas_scenarios" => params.NaturalGas.gasScenarioCount,
            "operational_periods" => length(periods),
            "precisions" => join(PRECISIONS, ','),
            "buckets" => BUCKETS,
        ),
    )
    println("hydrogen_algebra_fingerprint=$output")
    return nothing
end

function main(args)
    length(args) == 3 || error(
        "usage: write_hydrogen_algebra_fingerprint.jl CONFIG DATA_FOLDER OUTPUT",
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
