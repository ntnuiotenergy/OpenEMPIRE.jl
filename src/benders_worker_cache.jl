const BendersProfile = Dict{Any, Float64}
const BendersProfileMap = Dict{String, BendersProfile}
const BendersPairProfileMap = Dict{Tuple{String, String}, BendersProfile}

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
    sets::EmpireSets
    params::BendersSubproblemParams
    discounter
end

const _BENDERS_WORKER_CACHE = Ref{Union{Nothing, BendersSubproblemCache}}(nothing)

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

function _benders_slice_profile_map(profiles, keys)
    return BendersProfileMap(
        key => _benders_slice_profile(profile, keys)
        for (key, profile) in profiles
    )
end

function _benders_slice_pair_profile_map(profiles, keys)
    return BendersPairProfileMap(
        key => _benders_slice_profile(profile, keys)
        for (key, profile) in profiles
    )
end

function _benders_float_map(values)
    return Dict{String, Float64}(key => Float64(value) for (key, value) in values)
end

function _benders_pair_float_map(values)
    return Dict{Tuple{String, String}, Float64}(
        key => Float64(value) for (key, value) in values
    )
end

function _benders_make_cache(
    sets,
    par,
    discounter,
    strategic_periods,
    operational_periods,
    scenario_periods,
)
    strategic_keys = unique(Any[strategic_periods...])
    operational_keys = unique(Any[operational_periods...])
    scenario_keys = unique(Any[scenario_periods...])

    params = BendersSubproblemParams(
        _benders_slice_profile_map(par.sload, operational_keys),
        _benders_slice_pair_profile_map(par.genCapAvail, operational_keys),
        _benders_float_map(par.genCapAvailType),
        _benders_slice_profile_map(par.genEfficiency, strategic_keys),
        _benders_float_map(par.genRampUpCap),
        _benders_float_map(par.genCO2Content),
        _benders_slice_profile_map(
            par.genMaxBiomethaneAvailability,
            strategic_keys,
        ),
        _benders_slice_profile_map(par.maxRegHydroGen, scenario_keys),
        _benders_float_map(par.maxHydroNode),
        _benders_slice_profile_map(par.genMargCost, operational_keys),
        _benders_slice_profile_map(par.nodeLostLoadCost, operational_keys),
        _benders_float_map(par.storageBleedEff),
        _benders_float_map(par.storageChargeEff),
        _benders_float_map(par.storageDischargeEff),
        _benders_float_map(par.storageDiscToCharRatio),
        _benders_float_map(par.storOperationalInit),
        _benders_pair_float_map(par.lineEfficiency),
        par.availableBioEnergy === nothing ?
            nothing :
            _benders_slice_profile(par.availableBioEnergy, strategic_keys),
        par.CO2cap === nothing ?
            nothing :
            _benders_slice_profile(par.CO2cap, strategic_keys),
    )

    return BendersSubproblemCache(sets, params, discounter)
end

function _benders_make_inv_period_cache(sets, par, discounter, subproblems)
    strategic_periods = Any[subproblems...]
    operational_periods = Any[t for sp in subproblems for t in sp]
    scenario_periods = Any[sc for sp in subproblems for sc in opscenarios(sp)]
    return _benders_make_cache(
        sets,
        par,
        discounter,
        strategic_periods,
        operational_periods,
        scenario_periods,
    )
end

function _benders_make_scenario_cache(sets, par, discounter, subproblems)
    strategic_periods = Any[sp for (sp, _) in subproblems]
    operational_periods = Any[
        t for (_, scenarios) in subproblems for scenario in scenarios for t in scenario
    ]
    scenario_periods = Any[
        scenario for (_, scenarios) in subproblems for scenario in scenarios
    ]
    return _benders_make_cache(
        sets,
        par,
        discounter,
        strategic_periods,
        operational_periods,
        scenario_periods,
    )
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