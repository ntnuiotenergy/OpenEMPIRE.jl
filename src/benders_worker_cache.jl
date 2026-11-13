const BendersProfile = Dict{Any, Float64}
const BendersProfileMap = Dict{String, BendersProfile}
const BendersPairProfileMap = Dict{Tuple{String, String}, BendersProfile}

incoming_arcs(sets::EmpireSets, node) = [
    from for (from, to) in arcs(sets) if to == node
]
outgoing_arcs(sets::EmpireSets, node) = [
    to for (from, to) in arcs(sets) if from == node
]

struct BendersSubproblemSets
    Generator::Vector{GenId}
    ThermalGenerators::Set{GenId}
    HydroGenerator::Set{GenId}
    RegHydroGenerator::Set{GenId}
    Storage::Vector{StorId}
    Node::Vector{NodeId}
    OffshoreEnergyHub::Set{NodeId}
    DirectionalLink::Vector{Arc}
    Corridors::Vector{Arc}
    GeneratorsByNode::Dict{NodeId, Vector{GenId}}
    StoragesByNode::Dict{NodeId, Vector{StorId}}
    IncomingByNode::Dict{NodeId, Vector{NodeId}}
    OutgoingByNode::Dict{NodeId, Vector{NodeId}}
end

nodes(sets::BendersSubproblemSets) = sets.Node
offshore_energy_hubs(sets::BendersSubproblemSets) = sets.OffshoreEnergyHub
generators(sets::BendersSubproblemSets) = sets.Generator
thermal_generators(sets::BendersSubproblemSets) = sets.ThermalGenerators
hydro_generators(sets::BendersSubproblemSets) = sets.HydroGenerator
reg_hydro_generators(sets::BendersSubproblemSets) = sets.RegHydroGenerator
storages(sets::BendersSubproblemSets) = sets.Storage
arcs(sets::BendersSubproblemSets) = sets.DirectionalLink
bidir_arcs(sets::BendersSubproblemSets) = sets.Corridors
generators(sets::BendersSubproblemSets, n) =
    get(sets.GeneratorsByNode, n, GenId[])
storages(sets::BendersSubproblemSets, n) =
    get(sets.StoragesByNode, n, StorId[])
incoming_arcs(sets::BendersSubproblemSets, n) =
    get(sets.IncomingByNode, n, NodeId[])
outgoing_arcs(sets::BendersSubproblemSets, n) =
    get(sets.OutgoingByNode, n, NodeId[])
node_generators(sets::BendersSubproblemSets) = [
    (node, generator)
    for (node, generators_at_node) in sets.GeneratorsByNode
    for generator in generators_at_node
]
node_storages(sets::BendersSubproblemSets) = [
    (node, storage)
    for (node, storages_at_node) in sets.StoragesByNode
    for storage in storages_at_node
]
is_thermal(sets::BendersSubproblemSets, g) = g in sets.ThermalGenerators
is_hydro(sets::BendersSubproblemSets, g) = g in sets.HydroGenerator
is_reg_hydro(sets::BendersSubproblemSets, g) = g in sets.RegHydroGenerator

struct BendersSubproblemParams
    sload::BendersProfileMap
    genCapAvail::BendersPairProfileMap
    genCapAvailType::Dict{String, Float64}
    genEfficiency::BendersProfileMap
    genRampUpCap::Dict{String, Float64}
    genCO2Content::Dict{String, Float64}
    genMaxBiomethaneAvailability::BendersProfileMap
    maxRegHydroGen::BendersProfileMap
    maxHydroNode::Dict{String, Float64}
    genMargCost::BendersProfileMap
    nodeLostLoadCost::BendersProfileMap
    storageBleedEff::Dict{String, Float64}
    storageChargeEff::Dict{String, Float64}
    storageDischargeEff::Dict{String, Float64}
    storageDiscToCharRatio::Dict{String, Float64}
    storOperationalInit::Dict{String, Float64}
    lineEfficiency::Dict{Tuple{String, String}, Float64}
    availableBioEnergy::Union{Nothing, BendersProfile}
    CO2cap::Union{Nothing, BendersProfile}
end

struct BendersSubproblemCache
    sets::BendersSubproblemSets
    params::Dict{Any, BendersSubproblemParams}
    discounter
end

const _BENDERS_WORKER_CACHE = Ref{Union{Nothing, BendersSubproblemCache}}(nothing)

function _benders_make_sets(sets::EmpireSets)
    return BendersSubproblemSets(
        copy(generators(sets)),
        Set(thermal_generators(sets)),
        Set(hydro_generators(sets)),
        Set(reg_hydro_generators(sets)),
        copy(storages(sets)),
        copy(nodes(sets)),
        Set(offshore_energy_hubs(sets)),
        copy(arcs(sets)),
        copy(bidir_arcs(sets)),
        Dict(node => copy(generators(sets, node)) for node in nodes(sets)),
        Dict(node => copy(storages(sets, node)) for node in nodes(sets)),
        Dict(
            node => [from for (from, to) in arcs(sets) if to == node]
            for node in nodes(sets)
        ),
        Dict(
            node => [to for (from, to) in arcs(sets) if from == node]
            for node in nodes(sets)
        ),
    )
end

function _benders_slice_profile(profile, keys)
    values = BendersProfile()
    for key in keys
        try
            values[key] = Float64(profile[key])
        catch error
            error isa KeyError || rethrow()
        end
    end
    return values
end

function _benders_slice_profile_map(profiles, keys; allowed_keys = nothing)
    return BendersProfileMap(
        key => _benders_slice_profile(profile, keys)
        for (key, profile) in profiles
        if allowed_keys === nothing || key in allowed_keys
    )
end

function _benders_slice_pair_profile_map(profiles, keys; allowed_keys = nothing)
    return BendersPairProfileMap(
        key => _benders_slice_profile(profile, keys)
        for (key, profile) in profiles
        if allowed_keys === nothing || key in allowed_keys
    )
end

function _benders_float_map(values; allowed_keys = nothing)
    return Dict{String, Float64}(
        key => Float64(value)
        for (key, value) in values
        if allowed_keys === nothing || key in allowed_keys
    )
end

function _benders_pair_float_map(values; allowed_keys = nothing)
    return Dict{Tuple{String, String}, Float64}(
        key => Float64(value)
        for (key, value) in values
        if allowed_keys === nothing || key in allowed_keys
    )
end

function _benders_make_params(
    sets,
    par,
    strategic_periods,
    operational_periods,
    scenario_periods,
)
    node_keys = Set(nodes(sets))
    generator_keys = Set(generators(sets))
    storage_keys = Set(storages(sets))
    thermal_generator_keys = Set(thermal_generators(sets))
    node_generator_keys = Set(node_generators(sets))
    line_keys = Set(arcs(sets))
    for (m, n) in arcs(sets)
        push!(line_keys, (n, m))
    end

    strategic_keys = unique(Any[strategic_periods...])
    operational_keys = unique(Any[operational_periods...])
    scenario_keys = unique(Any[scenario_periods...])

    return BendersSubproblemParams(
        _benders_slice_profile_map(
            par.sload,
            operational_keys;
            allowed_keys = node_keys,
        ),
        _benders_slice_pair_profile_map(
            par.genCapAvail,
            operational_keys;
            allowed_keys = node_generator_keys,
        ),
        _benders_float_map(par.genCapAvailType; allowed_keys = generator_keys),
        _benders_slice_profile_map(
            par.genEfficiency,
            strategic_keys;
            allowed_keys = generator_keys,
        ),
        _benders_float_map(
            par.genRampUpCap;
            allowed_keys = thermal_generator_keys,
        ),
        _benders_float_map(par.genCO2Content; allowed_keys = generator_keys),
        _benders_slice_profile_map(
            par.genMaxBiomethaneAvailability,
            strategic_keys;
            allowed_keys = node_keys,
        ),
        _benders_slice_profile_map(
            par.maxRegHydroGen,
            scenario_keys;
            allowed_keys = node_keys,
        ),
        _benders_float_map(par.maxHydroNode; allowed_keys = node_keys),
        _benders_slice_profile_map(
            par.genMargCost,
            operational_keys;
            allowed_keys = generator_keys,
        ),
        _benders_slice_profile_map(
            par.nodeLostLoadCost,
            operational_keys;
            allowed_keys = node_keys,
        ),
        _benders_float_map(par.storageBleedEff; allowed_keys = storage_keys),
        _benders_float_map(par.storageChargeEff; allowed_keys = storage_keys),
        _benders_float_map(par.storageDischargeEff; allowed_keys = storage_keys),
        _benders_float_map(
            par.storageDiscToCharRatio;
            allowed_keys = storage_keys,
        ),
        _benders_float_map(par.storOperationalInit; allowed_keys = storage_keys),
        _benders_pair_float_map(par.lineEfficiency; allowed_keys = line_keys),
        par.availableBioEnergy === nothing ?
            nothing :
            _benders_slice_profile(par.availableBioEnergy, strategic_keys),
        par.CO2cap === nothing ?
            nothing :
            _benders_slice_profile(par.CO2cap, strategic_keys),
    )
end

function _benders_make_inv_period_cache(sets, par, discounter, subproblems)
    params = Dict{Any, BendersSubproblemParams}(
        sp => _benders_make_params(
            sets,
            par,
            [sp],
            Any[t for t in sp],
            Any[sc for sc in opscenarios(sp)],
        )
        for sp in subproblems
    )
    return BendersSubproblemCache(_benders_make_sets(sets), params, discounter)
end

function _benders_make_scenario_cache(sets, par, discounter, subproblems)
    params = Dict{Any, BendersSubproblemParams}(
        (sp, scenario_index) => _benders_make_params(
            sets,
            par,
            [sp],
            Any[t for scenario in scenarios for t in scenario],
            Any[scenario for scenario in scenarios],
        )
        for (sp, scenario_index, scenarios) in subproblems
    )
    return BendersSubproblemCache(_benders_make_sets(sets), params, discounter)
end

function initialize_benders_worker_cache!(cache::BendersSubproblemCache)
    _BENDERS_WORKER_CACHE[] = cache
    return nothing
end

function _benders_worker_cache()
    cache = _BENDERS_WORKER_CACHE[]
    cache === nothing &&
        error("Benders worker cache has not been initialized")
    return cache
end

function _benders_initialize_worker_cache!(worker, cache)
    isdefined(Main, :Distributed) ||
        error("Distributed must be loaded before initializing Benders workers")
    Main.Distributed.remotecall_wait(
        initialize_benders_worker_cache!,
        worker,
        cache,
    )
    return nothing
end